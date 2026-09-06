import SwiftUI

/// Настройка плана: целевой вес, срок, недельный цикл и расчёт под них.
///
/// Отдельно от экрана плана намеренно. Настраивают план один раз, а следят за ним
/// каждую неделю — это две разные работы с разной частотой, и на одном экране
/// главное (как идёт) оказывалось зажато между полем ввода и степпером.
struct PlanEditorView: View {
    var store: CalorieStore
    @Environment(\.dismiss) private var dismiss

    @State private var targetWeightText: String
    @FocusState private var targetWeightFocused: Bool
    @State private var durationWeeks: Int
    @State private var cyclingEnabled: Bool
    @State private var weekendStyle: WeekendStyle

    init(store: CalorieStore) {
        self.store = store
        let fallbackStart = store.latestWeight?.weightKg ?? store.profile?.weightKg ?? 70
        _targetWeightText = State(initialValue: String(format: "%.1f", store.plan?.targetWeightKg ?? fallbackStart))
        _durationWeeks = State(initialValue: store.plan?.durationWeeks ?? 8)
        _cyclingEnabled = State(initialValue: store.plan?.cyclingEnabled ?? false)
        _weekendStyle = State(initialValue: store.plan?.weekendStyle ?? .satSun)
    }

    private var currentWeight: Double {
        store.latestWeight?.weightKg ?? store.profile?.weightKg ?? 0
    }

    private var startWeight: Double {
        store.plan?.startWeightKg ?? currentWeight
    }

    private var targetWeight: Double? {
        Double(targetWeightText.replacingOccurrences(of: ",", with: "."))
    }

    private var tdee: Double {
        store.profile?.tdee ?? Double(store.dailyGoal)
    }

    private var draftPlan: Plan? {
        guard let targetWeight, targetWeight > 0, durationWeeks > 0, startWeight > 0 else { return nil }
        return Plan(
            startDate: store.plan?.startDate ?? Date(),
            durationWeeks: durationWeeks,
            startWeightKg: startWeight,
            targetWeightKg: targetWeight,
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

                Section("Целевой вес") {
                    HStack {
                        TextField("70.0", text: $targetWeightText)
                            .keyboardType(.decimalPad)
                            .focused($targetWeightFocused)
                        Text("кг")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Срок") {
                    Stepper("Недель: \(durationWeeks)", value: $durationWeeks, in: 1...52)
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
                        resultRow("Темп", String(format: "%+.2f \(String(localized: "кг/нед"))", draftPlan.weeklyRateKg))
                        if draftPlan.cyclingEnabled {
                            resultRow("В среднем за день", "\(draftPlan.dailyCalorieTarget(tdee: tdee)) \(String(localized: "ккал"))")
                            resultRow("Сегодня", "\(draftPlan.calorieTarget(for: Date(), tdee: tdee)) \(String(localized: "ккал"))", highlighted: true)
                        } else {
                            resultRow("Дневная цель", "\(draftPlan.dailyCalorieTarget(tdee: tdee)) \(String(localized: "ккал"))", highlighted: true)
                        }

                        if draftPlan.isAggressivePace(relativeToWeightKg: startWeight) {
                            Label(
                                "Темп выше ~1% веса в неделю — довольно агрессивно. Можно смягчить, увеличив срок или скорректировав целевой вес.",
                                systemImage: "exclamationmark.triangle.fill"
                            )
                            .font(.caption)
                            .foregroundStyle(.orange)
                        }
                    }
                }
        }
        .glassRow()
        // Клавиатура над цифровым полем закрывает половину экрана, а кнопки
        // «Готово» у decimalPad нет. Одного scrollDismissesKeyboard мало: он
        // живёт на прокрутке, а форма короткая и двигать нечего — жест ловим сами.
        .scrollDismissesKeyboard(.interactively)
        .simultaneousGesture(
            DragGesture(minimumDistance: 24).onEnded { drag in
                if drag.translation.height > 40 { targetWeightFocused = false }
            }
        )
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
