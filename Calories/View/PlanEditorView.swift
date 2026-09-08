import SwiftUI

/// Настройка плана: цепочка фаз, недельный цикл и расчёт под них.
///
/// Отдельно от экрана плана намеренно. Настраивают план один раз, а следят за ним
/// каждую неделю — это две разные работы с разной частотой, и на одном экране
/// главное (как идёт) оказывалось зажато между полем ввода и степпером.
struct PlanEditorView: View {
    var store: CalorieStore
    @Environment(\.dismiss) private var dismiss

    @State private var phases: [PlanPhase]
    @State private var cyclingEnabled: Bool
    @State private var weekendStyle: WeekendStyle

    init(store: CalorieStore) {
        self.store = store
        // Новый план начинается с одной фазы дефицита: это то, зачем сюда
        // заходят чаще всего, и пустой список нечем показать.
        _phases = State(initialValue: store.plan?.phases
                        ?? [PlanPhase(intent: .cut, durationWeeks: 8)])
        _cyclingEnabled = State(initialValue: store.plan?.cyclingEnabled ?? false)
        _weekendStyle = State(initialValue: store.plan?.weekendStyle ?? .satSun)
    }

    private var currentWeight: Double {
        store.latestWeight?.weightKg ?? store.profile?.weightKg ?? 0
    }

    private var startWeight: Double {
        store.plan?.startWeightKg ?? currentWeight
    }

    private var tdee: Double {
        store.profile?.tdee ?? Double(store.dailyGoal)
    }

    private var draftPlan: Plan? {
        guard startWeight > 0, !phases.isEmpty else { return nil }
        return Plan(
            startDate: store.plan?.startDate ?? Date(),
            startWeightKg: startWeight,
            phases: phases,
            cyclingEnabled: cyclingEnabled,
            weekendStyle: weekendStyle
        )
    }

