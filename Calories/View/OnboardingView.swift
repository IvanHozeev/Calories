import SwiftUI
import UniformTypeIdentifiers

/// Первый запуск: тело, активность, цель с планом и итог в виде кольца.
///
/// Раньше онбординг заканчивался двумя числами — калориями и белком, — а
/// план, цикл калорий, диет-брейки и нормы макросов человек находил потом
/// сам, если находил. Теперь всё, от чего зависит норма, настраивается здесь,
/// с разумными значениями по умолчанию: пропустить можно любой шаг кнопкой
/// «Далее», ничего не трогая.
///
/// Кончается предложением и пробным месяцем App Store: человек только что
/// увидел свой маршрут, и это единственный момент, когда «попробовать» значит
/// «начать вот это», а не «купить приложение».
struct OnboardingView: View {
    var store: CalorieStore
    var stepStore: StepStore
    @AppStorage("onboarding_completed") private var onboardingCompleted = false
    @Environment(PurchaseService.self) private var purchases
    @State private var isPurchasing = false
    @State private var showingPlans = false

    @State private var step: Step = .welcome

    @State private var sex: Sex = .male
    /// Дата, а не число лет: число устаревает ровно через год, и человек об
    /// этом не вспомнит. Колесо открывается на двадцати пяти годах — это
    /// начальная позиция, а не ответ за человека.
    @State private var birthDate = UserProfile.birthDateGuess(forAge: 25)
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
    @State private var showingBackupPicker = false
    /// Вычисляемым, а не хранимым: `@Observable` следит за чтением свойств в
    /// теле, а не за местом хранения, — и почленный инициализатор экрана от
    /// лишнего параметра не распухает.
    private var backups: BackupService { .shared }
    @State private var proteinTenths = Int(UserProfile.defaultProteinPerKg * 10)
    @State private var fatTenths = Int(MacroTargets.fatPerKg * 10)
    /// Кашрут и посты — одним вопросом: тема одна, и включает её тот же человек.
    @State private var observesTradition = false
    /// Два вопроса для предложения на финише: от них зависят и слова, и план.
    @State private var training: TrainingHabit = .sometimes
    @State private var obstacle: PastObstacle = .firstTime

    enum Step: Int, CaseIterable {
        /// Десять экранов вместо семнадцати: вопросы одной темы собраны вместе. «О тебе» —
        /// пол, возраст, рост и вес; «Образ жизни» — работа и зал; «Как идти к цели» — что
        /// мешало и как держать дефицит (только у сушки); «Питание» — белок, жир, кашрут;
        /// «Подключения» — копии и шаги.
        case welcome, explanations, about, lifestyle, goal, cutPlan, nutrition, gear, connections, result
    }

    /// Шаги, которые реально показываются: прошлые попытки, брейки и цикл —
    /// только у дефицита.
    private var steps: [Step] {
        Step.allCases.filter { $0 != .cutPlan || intent == .cut }
    }

