import SwiftUI

/// Первый запуск: тело, активность, цель с планом и итог в виде кольца.
///
/// Раньше онбординг заканчивался двумя числами — калориями и белком, — а
/// план, цикл калорий, диет-брейки и нормы макросов человек находил потом
/// сам, если находил. Теперь всё, от чего зависит норма, настраивается здесь,
/// с разумными значениями по умолчанию: пропустить можно любой шаг кнопкой
/// «Далее», ничего не трогая.
///
/// План сразу запускает двухнедельный пробный период — за две недели появится
/// первый вердикт «как идёт план», и будет видно, за что платить.
struct OnboardingView: View {
    var store: CalorieStore
    var stepStore: StepStore
    @AppStorage("onboarding_completed") private var onboardingCompleted = false

    @State private var step: Step = .welcome

    @State private var sex: Sex = .male
    @State private var age = 25
    @State private var heightInt = 175
    @State private var weightTenths = 800
    @State private var activityLevel: ActivityLevel = .moderate

    @State private var intent: PlanIntent = .cut
    @State private var ratePercent = PlanIntent.cut.defaultWeeklyRatePercent
    @State private var durationWeeks = 12

    @State private var dietBreakEvery: Int? = 4
    @State private var cyclingEnabled = false
    @State private var weekendStyle: WeekendStyle = .satSun

    @State private var healthAsked = false
    @State private var proteinTenths = Int(UserProfile.defaultProteinPerKg * 10)
    @State private var fatTenths = Int(MacroTargets.fatPerKg * 10)

    enum Step: Int, CaseIterable {
        case welcome, sex, age, height, weight, activity, goal, cutOptions, macros, gear, health, result
    }

    /// Шаги, которые реально показываются: брейки и цикл — только у дефицита.
    private var steps: [Step] {
        Step.allCases.filter { $0 != .cutOptions || intent == .cut }
    }

    private var weightKg: Double { Double(weightTenths) / 10 }

    private var goal: Goal {
        switch intent {
        case .cut:         return .fatLoss
        case .maintenance: return .maintenance
        case .bulk:        return .muscleGain
        }
    }

    private var draftProfile: UserProfile {
        UserProfile(
            weightKg: weightKg,
            heightCm: Double(heightInt),
            age: age,
            sex: sex,
            activityLevel: activityLevel,
            goal: goal,
            proteinPerKg: Double(proteinTenths) / 10,
            fatPerKg: Double(fatTenths) / 10
        )
    }

    /// План только для дефицита и набора: у поддержания нет ни темпа, ни финиша.
    private var draftPlan: Plan? {
        guard intent != .maintenance else { return nil }
        return Plan(
            startDate: Date(),
            startWeightKg: weightKg,
            phases: [PlanPhase(intent: intent, durationWeeks: durationWeeks, weeklyRatePercent: ratePercent,
                               dietBreakEvery: intent == .cut ? dietBreakEvery : nil)],
            cyclingEnabled: intent == .cut && cyclingEnabled,
            weekendStyle: weekendStyle
        )
    }

    private var dailyCalories: Int {
        let profile = draftProfile
        return draftPlan?.dailyCalorieTarget(tdee: profile.tdee) ?? profile.calorieTarget
    }

    private var proteinGrams: Double { draftProfile.proteinTargetGrams(from: nil) }
    private var fatGrams: Double { draftProfile.fatTargetGrams }
    private var carbGrams: Double {
        let left = Double(dailyCalories) - proteinGrams * MacroTargets.kcalPerProteinGram
            - fatGrams * MacroTargets.kcalPerFatGram
        return max(left, 0) / MacroTargets.kcalPerCarbGram
    }

    var body: some View {
        VStack(spacing: 0) {
            if step != .welcome { topBar }

            Group {
                switch step {
                case .welcome:    welcomeStep
                case .sex:        sexStep
                case .age:        ageStep
                case .height:     heightStep
                case .weight:     weightStep
                case .activity:   activityStep
                case .goal:       goalStep
                case .cutOptions: cutOptionsStep
                case .macros:     macrosStep
                case .gear:       gearStep
                case .health:     healthStep
                case .result:     resultStep
                }
            }
            .id(step)
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
        }
    }

    private func go(_ offset: Int) {
        guard let index = steps.firstIndex(of: step) else { return }
        let target = min(max(index + offset, 0), steps.count - 1)
        withAnimation(.easeInOut(duration: 0.25)) { step = steps[target] }
    }

