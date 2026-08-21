import SwiftUI

struct PlanView: View {
    @ObservedObject var store: CalorieStore
    @Environment(\.dismiss) private var dismiss

    @State private var targetWeightText: String
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
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Текущий вес")
                        Spacer()
                        Text(String(format: "%.1f кг", currentWeight))
                            .foregroundStyle(.secondary)
                    }
                    if let plan = store.plan, plan.startWeightKg != currentWeight {
                        HStack {
                            Text("Старт плана")
                            Spacer()
                            Text(String(format: "%.1f кг", plan.startWeightKg))
                                .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text(store.latestWeight != nil
                         ? "Взято из последнего взвешивания."
                         : "Взято из профиля — стоит записать актуальный вес на экране «Вес».")
                }

                if let plan = store.plan, let adherence = store.planAdherence() {
                    adherenceSection(plan: plan, adherence: adherence)
                }

                Section("Целевой вес") {
                    HStack {
                        TextField("70.0", text: $targetWeightText)
                            .keyboardType(.decimalPad)
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
                        resultRow("Темп", String(format: "%+.2f кг/нед", draftPlan.weeklyRateKg))
                        if draftPlan.cyclingEnabled {
                            resultRow("В среднем за день", "\(draftPlan.dailyCalorieTarget(tdee: tdee)) ккал")
                            resultRow("Сегодня", "\(draftPlan.calorieTarget(for: Date(), tdee: tdee)) ккал", highlighted: true)
                        } else {
                            resultRow("Дневная цель", "\(draftPlan.dailyCalorieTarget(tdee: tdee)) ккал", highlighted: true)
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

                if store.plan != nil {
                    Section {
                        Button("Завершить текущий план", role: .destructive) {
                            store.cancelPlan()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(store.plan.map(\.title) ?? "Новый план")
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
    }

    private func adherenceSection(plan: Plan, adherence: PlanAdherence) -> some View {
        Section {
            statusRow(adherence.status)

            resultRow("Ожидаемый вес сегодня", String(format: "%.1f кг", adherence.expectedWeightToday))
            if let actual = adherence.actualWeightToday {
                resultRow("Фактический вес (тренд)", String(format: "%.1f кг", actual))
            }
            if let deviation = adherence.deviationKg {
                resultRow("Отклонение", String(format: "%+.1f кг", deviation))
            }

            if adherence.status == .insufficientData {
                Text("Пока недостаточно данных — взвешивайся регулярно хотя бы неделю, чтобы увидеть фактический темп.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                if let projectedEndDate = adherence.projectedEndDate {
                    resultRow("При текущем темпе цель — к", projectedEndDate.formatted(.dateTime.day().month(.wide)))
                }

                if adherence.status == .ahead {
                    aheadActions(plan: plan, adherence: adherence)
                } else {
                    behindOrOnTrackActions(plan: plan, adherence: adherence)
                }
            }
        } header: {
            Text("Как идёт план")
        }
    }

    @ViewBuilder
    private func aheadActions(plan: Plan, adherence: PlanAdherence) -> some View {
        // Вариант 1: замедлить — есть больше, прийти к цели к исходной дате
        if let recalibrated = adherence.recalibratedDailyCalories, !plan.cyclingEnabled {
            VStack(alignment: .leading, spacing: 8) {
                Text("Замедлить: при \(recalibrated) ккал/день придёшь к \(String(format: "%.1f", plan.targetWeightKg)) кг к \(plan.endDate.formatted(.dateTime.day().month(.wide))).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Ставить \(recalibrated) ккал/день") {
                    store.dailyGoal = recalibrated
                }
                .buttonStyle(.bordered)
            }
        } else if plan.cyclingEnabled, let recalibrated = adherence.recalibratedDailyCalories {
            Text("При включённом цикле замедлить темп можно через увеличение целевого веса или срока — расчёт (\(recalibrated) ккал/день в среднем) пересчитается автоматически.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }

        // Вариант 2: финишировать раньше — принять новый срок
        if let projectedEndDate = adherence.projectedEndDate,
           projectedEndDate < plan.endDate.addingTimeInterval(-3 * 86400) {
            Button("Перенести финиш на \(projectedEndDate.formatted(.dateTime.day().month(.wide)))") {
                store.reschedulePlan(to: projectedEndDate)
            }
        }

        // Вариант 3: углубить цель — показываем к какому весу придёт к исходной дате
        if let projected = adherence.projectedWeightAtPlanEnd {
            let rounded = (projected * 10).rounded() / 10
            VStack(alignment: .leading, spacing: 8) {
                Text("Углубить цель: при текущем темпе к \(plan.endDate.formatted(.dateTime.day().month(.wide))) ты можешь достичь \(String(format: "%.1f", rounded)) кг.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Поставить цель \(String(format: "%.1f", rounded)) кг") {
                    guard var updated = store.plan else { return }
                    updated = Plan(
                        startDate: plan.startDate,
                        durationWeeks: plan.durationWeeks,
                        startWeightKg: plan.startWeightKg,
                        targetWeightKg: rounded,
                        cyclingEnabled: plan.cyclingEnabled,
                        weekendStyle: plan.weekendStyle
                    )
                    store.startPlan(updated)
                    targetWeightText = String(format: "%.1f", rounded)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder
    private func behindOrOnTrackActions(plan: Plan, adherence: PlanAdherence) -> some View {
        if let recalibrated = adherence.recalibratedDailyCalories, recalibrated != store.dailyGoal, !plan.cyclingEnabled {
            VStack(alignment: .leading, spacing: 8) {
                Text("Чтобы успеть к \(plan.endDate.formatted(.dateTime.day().month(.wide))):")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Ставить \(recalibrated) ккал/день") {
                    store.dailyGoal = recalibrated
                }
                .buttonStyle(.bordered)
            }
        } else if plan.cyclingEnabled, let recalibrated = adherence.recalibratedDailyCalories {
            Text("При включённом цикле точную корректировку стоит вносить через целевой вес/срок — расчёт (\(recalibrated) ккал/день в среднем) учтёт её автоматически.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }

        if let projectedEndDate = adherence.projectedEndDate,
           projectedEndDate > plan.endDate.addingTimeInterval(7 * 86400) {
            Button("Сдвинуть финиш на \(projectedEndDate.formatted(.dateTime.day().month(.wide)))") {
                store.reschedulePlan(to: projectedEndDate)
            }
        }
    }

    private func statusRow(_ status: PlanStatus) -> some View {
        let (text, color, icon): (String, Color, String) = {
            switch status {
            case .insufficientData: return ("Собираем данные", .secondary, "clock")
            case .onTrack: return ("Идёшь по графику", .green, "checkmark.circle.fill")
            case .ahead: return ("Опережаешь график", .blue, "arrow.up.circle.fill")
            case .behind: return ("Отстаёшь от графика", .orange, "exclamationmark.triangle.fill")
            }
        }()
        return Label(text, systemImage: icon)
            .foregroundStyle(color)
            .font(.subheadline.weight(.semibold))
    }

    private func resultRow(_ title: String, _ value: String, highlighted: Bool = false) -> some View {
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
