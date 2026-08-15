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

    private var startWeight: Double {
        store.plan?.startWeightKg ?? store.latestWeight?.weightKg ?? store.profile?.weightKg ?? 0
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
                        Text(String(format: "%.1f кг", startWeight))
                            .foregroundStyle(.secondary)
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
                        Picker("Выходные дни", selection: $weekendStyle) {
                            ForEach(WeekendStyle.allCases) { style in
                                Text(style.title).tag(style)
                            }
                        }
                    }
                } footer: {
                    Text("Автоматически распределяет калории по дням недели: чуть меньше в будни, рефид на выходных. Среднее за неделю остаётся тем же — меняется только распределение.")
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
            .navigationTitle(store.plan == nil ? "Новый план" : "План")
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

                if let recalibrated = adherence.recalibratedDailyCalories, recalibrated != store.dailyGoal, !plan.cyclingEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Чтобы успеть к \(plan.endDate.formatted(.dateTime.day().month(.wide))) при текущем факте, норму стоит скорректировать:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Поставить \(recalibrated) ккал/день") {
                            store.dailyGoal = recalibrated
                        }
                        .buttonStyle(.bordered)
                    }
                } else if plan.cyclingEnabled, let recalibrated = adherence.recalibratedDailyCalories {
                    Text("При включённом недельном цикле точную корректировку стоит вносить через целевой вес/срок выше — расчёт (\(recalibrated) ккал/день в среднем) учтёт её автоматически.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let projectedEndDate = adherence.projectedEndDate,
                   projectedEndDate > plan.endDate.addingTimeInterval(7 * 86400) {
                    Button("Сдвинуть срок плана на \(projectedEndDate.formatted(.dateTime.day().month(.wide)))") {
                        store.extendPlan(to: projectedEndDate)
                    }
                }
            }
        } header: {
            Text("Как идёт план")
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