    // MARK: - Top bar

    private var topBar: some View {
        ZStack {
            HStack {
                Button {
                    go(-1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.app(.body, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Назад")
                Spacer()
            }

            let visible = Array(steps.dropFirst())
            let current = visible.firstIndex(of: step) ?? 0
            HStack(spacing: 6) {
                ForEach(visible.indices, id: \.self) { i in
                    Capsule()
                        .fill(i <= current ? AnyShapeStyle(Color.green)
                                           : AnyShapeStyle(.channel(thickness: 6)))
                        .frame(width: i == current ? 22 : 8, height: 6)
                        .animation(.spring(duration: 0.3), value: step)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 4)
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 28) {
                // Тот же знак, что на лаунч-скрине, только живой: запуск
                // перетекает в приветствие, а не сменяется им.
                BrandMark(animated: true)
                    .frame(width: 150)
                VStack(spacing: 12) {
                    Text(verbatim: "Calories")
                        .font(.app(size: 38, weight: .bold))
                    Text("Настроим норму калорий и макросов под тебя и твою цель — пара минут.")
                        .font(.app(.body))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
            }
            Spacer()
            primaryButton(title: "Начать") { go(1) }
        }
    }

    private var sexStep: some View {
        stepShell(title: "Ты...", subtitle: "Пол учитывается в формуле метаболизма") {
            HStack(spacing: 12) {
                ForEach(Sex.allCases) { s in
                    tileCard(icon: s == .male ? "♂️" : "♀️", title: s.title, selected: sex == s) {
                        sex = s
                    }
                }
            }
        }
    }

    private var ageStep: some View {
        stepShell(title: "Сколько лет?", subtitle: "Возраст влияет на базовый обмен") {
            Picker("Возраст", selection: $age) {
                ForEach(14...90, id: \.self) { Text("\($0) лет").tag($0) }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: 240)
        }
    }

    private var heightStep: some View {
        stepShell(title: "Рост, см", subtitle: "Нужен для расчёта базового обмена") {
            Picker("Рост", selection: $heightInt) {
                ForEach(130...220, id: \.self) { Text("\($0) см").tag($0) }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: 240)
        }
    }

    private var weightStep: some View {
        stepShell(title: "Вес, кг", subtitle: "От него считаются калории, белок и жир") {
            Picker("Вес", selection: $weightTenths) {
                ForEach(350...2000, id: \.self) { v in
                    Text(verbatim: String(format: "%.1f \(String(localized: "кг"))", Double(v) / 10.0)).tag(v)
                }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: 240)
        }
    }

    private var activityStep: some View {
        stepShell(title: "Активность", subtitle: "Работа и зал за типичную неделю") {
            VStack(spacing: 8) {
                ForEach(ActivityLevel.allCases) { level in
                    selectableRow(title: level.title, subtitle: level.subtitle, selected: activityLevel == level) {
                        activityLevel = level
                    }
                }
            }
        }
    }

    private var goalStep: some View {
        stepShell(title: "Цель", subtitle: "Из неё приложение соберёт план с темпом и сроком") {
            VStack(spacing: 16) {
                Picker("Цель", selection: $intent) {
                    ForEach(PlanIntent.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: intent) { _, newIntent in
                    ratePercent = newIntent.defaultWeeklyRatePercent
                    durationWeeks = newIntent == .bulk ? 16 : 12
                }

                if intent != .maintenance {
                    VStack(spacing: 0) {
                        Stepper(value: $ratePercent, in: 0.1...1.5, step: 0.05) {
                            HStack {
                                Text("Темп")
                                Spacer()
                                Text(verbatim: String(format: "%.2f%% · %+.2f \(String(localized: "кг/нед"))",
                                                      ratePercent,
                                                      intent.direction * ratePercent / 100 * weightKg))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                        .padding(.vertical, 10)
                        Divider()
                        Stepper(value: $durationWeeks, in: 4...52) {
                            HStack {
                                Text("Срок")
                                Spacer()
                                Text(String(format: String(localized: "%lld нед."), durationWeeks))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                        .padding(.vertical, 10)
                    }
                    .padding(.horizontal, 16)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))

                    if ratePercent > intent.aggressiveRatePercent {
                        Label(intent == .cut
                              ? "Быстрее процента веса в неделю — на сушке это уже за счёт мышц."
                              : "Быстрее половины процента в неделю — на наборе большая часть прибавки будет жиром.",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.app(.caption))
                            .foregroundStyle(.orange)
                    }

                    Text(String(format: String(localized: "План бесплатно %lld дней — за это время появится первый вердикт, как он идёт."),
                                CalorieStore.trialDays))
                        .font(.app(.footnote))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    Text("На поддержании план не нужен: норма — твой расход, без темпа и финиша.")
                        .font(.app(.footnote))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    private var cutOptionsStep: some View {
        stepShell(title: "Как держать дефицит", subtitle: "Можно не трогать и настроить потом в плане") {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Диет-брейки")
                        .font(.app(.headline))
                    Picker("Диет-брейки", selection: $dietBreakEvery) {
                        Text("Вручную").tag(Int?.none)
                        ForEach(PlanPhase.dietBreakOptions, id: \.self) { every in
                            Text(String(format: String(localized: "%lld : 1"), every)).tag(Int?.some(every))
                        }
                    }
                    .pickerStyle(.segmented)
                    Text("Неделя поддержания после каждых N недель дефицита. Жир уходит так же, а голод и тяга сорваться заметно меньше.")
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Недельный цикл калорий", isOn: $cyclingEnabled.animation())
                        .font(.app(.headline))
                    if cyclingEnabled {
                        Picker("Рефид-дни", selection: $weekendStyle) {
                            ForEach(WeekendStyle.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.menu)
                    }
                    Text("В будни чуть меньше, в рефид-дни больше. Среднее за неделю то же, а рефид переносится на праздник одной кнопкой.")
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var macrosStep: some View {
        stepShell(title: "Белок и жир", subtitle: "Углеводы — всё, что останется от нормы калорий") {
            VStack(spacing: 0) {
                Stepper(value: $proteinTenths, in: 10...30) {
                    macroLine(title: "Белок", perKg: Double(proteinTenths) / 10, grams: proteinGrams, color: MacroKind.protein.color)
                }
                .padding(.vertical, 10)
                Divider()
                Stepper(value: $fatTenths,
                        in: Int(MacroTargets.fatFloorPerKg * 10)...Int(MacroTargets.fatCeilingPerKg * 10)) {
                    macroLine(title: "Жир", perKg: Double(fatTenths) / 10, grams: fatGrams, color: MacroKind.fat.color)
                }
                .padding(.vertical, 10)
                Divider()
                HStack {
                    Text("Углеводы")
                        .foregroundStyle(MacroKind.carbs.color)
                    Spacer()
                    Text(verbatim: "\(Int(carbGrams.rounded())) \(String(localized: "г"))")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .padding(.vertical, 12)
            }
            .padding(.horizontal, 16)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    /// Доступ к шагам — здесь, с объяснением, а не системным окном на первом
    /// запуске. Кнопка одна: «Разрешить» открывает окно «Здоровья», «Далее»
    /// снизу — пропустить. Шаги потом можно подключить с их карточки.
    /// Чем мерить. Приложение считает по факту — по дневнику и весам, — и без
    /// инструментов считать нечего: это честнее сказать на входе, чем потом
    /// показывать человеку «данных мало».
    private var gearStep: some View {
        stepShell(title: "Что понадобится", subtitle: "Норма считается по твоим данным, а данные нужно чем-то снимать") {
            VStack(alignment: .leading, spacing: 18) {
                gearLine(icon: "scalemass", title: "Напольные весы",
                         text: "Взвешивания каждое утро. По их тренду видно, сколько ты на самом деле тратишь, — и норма считается от факта, а не от формулы.")
                gearLine(icon: "square.stack.3d.up", title: "Кухонные весы",
                         text: "«На глаз» ошибаются на сотни калорий в день. Взвешенная еда — это разница между «работает» и «непонятно».")
                gearLine(icon: "applewatch", title: "Браслет или часы",
                         text: "Не обязательно. Шаги и активные калории подтянутся из «Здоровья» сами, и активность перестанет быть догадкой.")
            }
        }
    }

    private func gearLine(icon: String, title: LocalizedStringKey, text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.app(.title3))
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.app(.body, weight: .semibold))
                Text(text)
                    .font(.app(.footnote))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var healthStep: some View {
        stepShell(title: "Шаги", subtitle: "Приложение только читает их из «Здоровья», ничего туда не пишет") {
            VStack(spacing: 20) {
                Image(systemName: "figure.walk.circle.fill")
                    .font(.app(size: 72))
                    .foregroundStyle(.blue)
                Text("Шаги и активные калории появятся на «Сегодня» рядом с едой — сами, без ручного ввода.")
                    .font(.app(.body))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    stepStore.requestAuthorization()
                    healthAsked = true
                } label: {
                    Label(healthAsked ? "Доступ запрошен" : "Разрешить доступ",
                          systemImage: healthAsked ? "checkmark" : "heart.fill")
                        .font(.app(.body, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                }
                .buttonStyle(.bordered)
                .tint(.blue)
                .disabled(healthAsked)
                .accessibilityIdentifier("onboardingHealthAccess")
            }
        }
    }

    private func macroLine(title: LocalizedStringKey, perKg: Double, grams: Double, color: Color) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(color)
            Spacer()
            Text(verbatim: String(format: "%.1f \(String(localized: "г/кг")) · %d \(String(localized: "г"))",
                                  perKg, Int(grams.rounded())))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private var resultStep: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 24) {
                Text("Готов?")
                    .font(.app(size: 30, weight: .bold))

                // Кольцо с «Сегодня», заполненное нормой: сразу видно, на что
                // делится день — половина калорий и дуги макросов по их граммам.
                ProgressRing(consumed: 0, goal: dailyCalories, macros: .zero,
                             proteinTarget: proteinGrams, fatTarget: fatGrams, carbsTarget: carbGrams,
                             showsTargets: true, onOpen: {})
                    .allowsHitTesting(false)

                HStack(spacing: 0) {
                    resultNumber(Int(proteinGrams.rounded()), unit: "г", title: "Белки", color: MacroKind.protein.color)
                    resultNumber(Int(fatGrams.rounded()), unit: "г", title: "Жиры", color: MacroKind.fat.color)
                    resultNumber(Int(carbGrams.rounded()), unit: "г", title: "Углеводы", color: MacroKind.carbs.color)
                }
                .padding(.horizontal, 24)

                if let plan = draftPlan {
                    Text(String(format: String(localized: "%@ к %@ · план бесплатно %lld дней"),
                                String(format: "%.1f \(String(localized: "кг"))", plan.targetWeightKg),
                                plan.endDate.formatted(.dateTime.day().month(.wide)),
                                CalorieStore.trialDays))
                        .font(.app(.footnote))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
            }
            Spacer()
            primaryButton(title: "Начать") { finish() }
        }
    }

    private func resultNumber(_ value: Int, unit: LocalizedStringKey, title: LocalizedStringKey, color: Color) -> some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(verbatim: "\(value)")
                    .font(.app(.title2, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(color)
                Text(unit)
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
            }
            Text(title)
                .font(.app(.caption))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    /// Профиль, план и пробный период — в таком порядке: `startPlan` закрыт
    /// премиумом, и без пробного периода план молча не сохранился бы.
    private func finish() {
        if !healthAsked { stepStore.deferAuthorization() }
        store.updateProfile(draftProfile)
        if let plan = draftPlan {
            store.startTrialIfNeeded()
            store.startPlan(plan)
        }
        onboardingCompleted = true
    }

    // MARK: - Layout helpers

    @ViewBuilder
    private func stepShell<Content: View>(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text(title)
                    .font(.app(size: 28, weight: .bold))
                Text(subtitle)
                    .font(.app(.subheadline))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 20)
            .padding(.horizontal, 24)

            Spacer()

            content()
                .padding(.horizontal, 24)

            Spacer()

            primaryButton(title: "Далее") { go(1) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func primaryButton(title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.app(.body, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.green)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 44)
    }

    private func selectableRow(title: String, subtitle: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title)
                        .font(.app(.body, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(verbatim: subtitle)
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(selected ? Color.green.opacity(0.1) : Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(selected ? Color.green : Color.clear, lineWidth: 1.5)
            )
        }
        // Без плоского стиля кнопка красит текст карточки в синий.
        .buttonStyle(.plain)
    }

    private func tileCard(icon: String, title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Text(verbatim: icon).font(.app(size: 36))
                Text(verbatim: title)
                    .font(.app(.body, weight: .medium))
                    .foregroundStyle(.primary)
                if selected {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Color.clear.frame(height: 20)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(selected ? Color.green.opacity(0.1) : Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(selected ? Color.green : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}