    var body: some View {
        Form {
                Section {
                    HStack {
                        Text("Текущий вес")
                        Spacer()
                        Text(String(format: "%.1f \(String(localized: "кг"))", currentWeight))
                            .foregroundStyle(.secondary)
                    }
                    if let plan = store.plan, plan.startWeightKg != currentWeight {
                        HStack {
                            Text("Старт плана")
                            Spacer()
                            Text(String(format: "%.1f \(String(localized: "кг"))", plan.startWeightKg))
                                .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text(store.latestWeight != nil
                         ? "Взято из последнего взвешивания."
                         : "Взято из профиля — стоит записать актуальный вес на экране «Вес».")
                }

                Section {
                    ForEach($phases) { $phase in
                        NavigationLink {
                            PlanPhaseEditorView(phase: $phase,
                                                startWeightKg: weight(atStartOf: phase),
                                                isFirst: phases.first?.id == phase.id)
                        } label: {
                            phaseRow(phase)
                        }
                    }
                    .onDelete { offsets in
                        // Последнюю не отдаём: план без единой фазы — это не план.
                        guard phases.count > offsets.count else { return }
                        phases.remove(atOffsets: offsets)
                    }
                    .onMove { phases.move(fromOffsets: $0, toOffset: $1) }

                    Menu {
                        ForEach(PlanIntent.allCases) { intent in
                            Button {
                                phases.append(PlanPhase(intent: intent, durationWeeks: 8))
                            } label: {
                                Label(intent.title, systemImage: intent.symbol)
                            }
                        }
                    } label: {
                        Label("Добавить фазу", systemImage: "plus")
                    }
                } header: {
                    Text("Фазы")
                } footer: {
                    Text("Сушка, выход в поддержание, набор — это один план, а не три. Порядок фаз меняется перетаскиванием, темп каждой считается от веса, с которым она начинается.")
                }

                Section {
                    Toggle("Недельный цикл калорий", isOn: $cyclingEnabled)
                    if cyclingEnabled {
                        Picker("Рефид-дни", selection: $weekendStyle) {
                            ForEach(WeekendStyle.allCases) { style in
                                VStack(alignment: .leading) {
                                    Text(style.title)
                                    Text(style.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .tag(style)
                            }
                        }
                        .pickerStyle(.navigationLink)
                    }
                } footer: {
                    if cyclingEnabled {
                        Text("В \(weekendStyle.title) калорий больше, в остальные дни — меньше. Среднее за неделю остаётся тем же.")
                    } else {
                        Text("Одинаковая норма каждый день. Включи цикл, если хочешь распределить калории по дням недели с рефид-днями.")
                    }
                }

                if cyclingEnabled, let draftPlan {
                    Section("Раскладка по дням") {
                        ForEach(draftPlan.weeklyCalorieBreakdown(tdee: tdee), id: \.label) { day in
                            HStack {
                                Text(day.label)
                                Spacer()
                                Text("\(day.calories) ккал")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if let draftPlan {
                    Section("Расчёт") {
                        resultRow("Дата окончания", draftPlan.endDate.formatted(.dateTime.day().month(.wide)))
                        resultRow("Всего недель", "\(draftPlan.durationWeeks)")
                        // Прогноз, а не цель: целевой вес у цепочки не задают,
                        // его считают по темпам, которые готов держать.
                        resultRow("Вес к финишу", String(format: "%.1f \(String(localized: "кг"))", draftPlan.targetWeightKg))
                        if draftPlan.cyclingEnabled {
                            resultRow("В среднем за день", "\(draftPlan.dailyCalorieTarget(tdee: tdee)) \(String(localized: "ккал"))")
                            resultRow("Сегодня", "\(draftPlan.calorieTarget(for: Date(), tdee: tdee)) \(String(localized: "ккал"))", highlighted: true)
                        } else {
                            resultRow("Дневная цель", "\(draftPlan.dailyCalorieTarget(tdee: tdee)) \(String(localized: "ккал"))", highlighted: true)
                        }

                        if draftPlan.hasAggressivePhase {
                            Label(
                                "В плане есть фаза со слишком резким темпом — она отмечена внутри.",
                                systemImage: "exclamationmark.triangle.fill"
                            )
                            .font(.caption)
                            .foregroundStyle(.orange)
                        }
                    }
                }
        }
        .glassRow()
        .navigationTitle(store.plan == nil ? String(localized: "Новый план") : String(localized: "Изменить план"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                CheckmarkButton {
                    guard let draftPlan else { return }
                    store.startPlan(draftPlan)
                    dismiss()
                }
                .disabled(draftPlan == nil)
                .fontWeight(.semibold)
            }
        }
    }

    /// Вес, с которым фаза начинается, — по фазам до неё.
    private func weight(atStartOf phase: PlanPhase) -> Double {
        guard let index = phases.firstIndex(where: { $0.id == phase.id }) else { return startWeight }
        var weight = startWeight
        for earlier in phases.prefix(index) {
            weight += earlier.weeklyRateKg(fromWeightKg: weight) * Double(earlier.durationWeeks)
        }
        return weight
    }

    private func phaseRow(_ phase: PlanPhase) -> some View {
        let start = weight(atStartOf: phase)
        let end = start + phase.weeklyRateKg(fromWeightKg: start) * Double(phase.durationWeeks)
        return HStack(spacing: 10) {
            Image(systemName: phase.intent.symbol)
                .foregroundStyle(phase.isAggressive ? .orange : .secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(phase.intent.title)
                HStack(spacing: 6) {
                    Text(String(format: String(localized: "%lld нед."), phase.durationWeeks))
                    if phase.intent != .maintenance {
                        Text(verbatim: "·")
                        Text(String(format: "%.2f%%", phase.weeklyRatePercent))
                    }
                    if phase.rampWeeks > 0 {
                        Text(verbatim: "·")
                        Image(systemName: "arrow.turn.right.up")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
            Spacer()
            Text(String(format: "%.1f \(String(localized: "кг"))", end))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func resultRow(_ title: LocalizedStringKey, _ value: String, highlighted: Bool = false) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(highlighted ? .primary : .secondary)
            Spacer()
            Text(value)
                .font(highlighted ? .body.weight(.semibold) : .body)
                .foregroundStyle(highlighted ? .green : .primary)
        }
    }
}