    private var answers: OfferAnswers {
        OfferAnswers(training: training, obstacle: intent == .cut ? obstacle : nil)
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
            age: UserProfile.age(bornOn: birthDate) ?? 25,
            birthDate: birthDate,
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
            // Сушка — сразу с удержанием после неё: предложение обещает «сбросить
            // и удержать», и в плане должно быть ровно это.
            phases: intent == .cut
                ? answers.cutPhases(durationWeeks: durationWeeks, ratePercent: ratePercent,
                                    dietBreakEvery: dietBreakEvery)
                : [PlanPhase(intent: intent, durationWeeks: durationWeeks, weeklyRatePercent: ratePercent)],
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
                case .welcome:      welcomeStep
                case .explanations: explanationsStep
                case .about:        aboutStep
                case .lifestyle:    lifestyleStep
                case .goal:         goalStep
                case .cutPlan:      cutPlanStep
                case .nutrition:    nutritionStep
                case .gear:         gearStep
                case .connections:  connectionsStep
                case .result:       resultStep
                }
            }
            // Всё, что красится акцентом, — цветом текущего шага: переключатели,
            // меню, значки. Тот же цвет у точки сверху и у кнопки «Далее».
            .tint(accent)
            .id(step)
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
        }
        .task { if purchases.products.isEmpty { await purchases.load() } }
        // Подписку могли оформить и на листе со всеми тарифами — онбординг
        // кончается так же, как после кнопки на финише.
        .onChange(of: purchases.isPremium) { _, premium in
            if premium, step == .result { finish(subscribed: true) }
        }
        .sheet(isPresented: $showingPlans) {
            NavigationStack {
                // То же предложение, что на финише: ответы и план ещё не
                // сохранены, и пэйвол сам собрал бы его по старым данным.
                PaywallView(store: store, presetOffer: offer)
                    .toolbar {
                        // Справа: слева у пэйвола свой крупный заголовок, и
                        // «Закрыть» наезжал на него.
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Закрыть", systemImage: "xmark") { showingPlans = false }
                        }
                    }
            }
        }
        .alert("Не удалось оформить подписку", isPresented: Binding(
            get: { purchases.purchaseError != nil && !showingPlans },
            set: { if !$0 { purchases.purchaseError = nil } }
        )) {
            Button("Понятно", role: .cancel) { purchases.purchaseError = nil }
        } message: {
            Text(purchases.purchaseError ?? "")
        }
    }

    /// Цвет шага: у каждого свой, по кругу — те же четыре, что в кольце и
    /// в надписи «Calories» внизу настроек.
    ///
    /// Онбординг — единственное место, где человек идёт по приложению
    /// насквозь, и цвет здесь показывает движение: кнопка, точка и выбранная
    /// плитка меняют цвет от шага к шагу, а пройденные точки остаются каждая
    /// в своём. К концу полоска сверху набирается всеми цветами кольца —
    /// тем самым, ради которого всё и затевалось.
    private func stepColor(_ index: Int) -> Color {
        let colors = [ProgressRing.carbColors, ProgressRing.fatColors,
                      ProgressRing.proteinColors, ProgressRing.kcalColors].map { $0[1] }
        return colors[index % colors.count]
    }

    /// Цвет текущего шага — им красится всё, что на нём выделено.
    private var accent: Color { stepColor(steps.firstIndex(of: step) ?? 0) }

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
                        .foregroundStyle(accent)
                }
                .accessibilityLabel("Назад")
                Spacer()
            }

            let visible = Array(steps.dropFirst())
            let current = visible.firstIndex(of: step) ?? 0
            HStack(spacing: 6) {
                ForEach(visible.indices, id: \.self) { i in
                    Capsule()
                        .fill(i <= current ? AnyShapeStyle(stepColor(i + 1))
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
                // Тот же резиновый знак, что на лаунч-скрине и иконке: запуск
                // перетекает в приветствие, а не сменяется им. Живой — дышит.
                BreathingSign()
                    .frame(width: 150, height: 150)
                VStack(spacing: 6) {
                    // Чем приложение себя считает — надстрочником, как
                    // подзаголовок в магазине. Ниже имя, под ним обещание:
                    // порядок чтения тот же, что у соседнего приложения, и
                    // два продукта читаются как одна линейка.
                    //
                    // Обе строки не переводим: «It counts» по-английски
                    // значит и «оно считает», и «это важно» — каламбур
                    // держит обе половины обещания, а в переводе остаётся
                    // только одна. Это знак, как и само название.
                    Text(verbatim: "Nutrition Coach")
                        .font(.app(.footnote, weight: .semibold))
                        .foregroundStyle(accent)
                        .textCase(.uppercase)
                        .tracking(0.8)
                    Text(verbatim: "Calories")
                        .font(.app(size: 38, weight: .bold))
                    Text(verbatim: "Eat. It counts.")
                        .font(.app(.subheadline, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 10)
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

    /// Насколько подробно объяснять. Спрашиваем сразу и один раз: дальше на
    /// этом уровне говорит весь онбординг и всё приложение.
    ///
    /// Спрашиваем прямо, а не угадываем по возрасту: и двадцатилетний, и
    /// сорокалетний могут считать макросы третий год или не считать никогда.
    private var explanationsStep: some View {
        stepShell(title: "Как объяснять?") {
            VStack(spacing: 12) {
                ForEach(ExplanationLevel.allCases) { level in
                    Button {
                        ExplanationSettings.shared.level = level
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: level.title)
                                .font(.app(.body, weight: .medium))
                                .foregroundStyle(.primary)
                            Text(verbatim: level.summary)
                                .font(.app(.footnote))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .selectionSurface(ExplanationSettings.shared.level == level, accent: accent)
                    }
                    .buttonStyle(.plain)
                }
            }
            .accessibilityIdentifier("explanationChoice")
        }
    }

    /// Пол, возраст, рост и вес — одним экраном: все четыре нужны ради одной формулы
    /// базового обмена, и четыре отдельных шага с одним колесом на каждом растягивали
    /// самое скучное место онбординга.
    ///
    /// Возраст — датой, а не числом лет: число устаревает ровно через год, и человек об
    /// этом не вспомнит, а дату проще вспомнить, чем сосчитать. Рост и вес — колёсами
    /// рядом: на одном экране им хватает места, а выбирать числа колесом привычнее всего.
    private var aboutStep: some View {
        stepShell(title: "О тебе", subtitle: "Из этого считается базовый обмен — основа нормы калорий") {
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    ForEach(Sex.allCases) { s in
                        compactTile(icon: s.symbol, title: s.title, selected: sex == s) { sex = s }
                    }
                }

                DatePicker("День рождения",
                           selection: $birthDate,
                           in: UserProfile.birthDateRange(),
                           displayedComponents: .date)
                    .font(.app(.body, weight: .medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .tileSurface(cornerRadius: 20)
                    .accessibilityIdentifier("onboardingBirthDate")

                HStack(spacing: 12) {
                    VStack(spacing: 2) {
                        Text("Рост, см")
                            .font(.app(.caption))
                            .foregroundStyle(.secondary)
                        Picker("Рост", selection: $heightInt) {
                            ForEach(130...220, id: \.self) { Text(verbatim: "\($0)").tag($0) }
                        }
                        .pickerStyle(.wheel)
                        .frame(height: 120)
                    }
                    VStack(spacing: 2) {
                        Text("Вес, кг")
                            .font(.app(.caption))
                            .foregroundStyle(.secondary)
                        Picker("Вес", selection: $weightTenths) {
                            ForEach(350...2000, id: \.self) { v in
                                Text(verbatim: String(format: "%.1f", Double(v) / 10.0)).tag(v)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(height: 120)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .tileSurface(cornerRadius: 20)
            }
        }
    }

    /// Работа и зал — одним экраном: оба вопроса про привычный образ жизни, и от обоих
    /// зависит, сколько калорий и белка нужно. Зал идёт до цели: от ответа зависит темп
    /// сушки по умолчанию и белок, и человек видит их уже выставленными, а не
    /// переписанными после.
    private var lifestyleStep: some View {
        stepShell(title: "Образ жизни", subtitle: "Работа, зал и типичная неделя") {
            VStack(alignment: .leading, spacing: 18) {
                questionBlock("Активность") {
                    VStack(spacing: 8) {
                        ForEach(ActivityLevel.allCases) { level in
                            selectableRow(title: level.title, subtitle: level.subtitle, selected: activityLevel == level) {
                                activityLevel = level
                            }
                        }
                    }
                }
                questionBlock("Ходишь в зал?") {
                    VStack(spacing: 8) {
                        ForEach(TrainingHabit.allCases) { habit in
                            selectableRow(title: habit.title, subtitle: habit.subtitle, selected: training == habit) {
                                chooseTraining(habit)
                            }
                            .accessibilityIdentifier("onboardingTraining-\(habit.rawValue)")
                        }
                    }
                }
            }
        }
    }

    private func chooseTraining(_ habit: TrainingHabit) {
        training = habit
        proteinTenths = Int((answers.proteinPerKg * 10).rounded())
        if intent == .cut { ratePercent = answers.cutRatePercent }
    }

    /// Что мешало раньше — та боль, которую человек пришёл решить. По ней
    /// собирается предложение на финише, и она же меняет план: тому, кто
    /// срывался, — цикл калорий, кто терял силу — бережный темп и больше белка.
    private var obstacleChoices: some View {
        VStack(spacing: 8) {
            ForEach(PastObstacle.allCases) { item in
                selectableRow(title: item.title, subtitle: item.subtitle, selected: obstacle == item) {
                    chooseObstacle(item)
                }
                .accessibilityIdentifier("onboardingObstacle-\(item.rawValue)")
            }
        }
    }

    private func chooseObstacle(_ item: PastObstacle) {
        obstacle = item
        cyclingEnabled = answers.wantsCycling
        proteinTenths = Int((answers.proteinPerKg * 10).rounded())
        // Темп выбран шагом раньше; трогаем его, только если он резче, чем
        // стоит тому, кто терял силу.
        if item == .lostStrength { ratePercent = min(ratePercent, answers.cutRatePercent) }
    }

    /// Три карточки вместо сегментов, а под ними — темп.
    ///
    /// Сегменты «Сушка / Поддержание / Набор» назвали цели и больше ничего:
    /// что за этим стоит, человек узнавал уже на плане. У карточки есть
    /// строка про то, чем цель обернётся. Темп — тремя вариантами с тем, что
    /// они значат в килограммах и в итоге, а не шагом степпера в сотых долях
    /// процента: никто не знает, чем 0.65% отличается от 0.7%.
    private var goalStep: some View {
        stepShell(title: "Цель", subtitle: "От неё зависят норма калорий и план") {
            VStack(spacing: 10) {
                selectableRow(title: String(localized: "Похудеть"),
                              subtitle: String(localized: "Дефицит, темп и срок до цели"),
                              selected: intent == .cut) { chooseIntent(.cut) }
                    .accessibilityIdentifier("onboardingGoal-cut")
                selectableRow(title: String(localized: "Поддерживать"),
                              subtitle: String(localized: "Норма равна расходу, план не нужен"),
                              selected: intent == .maintenance) { chooseIntent(.maintenance) }
                    .accessibilityIdentifier("onboardingGoal-maintenance")
                selectableRow(title: String(localized: "Набрать"),
                              subtitle: String(localized: "Небольшой профицит, медленно"),
                              selected: intent == .bulk) { chooseIntent(.bulk) }
                    .accessibilityIdentifier("onboardingGoal-bulk")

                if intent != .maintenance {
                    paceSection
                        .padding(.top, 6)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: intent)
        }
    }

    private func chooseIntent(_ newIntent: PlanIntent) {
        intent = newIntent
        ratePercent = newIntent == .cut ? answers.cutRatePercent : newIntent.defaultWeeklyRatePercent
        durationWeeks = newIntent == .bulk ? 16 : 12
    }

    /// Три темпа на цель: бережный, рабочий и верхняя граница. Верхняя —
    /// ровно та, за которой приложение предупреждает (`aggressiveRatePercent`).
    private var paceOptions: [(percent: Double, note: String)] {
        switch intent {
        case .cut:
            return [(0.5, String(localized: "Бережно: медленнее, зато легче держать и меньше риск для мышц.")),
                    (0.7, String(localized: "Рабочая середина: заметный результат без лишнего риска.")),
                    (1.0, String(localized: "Верхняя граница: держать тяжело, мышцы под риском."))]
        case .bulk:
            return [(0.2, String(localized: "Осторожно: почти весь набор — мышцы, но медленно.")),
                    (0.3, String(localized: "Рабочая середина для набора: мышцы растут, жира немного.")),
                    (0.5, String(localized: "Верхняя граница набора: большая часть прибавки будет жиром."))]
        case .maintenance:
            return []
        }
    }

    private var paceSection: some View {
        let options = paceOptions
        let weekly = intent.direction * ratePercent / 100 * weightKg
        let finish = weightKg + weekly * Double(durationWeeks)
        return VStack(alignment: .leading, spacing: 6) {
            Text("Темп")
                .font(.app(.subheadline, weight: .semibold))
                .padding(.horizontal, 14)
            VStack(alignment: .leading, spacing: 12) {
                Picker("Темп", selection: $ratePercent) {
                    ForEach(options, id: \.percent) { option in
                        Text(verbatim: option.percent.formatted(.number.precision(.fractionLength(0...2))) + "%")
                            .tag(option.percent)
                    }
                }
                .pickerStyle(.segmented)

                HStack(alignment: .firstTextBaseline) {
                    Text("\(Text(verbatim: weekly.formatted(.number.precision(.fractionLength(2)).sign(strategy: .always())) + " ").font(.app(.title3, weight: .bold)))\(Text("кг в неделю").font(.app(.caption)).foregroundColor(.secondary))")
                    Spacer(minLength: 8)
                    Text(verbatim: String(format: String(localized: "за %1$lld нед. — до %2$@ кг"),
                                          durationWeeks,
                                          finish.formatted(.number.precision(.fractionLength(0)))))
                        .font(.app(.subheadline))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .monospacedDigit()

                Text(verbatim: options.first { $0.percent == ratePercent }?.note ?? "")
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .tileSurface(cornerRadius: 20)
        }
    }

    /// Сушка — одним экраном: что мешало раньше и как держать дефицит. Первое меняет
    /// второе (кому срываться — цикл калорий), поэтому рядом, а не через шаг.
    private var cutPlanStep: some View {
        stepShell(title: "Как идти к цели", subtitle: "Под это соберём план. Остальное можно настроить потом") {
            VStack(alignment: .leading, spacing: 18) {
                questionBlock("Что мешало раньше?") { obstacleChoices }
                cutOptionsContent
            }
        }
    }

    private var cutOptionsContent: some View {
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
                    explain("Неделя поддержания после каждых N недель дефицита. Жир уходит так же, а голод и тяга сорваться заметно меньше.").map { Text($0) }
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
                    explain("В будни чуть меньше, в рефид-дни больше. Среднее за неделю то же, а рефид переносится на праздник одной кнопкой.").map { Text($0) }
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                }
        }
    }

    /// Белок, жир и кашрут — одним экраном про питание: нормы макросов и то, по каким
    /// правилам человек ест. Кашрут и посты спрашиваем, а не прячем в настройки: тому,
    /// кто их соблюдает, иначе пришлось бы узнавать о кашруте и календаре случайно. Не
    /// соблюдающему вопрос ничего не стоит — по умолчанию выбрано «Нет».
    private var nutritionStep: some View {
        stepShell(title: "Питание", subtitle: "Углеводы — всё, что останется от нормы калорий") {
            VStack(alignment: .leading, spacing: 18) {
                macrosCard
                questionBlock("Кашрут и посты") { traditionChoices }
            }
        }
    }

    private var macrosCard: some View {
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
            .tileSurface(cornerRadius: 20)
    }

    /// Доступ к шагам — здесь, с объяснением, а не системным окном на первом
    /// запуске. Кнопка одна: «Разрешить» открывает окно «Здоровья», «Далее»
    /// снизу — пропустить. Шаги потом можно подключить с их карточки.
    /// Чем мерить. Приложение считает по факту — по дневнику и весам, — и без
    /// инструментов считать нечего: это честнее сказать на входе, чем потом
    /// показывать человеку «данных мало».
    /// Снаряжение — страницами, а не списком из трёх строк.
    ///
    /// Списком это читалось требованием: три галочки, которых у человека
    /// может не быть, и все разом перед глазами. Страницами — знакомство:
    /// по одной вещи за раз, крупно, и видно, что их всего три.
    ///
    /// Нужны ли они на самом деле, сказано в самих подписях: двое весов
    /// обязательны, часы нет.
    private var gearStep: some View {
        stepShell(title: "Что понадобится", subtitle: "Данные нужно чем-то снимать") {
            TabView {
                gearPage(.bodyScale, color: MacroKind.protein.color, title: "Напольные весы",
                         text: explain("Взвешивания каждое утро. По их тренду видно, сколько ты на самом деле тратишь, — и норма считается от факта, а не от формулы."))
                gearPage(.kitchenScale, color: MacroKind.carbs.color, title: "Кухонные весы",
                         text: explain("«На глаз» ошибаются на сотни калорий в день. Взвешенная еда — это разница между «работает» и «непонятно»."))
                gearPage(.watch, color: MacroKind.fat.color, title: "Браслет или часы",
                         text: explain("Не обязательно. Шаги и активные калории подтянутся из «Здоровья» сами, и активность перестанет быть догадкой."))
            }
            .tabViewStyle(.page)
            // Точки видны всегда, а не только пока листают: на светлом фоне
            // системные по умолчанию и так еле заметны, а без них человек
            // не узнает, что страниц несколько.
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            .frame(maxWidth: .infinity, minHeight: 320)
        }
    }

    /// Одна страница снаряжения: рисунок, название, зачем оно.
    private func gearPage(_ kind: GearArt.Kind, color: Color,
                          title: LocalizedStringKey, text: LocalizedStringKey?) -> some View {
        VStack(spacing: 20) {
            GearArt(kind: kind, color: color)
                .frame(height: 150)
            VStack(spacing: 8) {
                Text(title)
                    .font(.app(.title3, weight: .semibold))
                text.map { Text($0) }
                    .font(.app(.footnote))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 32)
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
    }

    /// Копии дневника и шаги — одним экраном «Подключения»: обе вещи про то, откуда и
    /// куда уходят данные, обе по одной кнопке, и обе можно пропустить.
    ///
    /// Копии спрашиваем здесь, пока терять нечего. Контейнер приложения удаляется
    /// вместе с приложением, а копия внутри него спасает от порчи данных, но не от
    /// «удалил и поставил заново» и не от потерянного телефона. Папка в «Файлах» или
    /// iCloud Drive лежит снаружи и переживает и то, и другое. Синхронизации у
    /// приложения нет, и выбранная папка — единственное, что стоит между годом
    /// дневника и пустым экраном. Пропустить можно, но молча мимо не пройдёшь: отказ
    /// явный, а на «Сегодня» потом придёт напоминание.
    ///
    /// Доступ к шагам — здесь, с объяснением, а не системным окном на первом запуске.
    /// Приложение только читает шаги из «Здоровья», ничего туда не пишет.
    private var connectionsStep: some View {
        stepShell(title: "Подключения", subtitle: "Можно пропустить и подключить позже") {
            VStack(spacing: 14) {
                connectionCard(
                    icon: backups.isConfigured ? "externaldrive.badge.checkmark" : "externaldrive.badge.icloud",
                    title: "Копии дневника",
                    text: backups.folderName.map { _ in "Копия будет обновляться раз в сутки, последние четырнадцать сохранятся." }
                        ?? "Папка в «Файлах» или iCloud Drive: копия переживёт и переустановку, и новый телефон.",
                    folder: backups.folderName
                ) {
                    Button {
                        showingBackupPicker = true
                    } label: {
                        Label(backups.isConfigured ? "Выбрать другую папку" : "Выбрать папку",
                              systemImage: "folder")
                            .font(.app(.body, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("onboardingBackupFolder")
                }

                connectionCard(
                    icon: "figure.walk.circle.fill",
                    title: "Шаги",
                    text: "Шаги и активные калории появятся на «Сегодня» рядом с едой. Приложение только читает их из «Здоровья», ничего туда не пишет.",
                    folder: nil
                ) {
                    Button {
                        stepStore.requestAuthorization()
                        healthAsked = true
                    } label: {
                        Label(healthAsked ? "Доступ запрошен" : "Разрешить доступ",
                              systemImage: healthAsked ? "checkmark" : "heart.fill")
                            .font(.app(.body, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                    .buttonStyle(.bordered)
                    .disabled(healthAsked)
                    .accessibilityIdentifier("onboardingHealthAccess")
                }
            }
        }
        .fileImporter(isPresented: $showingBackupPicker, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { backups.useFolder(url) }
        }
    }

    /// Карточка подключения: значок цветом шага, название, пояснение и кнопка.
    private func connectionCard<Action: View>(icon: String, title: LocalizedStringKey, text: LocalizedStringKey,
                                              folder: String?, @ViewBuilder action: () -> Action) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.app(size: 34))
                    .foregroundStyle(accent)
                    .frame(width: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.app(.headline))
                    if let folder {
                        Text(verbatim: folder)
                            .font(.app(.subheadline, weight: .semibold))
                    }
                    Text(text)
                        .font(.app(.footnote))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            action()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tileSurface(cornerRadius: 20)
    }

    /// Выбор кашрута и постов: «Соблюдаю» или «Нет».
    private var traditionChoices: some View {
        VStack(spacing: 8) {
            selectableRow(title: String(localized: "Соблюдаю"),
                          subtitle: String(localized: "Ожидание между мясным и молочным, посты и праздники с подсказками на «Сегодня»"),
                          selected: observesTradition) { observesTradition = true }
                .accessibilityIdentifier("onboardingObservesTradition")
            selectableRow(title: String(localized: "Нет"),
                          subtitle: String(localized: "Ни кашрута, ни календаря"),
                          selected: !observesTradition) { observesTradition = false }
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

    /// Финиш — не «Готов?», а предложение: что человек получит, собранное
    /// из его ответов, и его же цифры — откуда, куда и к какому дню.
    private var offer: Offer {
        Offer.make(intent: intent, answers: answers, observesTradition: observesTradition)
    }

    private var resultStep: some View {
        let offer = offer
        return VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 8) {
                        Text(verbatim: offer.headline)
                            .font(.app(size: 28, weight: .bold))
                            .multilineTextAlignment(.center)
                            .accessibilityIdentifier("onboardingOffer")
                        Text(verbatim: offer.subtitle)
                            .font(.app(.subheadline))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 24)

                    routeCard
                        .padding(.horizontal, 20)

                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(offer.benefits.prefix(3), id: \.kind) { benefit in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: benefit.icon)
                                    .font(.app(.headline))
                                    .foregroundStyle(ProgressRing.kcalColors[0])
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: benefit.title)
                                        .font(.app(.headline))
                                    Text(verbatim: benefit.detail)
                                        .font(.app(.footnote))
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                }
                .padding(.top, 24)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)

            trialBar
        }
    }

    /// Пробный месяц — кнопкой на финише, с ценой под ней.
    ///
    /// Один раз и с картой: App Store сам следит, чтобы пробный месяц был
    /// один на Apple ID, и сам спишет годовую цену, если человек не отменит.
    /// Поэтому под кнопкой — сколько и когда, а рядом — выход без подписки:
    /// «Не сейчас» ведёт в приложение, а маршрут ждёт до подписки.
    ///
    /// Тарифы не загрузились (нет сети) — остаётся обычное «Начать»: закрыть
    /// человеку вход в приложение из-за App Store нельзя.
    @ViewBuilder
    private var trialBar: some View {
        if let product = purchases.featured {
            VStack(spacing: 8) {
                Button {
                    isPurchasing = true
                    Task {
                        let bought = await purchases.purchase(product)
                        isPurchasing = false
                        if bought { finish(subscribed: true) }
                    }
                } label: {
                    Group {
                        if isPurchasing {
                            ProgressView().tint(Color(.systemBackground))
                        } else {
                            Text(verbatim: product.purchaseTitle(introEligible: purchases.introEligible))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(AccentActionButtonStyle(color: accent))
                .disabled(isPurchasing)
                .accessibilityIdentifier("onboardingTrial")

                Text(verbatim: product.termsText(introEligible: purchases.introEligible))
                    .font(.app(.caption2))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 24) {
                    Button("Все тарифы") { showingPlans = true }
                    Button("Не сейчас") { finish(subscribed: false) }
                        .accessibilityIdentifier("onboardingSkipTrial")
                }
                .font(.app(.subheadline, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        } else if purchases.isLoading {
            ProgressView()
                .frame(height: 50)
                .padding(.bottom, 44)
        } else {
            primaryButton(title: "Начать") { finish(subscribed: false) }
        }
    }

    /// Маршрут и норма одной карточкой: кольцо дня, откуда и куда вес, к
    /// какому дню, и сколько удержания после.
    private var routeCard: some View {
        HStack(spacing: 16) {
            // Резиновый знак вместо кольца с нормой: норма в калориях и белке
            // стоит текстом рядом, а знак здесь — то же, что на иконке и
            // заставке, и финиш онбординга приходит к тому, с чего он начался.
            RubberSign(ring: 76)
                .frame(width: 88, height: 88)
            VStack(alignment: .leading, spacing: 4) {
                if let plan = draftPlan {
                    Text(verbatim: String(format: "%.1f → %.1f %@", plan.startWeightKg, plan.targetWeightKg,
                                          String(localized: "кг")))
                        .font(.app(.title3, weight: .bold))
                    Text(verbatim: String(format: String(localized: "к %@"),
                                          plan.targetReachedDate.formatted(.dateTime.day().month(.wide))))
                        .font(.app(.subheadline, weight: .semibold))
                        .foregroundStyle(ProgressRing.kcalColors[0])
                    if plan.holdWeeksAfterTarget > 0 {
                        Text(String(format: String(localized: "потом %lld нед. удержания"), plan.holdWeeksAfterTarget))
                            .font(.app(.caption))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(verbatim: String(format: String(localized: "%1$lld ккал · белок %2$lld г"),
                                      dailyCalories, Int(proteinGrams.rounded())))
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
            }
            .monospacedDigit()
            Spacer(minLength: 0)
        }
        .padding(16)
        .tileSurface(cornerRadius: 22)
    }

    /// Профиль и план. `startPlan` закрыт премиумом: с подпиской план
    /// запускается сразу, без неё — откладывается до подписки.
    private func finish(subscribed: Bool) {
        guard !onboardingCompleted else { return }
        if !healthAsked { stepStore.deferAuthorization() }
        store.updateProfile(draftProfile)
        answers.save()
        if observesTradition {
            KosherSettings.shared.isEnabled = true
            KosherSettings.shared.observesCalendar = true
        }
        if let plan = draftPlan {
            // Право от StoreKit доходит до стора через приложение, чуть позже
            // кнопки, — ставим его здесь, чтобы план не потерялся по дороге.
            if subscribed { store.isPremium = true }
            if store.isPremium {
                store.startPlan(plan)
            } else {
                store.keepPendingPlan(plan)
            }
        }
        onboardingCompleted = true
    }

    // MARK: - Layout helpers

    @ViewBuilder
    /// Подпись необязательна: у половины шагов под заголовком стояла
    /// строка, которая ничего не добавляла — обещала то, что человек увидит
    /// через экран, или успокаивала, что выбор можно поменять. Заголовок с
    /// самим вопросом справляется и один.
    private func stepShell<Content: View>(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        // Содержимое собираем до замыкания прокрутки: параметр-билдер в него
        // не попадает, он не «убегающий».
        let body = content()
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text(title)
                    .font(.app(size: 28, weight: .bold))
                subtitle.map { Text($0) }
                    .font(.app(.subheadline))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 20)
            .padding(.horizontal, 24)

            // Содержимое прокручивается: на экранах из нескольких вопросов оно
            // выше окна, а кнопка «Далее» стоит под ним и не уезжает. Пока оно
            // ниже окна, прокрутки нет и оно по центру, как стояло раньше.
            GeometryReader { proxy in
                ScrollView {
                    body
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)
                        .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
            }

            primaryButton(title: "Далее") { go(1) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Блок вопроса внутри экрана из нескольких: подпись и варианты под ней.
    private func questionBlock<Content: View>(_ title: LocalizedStringKey,
                                              @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.app(.subheadline, weight: .semibold))
                .padding(.horizontal, 4)
            content()
        }
    }

    /// Кнопка шага — цветом шага, тем же, что точка сверху и значки на экране: чёрная
    /// кнопка на каждом шаге была единственным, что не менялось, и выбивалась из
    /// цветного онбординга. Подпись чёрная: на пастели белая не читалась бы.
    private func primaryButton(title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(AccentActionButtonStyle(color: accent))
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
                        .foregroundStyle(accent)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .selectionSurface(selected, accent: accent)
        }
        // Без плоского стиля кнопка красит текст карточки в синий.
        .buttonStyle(.plain)
        // Выбранная карточка — выбранная и для VoiceOver: галочку он не читает.
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Компактная плитка выбора: значок цветом шага и название в строку.
    private func compactTile(icon: String, title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(verbatim: icon)
                    .font(.app(size: 24))
                    .foregroundStyle(accent)
                Text(verbatim: title)
                    .font(.app(.body, weight: .medium))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .selectionSurface(selected, accent: accent)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Кнопка онбординга: капсула цветом шага.
private struct AccentActionButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.app(.subheadline, weight: .semibold))
            .foregroundStyle(Color.black)
            .padding(.horizontal, 18)
            .frame(minHeight: 48)
            .background(color, in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
    }
}

private extension View {
    /// Карточка выбора: стекло, выбранная обведена цветом шага.
    func selectionSurface(_ selected: Bool, accent: Color) -> some View {
        tileSurface(cornerRadius: 20)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(selected ? accent : Color.clear, lineWidth: 1.5)
            )
    }
}
