import SwiftUI

/// Профиль: параметры тела, активность, норма белка и производные расчёты.
/// Раньше всё это лежало в «Настройках», где занимало пять секций из восьми — то есть
/// экран назывался настройками, а был в основном анкетой. Профиль правят осознанно
/// и он задаёт всю математику приложения, поэтому у него свой вход в тулбаре «Прогресса».
/// Корень вкладки «Тело». Раньше это был экран «Профиль», спрятанный за ячейкой
/// в списке — лишний шаг к тому, ради чего на вкладку и заходят. Содержимое
/// поднято наружу, а замеры и динамика веса встали в один ряд с остальными
/// параметрами тела.
struct ProfileView: View {
    var store: CalorieStore
    @AppStorage(AppAccent.defaultsKey) private var appAccent = AppAccent.system.rawValue
    
    /// Черновик экрана: всё, что крутят колёсами и переключателями.
    /// Перевод профиля в него и обратно живёт в `ProfileDraft`, а не здесь, —
    /// раньше он был тут дважды и разошёлся.
    @State private var draft: ProfileDraft

    @State private var showingGoalEditor = false
    @State private var showingBasis = false
    @State private var goalText = ""
    /// Раскрытое колесо. Одно на экран: открыть второе, не закрыв первое,
    /// невозможно по устройству значения, а не по внимательности.
    @State private var openPicker: ProfilePicker?
    @AppStorage("use_imperial") private var useImperial = false
    
    private func weightDisplayText(_ tenths: Int) -> String {
        let kg = Double(tenths) / 10.0
        return useImperial
        ? String(format: "%.1f \(String(localized: "фунт"))", kg * 2.20462)
        : String(format: "%.1f \(String(localized: "кг"))", kg)
    }
    
    /// Принимает десятые доли сантиметра: 1805 — это 180.5.
    private func heightDisplayText(_ tenths: Int) -> String {
        let cm = Double(tenths) / 10
        guard useImperial else {
            return String(format: "%.1f \(String(localized: "см"))", cm)
        }
        let totalInches = cm / 2.54
        let feet = Int(totalInches) / 12
        let inches = totalInches.truncatingRemainder(dividingBy: 12)
        return String(format: "%d' %.1f\"", feet, inches)
    }
    
    init(store: CalorieStore) {
        self.store = store
        _draft = State(initialValue: ProfileDraft(profile: store.profile,
                                               latestWeightKg: store.latestWeight?.weightKg))
    }
    
    /// Обхваты для оценки жира берутся из замеров в момент расчёта, а не копируются
    /// в профиль: копия рано или поздно расходится с оригиналом.
    private var measurement: BodyMeasurement? { store.latestMeasurement }

    /// Сухая масса известна только по снятым замерам — без них персональный
    /// режим предлагать нечестно, он молча посчитает то же самое от веса.
    private var leanMassKg: Double? { draftProfile?.leanMassKg(from: measurement) }


    @ViewBuilder
    private func macroBudgetSection(_ profile: UserProfile) -> some View {
        let protein = profile.proteinTargetGrams(from: measurement)
        let fat = profile.fatTargetGrams
        let goal = Double(store.adaptedTodayGoal > 0 ? store.adaptedTodayGoal : store.dailyGoal)
        let locked = protein * MacroTargets.kcalPerProteinGram + fat * MacroTargets.kcalPerFatGram
        let carbs = (goal - locked) / MacroTargets.kcalPerCarbGram

        // Белок и жир здесь не повторяем: их «итого» стоит двумя секциями выше,
        // в самих нормах, где их и задают. Новое число тут одно — углеводы,
        // которых никто не задаёт: они остаток нормы калорий.
        Section {
            if carbs > 0 {
                MacroBudgetRow("Углеводы", grams: carbs, color: MacroKind.carbs.color)
            } else {
                Label(
                    String(
                        format: String(localized: "Белок и жир не помещаются в норму: не хватает %d ккал. Подними калораж или опусти норму белка."),
                        Int((locked - goal).rounded())
                    ),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.app(.footnote))
                .foregroundStyle(.orange)
            }
        } header: {
            Text("Норма углеводов")
        } footer: {
            explain("Белок и жир заданы телом, углеводы — остаток нормы калорий. В день с повышенной нормой вырастут именно они.").map { Text($0) }
        }
    }
    
    
    /// Экран оплаты со строки «Premium» внизу профиля.
    @State private var showingPaywall = false
    @State private var showingSettings = false

    /// Профиль, который получится из черновика. Опционален ради тех мест,
    /// где он читается как «есть ли что считать».
    private var draftProfile: UserProfile? { draft.profile }

    /// Переезд заголовка секции в шапку — то же, что в «Рационе». Объектом,
    /// а не состоянием экрана: прокрутка меняет его на каждом кадре, и
    /// `@State` перестраивал бы весь список.
    @State private var head = SectionHeadState()
    /// Линия, на которой заголовок встаёт: верхняя безопасная зона экрана.
    @State private var pinLine: CGFloat = 0

    /// Секции в том порядке, в каком они на экране, и ровно те, что сейчас
    /// показаны. По порядку имя держится всю длину секции, даже когда её
    /// заголовок давно уехал за кромку; по составу — не считается текущей
    /// та, которой на экране нет.
    private var sectionOrder: [String] {
        var order = [String(localized: "Расчёт")]
        if store.plan == nil, !store.isPremium { order.append(String(localized: "Цель")) }
        order.append(String(localized: "Параметры тела"))
        order.append(String(localized: "Питание"))
        if !usesFact { order.append(String(localized: "Уровень активности")) }
        order.append(String(localized: "Норма белка"))
        order.append(String(localized: "Норма жира"))
        return order
    }

    var body: some View {
        List {
            // Подписка — самой верхней строкой, как учётная запись в
            // Настройках, и со словом, а не звёздочками в углу: значок без
            // подписи не говорил, что за ним оплата.
            Section {
                Button { showingPaywall = true } label: {
                    HStack {
                        Label("Premium", systemImage: "sparkles")
                            .foregroundStyle(.primary)
                        Spacer()
                        if store.isPremium {
                            Text("Активен")
                                .foregroundStyle(.secondary)
                        }
                        Image(systemName: "chevron.right")
                            .font(.app(.caption, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("subscription")
            }

            // Расчёт сразу под ней: ради него профиль и открывают — сколько тратишь,
            // сколько есть и сколько белка. Параметры, из которых он собран,
            // правят редко, и им место ниже.
            calculationSection

            // Выбор цели — только без премиума. С премиумом режим задаётся
            // планом: вне плана идёт поддержание, и множитель из профиля
            // означал бы вечный дефицит по настройке, о которой забыли.
            GoalSection(store: store, goal: $draft.goal)
            
            bodyParametersSection

            // Питание сразу перед нормами белка и жира: расписание приёмов и
            // эти нормы — про одно и то же, про еду. Параметры тела идут
            // раньше, потому что из них считаются и те и другие.
            //
            // Приёмы пищи при этом в профиле, а не в настройках приложения: это
            // про режим человека, как подъём и отбой, а не про то, как
            // приложение выглядит и куда кладёт копии.
            NutritionSection(store: store)
            
            // Пока норма идёт от факта, множитель активности ни на что не
            // влияет: расход измерен, а не угадан. Тогда выбор уезжает в лист
            // «Как считаем» — вместе с переключателем, который его включает.
            ActivityLevelSection(draft: $draft, usesFact: usesFact)
            
            ProteinTargetSection(draft: $draft, openPicker: $openPicker,
                                 measurement: measurement)

            FatTargetSection(draft: $draft, openPicker: $openPicker)

            if let draftProfile, store.dailyGoal > 0 {
                macroBudgetSection(draftProfile)
            }
        }
        .sheet(isPresented: $showingBasis) {
            CalculationBasisSheet(store: store, activityLevel: $draft.activityLevel,
                                  basis: draftProfile.map(basisCaption) ?? "",
                                  fatMethod: fatMethodText)
        }
        .glassRow()
        .listStyle(.insetGrouped)
        .tint((AppAccent(rawValue: appAccent) ?? .system).color(focus: store.focusMacro))
        .alert("Дневная цель", isPresented: $showingGoalEditor) {
            TextField("Ккал в день", text: $goalText)
                .keyboardType(.numberPad)
            Button("Отмена", role: .cancel) { }
            Button("Сохранить") {
                if let value = Int(goalText), value > 0 {
                    // Своё число живёт, пока его не перебьёт правка профиля:
                    // расход его больше не двигает.
                    store.setManualGoal(value)
                }
            }
        } message: {
            Text("Своё число вместо расчётного. Правка профиля пересчитает цель заново.")
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollIndicators(.hidden)
        .measuresPinLine()
        .onPreferenceChange(PinLineKey.self) { pinLine = $0; head.update(pinLine: $0) }
        .onPreferenceChange(SectionHeadKey.self) { heads in
            head.update(heads: heads, order: sectionOrder, pinLine: pinLine)
        }
        // Имя секции переезжает в шапку, как в «Рационе»: список длинный, и
        // «Профиль» наверху ничего не говорит о том, где человек сейчас.
        .tabTitle(head.current ?? String(localized: "Профиль"), trailingRoom: 44, rising: head.rising)
        .toolbar {
            // Настройки приложения — шестерёнкой в шапке, как у системных
            // экранов с учётной записью. На «Сегодня» она стояла третьим
            // значком в ряду про сегодняшний день, хотя это не про него.
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Настройки")
                .accessibilityIdentifier("openSettings")
            }
        }
        .navigationDestination(isPresented: $showingSettings) {
            SettingsView(store: store)
        }
        .navigationDestination(isPresented: $showingPaywall) {
            PaywallView(store: store, focus: .plan)
        }
        .onChange(of: draftProfile) { _, newProfile in
            if let p = newProfile { store.updateProfile(p) }
        }
        // Профиль, сохранённый не отсюда, подхватываем обратно в черновик.
        //
        // Экран собирается раньше, чем человек заполняет онбординг: вкладки
        // уже построены, а онбординг лежит поверх них листом. Поэтому `@State`
        // снимал профиль, когда профиля ещё не было, и навсегда оставался с
        // умолчаниями — семьдесят килограммов, сто семьдесят сантиметров,
        // двадцать пять лет.
        //
        // Само по себе это было бы досадно, но рядом стоит обработчик выше:
        // любая правка черновика пишет его в хранилище целиком. То есть
        // первое же касание любой строки «Профиля» затирало введённые в
        // онбординге вес, рост и возраст умолчаниями — молча.
        //
        // Сверяемся перед тем, как применять: без этого мы бы отвечали на
        // собственную же запись и ходили по кругу.
        .onChange(of: store.profile) { _, saved in
            guard let saved, saved != draftProfile else { return }
            apply(saved)
        }
    }
    
    
    /// Переносит сохранённый профиль в черновик экрана.
    ///
    /// Вес при этом снова берётся из последнего взвешивания, а не из профиля:
    /// на экране должно стоять то же число, что и на весах утром.
    private func apply(_ profile: UserProfile) {
        draft = ProfileDraft(profile: profile, latestWeightKg: store.latestWeight?.weightKg)
    }

    /// Динамика за месяц: искра и изменение прямо в строке веса — тренд виден,
    /// не заходя внутрь.
    private var weightTrend: (points: [Double], caption: String)? {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let recent = store.weightEntries.filter { $0.date >= cutoff }.sorted { $0.date < $1.date }
        guard recent.count >= 2, let first = recent.first, let last = recent.last else { return nil }
        let delta = last.weightKg - first.weightKg
        let unit = String(localized: "кг")
        return (recent.map(\.weightKg),
                String(format: "%+.1f %@", delta, unit))
    }
    
    /// Считаем ли норму от измеренного расхода.
    private var usesFact: Bool { store.usesMeasuredExpenditure && store.adaptiveTDEE != nil }

    /// Строка значения: подпись слева, число справа, «i» — объяснение листом.
    ///
    /// «i», а не шеврон: шеврон ведёт вглубь, а здесь подробности о самой
    /// строке и возврат в то же место.
    private func valueRow(_ title: LocalizedStringKey, systemImage: String,
                          value: String, unit: LocalizedStringKey, detail: LocalizedStringKey? = nil,
                          color: Color = .secondary, onInfo: (() -> Void)?) -> some View {
        settingLabel(systemImage: systemImage) {
            HStack(spacing: 6) {
                Text(title)
                if let detail {
                    Text(detail)
                        .font(.app(.caption))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Text(verbatim: value)
                    .monospacedDigit()
                    .foregroundStyle(color)
                Text(unit)
                    .foregroundStyle(.secondary)
                if let onInfo {
                    Button(action: onInfo) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Как считаем")
                }
            }
        }
    }

    /// Как считается жир — для листа «Как считаем».
    private var fatMethodText: String {
        guard let draftProfile else { return "" }
        return draftProfile.isNavyMethod(from: measurement)
            ? String(localized: "Жир считается методом ВМС США по обхватам из замеров, точность ±2–3%. Чтобы уточнить, снимай их в одном и том же месте.")
            : String(localized: "Жир считается по формуле Дойренберга от ИМТ, точность ±5%: она не различает мышцы и жир. Сними шею и пояс в замерах — тогда включится метод по обхватам.")
    }

    /// Откуда взялись числа — одной строкой для листа «Как считаем».
    fileprivate func basisCaption(_ profile: UserProfile) -> String {
        var parts: [String] = []
        // Формульный расход нужен только рядом с измеренным — как то, с чем
        // его сравнивают. Когда считаем по формуле, он и есть число в строке.
        if usesFact {
            parts.append(String(format: String(localized: "по формуле %lld"), Int(profile.tdee.rounded())))
        }
        parts.append(String(format: String(localized: "BMR %lld"), Int(profile.bmr.rounded())))
        // ИМТ — только когда жир считается от него: тогда он объясняет,
        // откуда взялся процент. При замерах по обхватам он ни при чём.
        if !profile.isNavyMethod(from: measurement) {
            parts.append(String(format: String(localized: "ИМТ %.1f"), profile.bmi))
        }
        if let fact = store.adaptiveTDEE, usesFact {
            parts.append(String(format: String(localized: "%lld дн. данных"), fact.loggedDays))
        }
        return parts.joined(separator: " · ")
    }

}

/// Искра веса: тридцать дней одной линией. Осей нет намеренно — здесь важна
/// форма кривой, а числа лежат на экране динамики.
private struct WeightSparkline: View {
    let points: [Double]
    
    var body: some View {
        GeometryReader { geo in
            if points.count >= 2, let low = points.min(), let high = points.max() {
                // Плоская линия при одинаковом весе не должна делить на ноль
                let span = max(high - low, 0.1)
                Path { path in
                    for (index, value) in points.enumerated() {
                        let x = geo.size.width * CGFloat(index) / CGFloat(points.count - 1)
                        let y = geo.size.height * (1 - CGFloat((value - low) / span))
                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(Color.accentColor,
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
        .accessibilityHidden(true)
    }
}

/// Как считается расход: по факту или по формуле, и с каким множителем активности.
///
/// Отдельным листом, а не секцией профиля: пока расход измеряется по дневнику
/// и весам, множитель активности ни на что не влияет, и держать его на главном
/// экране значит спрашивать то, что не спросят.
private struct CalculationBasisSheet: View {
    var store: CalorieStore
    @Binding var activityLevel: ActivityLevel
    /// Из чего собран расход: формула, BMR, ИМТ, дни данных.
    var basis: String
    /// Каким методом считается жир.
    var fatMethod: String
    @Environment(\.dismiss) private var dismiss

    /// Множитель активности спрашиваем, только пока расход считается по
    /// формуле: измеренный расход уже знает и работу, и зал.
    private var showsActivityPicker: Bool {
        !(store.usesMeasuredExpenditure && store.adaptiveTDEE != nil)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(isOn: Binding(get: { store.usesMeasuredExpenditure },
                                         set: { store.usesAdaptiveTDEE = $0 })) {
                        Text("Считать по факту")
                    }
                    .disabled(store.adaptiveTDEE == nil || !store.isPremium)
                    .accessibilityIdentifier("useAdaptiveTDEE")
                } footer: {
                    if !store.isPremium {
                        Text("Расчёт по факту — в Premium. Пока норма считается по формуле.")
                    } else if let fact = store.adaptiveTDEE {
                        Text(verbatim: String(format: String(localized: "По дневнику и весам: около %1$lld ккал в день, данных за %2$lld дн. Формула даёт %3$lld."),
                                              Int((store.smoothedTDEE ?? fact.tdee).rounded()), fact.loggedDays,
                                              Int((store.profile?.tdee ?? 0).rounded()))
                             + " "
                             + String(format: String(localized: "Отсюда и число: съедено в среднем %1$lld ккал в день, вес по тренду %2$@ кг в неделю. Формула этого не видит — она не знает ни твоей работы, ни адаптации к дефициту."),
                                      Int(fact.meanIntake.rounded()),
                                      String(format: "%+.2f", fact.weeklyRateKg)))
                    } else {
                        Text("Пока по формуле. Расход по факту — после двух недель записей.")
                    }
                }

                // Справка, которая раньше висела тремя строками мелкого текста
                // под карточкой: из чего собран расход и как считается жир.
                Section {
                    Text(verbatim: basis)
                        .font(.app(.footnote))
                        .foregroundStyle(.secondary)
                    Text(verbatim: fatMethod)
                        .font(.app(.footnote))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if showsActivityPicker {
                    Section {
                        Picker("Уровень активности", selection: $activityLevel) {
                            ForEach(ActivityLevel.allCases) { level in
                                Text(level.title).tag(level)
                            }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    } header: {
                        Text("Уровень активности")
                    } footer: {
                        explain("Множитель к базовому обмену. Он нужен, только пока расход считается по формуле: измеренный расход уже знает и работу, и зал.").map { Text($0) }
                    }
                }
            }
            .glassRow()
            .listStyle(.insetGrouped)
            // Отступ под заголовком — свой: штатный у сгруппированного списка
            // рассчитан на длинный экран, а в листе на два пункта он читался
            // как пустая строка между заголовком и переключателем.
            .contentMargins(.top, 8, for: .scrollContent)
            .screenTitle(String(localized: "Как считаем"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    CheckmarkButton { dismiss() }
                }
            }
        }
        // Половина и весь экран: справки и пять уровней активности в одну
        // фиксированную высоту не помещались.
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Разделы профиля
//
// Тело `body` было списком на триста семьдесят строк, где разделы приходилось
// искать глазами по отступам. Каждый раздел стал свойством с явным типом: и
// читается, и проверяется типами по частям.
private extension ProfileView {
    /// Расчёт: сколько тратишь, сколько есть и сколько белка. Ради него
    /// профиль и открывают, поэтому он первый.
    @ViewBuilder
    var calculationSection: some View {
    if let draftProfile {
        // Две строки вместо карточки.
        //
        // Карточка несла расход, норму, жир, сон, пульс, шаги и совет — и
        // половина этого жила где-то ещё: шаги и совет на «Сегодня», жир
        // среди параметров тела. Сон и пульс норму не двигают, а смотреть на
        // них здесь было незачем. Остался сам расчёт: сколько тратишь и, если
        // норма от этого отличается, сколько есть. Как это посчитано — в «i».
        Section {
            let expenditure = usesFact ? (store.smoothedTDEE ?? draftProfile.tdee) : draftProfile.tdee
            valueRow("Расход", systemImage: "flame",
                     value: "\(Int(expenditure.rounded()))", unit: "ккал",
                     detail: usesFact ? "по факту" : "по формуле",
                     color: .primary,
                     onInfo: { showingBasis = true })
                .accessibilityIdentifier("adaptiveTDEE")

            // Норма, совпавшая с расходом, не показывается: на поддержании
            // это то же число строкой выше.
            if abs(Double(store.dailyGoal) - expenditure) >= 5 {
                valueRow("Норма", systemImage: "fork.knife",
                         value: "\(store.dailyGoal)", unit: "ккал",
                         color: ProgressRing.kcalColors[0], onInfo: nil)
                    // Своё число — только без плана: с планом норму ведёт он.
                    .tappableRow {
                        guard store.plan == nil else { return }
                        goalText = String(store.dailyGoal)
                        showingGoalEditor = true
                    }
                    .accessibilityIdentifier("calorieTargetRow")
            }
        } header: {
            Text("Расчёт")
                .tracksSectionHead(String(localized: "Расчёт"))
        }
    }
    }

    @ViewBuilder
    var bodyParametersSection: some View {
    Section {
        // Знак — слева, в колонке значков, и он меняется вместе с выбором:
        // тот же знак, что человек видел в онбординге, стоит там же, где у
        // соседних строк стоят символы. В самих же вариантах его нет —
        // свёрнутый пикер показывает выбранный вариант целиком, и знак в нём
        // выходил мелким и косым, а подпись пропадала.
        Picker(selection: $draft.sex) {
            ForEach(Sex.allCases) { option in
                Text(verbatim: option.title).tag(option)
            }
        } label: {
            settingLabel("Пол", glyph: draft.sex.symbol)
        }
        .id(appAccent)
        // Вес ведёт на свой экран, а не открывает колесо: он меняется
        // взвешиваниями с датой, и колесо тут же расходилось бы с историей.
        // Динамика переехала туда же — отдельной строке рядом делать нечего.
        NavigationLink {
            WeightDetailView(store: store)
        } label: {
            settingLabel(systemImage: "scalemass") {
            HStack {
                Text(LocalizedStringKey(useImperial ? "Вес, фунт" : "Вес, кг"))
                Spacer()
                if let trend = weightTrend {
                    Text(trend.caption)
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                    WeightSparkline(points: trend.points)
                        .frame(width: 44, height: 18)
                }
                Text(weightDisplayText(draft.weightTenths))
                    .foregroundStyle(.secondary)
            }
            }
        }
        .accessibilityIdentifier("openWeight")
        
        
        
        settingLabel(systemImage: "figure.stand") {
            HStack {
                Text(LocalizedStringKey(useImperial ? "Рост, фт+дюйм" : "Рост, см"))
                Spacer()
                Text(heightDisplayText(draft.heightTenths))
                    .foregroundStyle(.secondary)
            }
        }
        .tappableRow {
            withAnimation(.easeInOut(duration: 0.2)) {
                openPicker = openPicker == .height ? nil : .height
            }
        }
        if openPicker == .height {
            Picker("Рост", selection: $draft.heightTenths) {
                ForEach(Array(stride(from: 1000, through: 2500, by: 1)), id: \.self) { v in
                    Text(heightDisplayText(v)).tag(v)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 160)
        }
        settingLabel(systemImage: "birthday.cake") {
            HStack {
                Text(draft.birthDate == nil ? "Возраст" : "День рождения")
                Spacer()
                // Пока даты нет, показываем годы: подставить вместо них
                // выдуманную дату значило бы соврать о дне рождения.
                if let birthDate = draft.birthDate {
                    Text(birthDate.formatted(date: .abbreviated, time: .omitted))
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(draft.ageInt) лет")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .tappableRow {
            withAnimation(.easeInOut(duration: 0.2)) {
                openPicker = openPicker == .birthday ? nil : .birthday
            }
        }
        if openPicker == .birthday {
            // Колесо дат и у тех, у кого записано только число лет: иначе
            // введённое когда-то число остаётся навсегда, а дата появиться
            // не может. Открывается оно на этом числе лет, а записывается
            // только то, что человек выбрал сам.
            DatePicker("День рождения",
                       selection: Binding(get: { draft.birthDate ?? UserProfile.birthDateGuess(forAge: draft.ageInt) },
                                          set: { newValue in
                                              draft.birthDate = newValue
                                              draft.ageInt = UserProfile.age(bornOn: newValue) ?? draft.ageInt
                                          }),
                       in: UserProfile.birthDateRange(),
                       displayedComponents: .date)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(height: 160)
                .accessibilityIdentifier("profileBirthDate")
        }
        // Замеры — пятой строкой, рядом с ростом и весом: это такой же
        // параметр тела, просто снимаемый лентой. В тулбаре их искали
        // глазами, потому что иконка линейки ничего не обещает.
        NavigationLink {
            MeasurementsView(store: store)
        } label: {
            settingLabel(systemImage: "ruler") {
            HStack {
                Text("Замеры")
                Spacer()
                if let last = store.latestMeasurement {
                    Text(last.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                }
            }
            }
        }
        .accessibilityIdentifier("openMeasurementsRow")

        // Жир — среди параметров тела, рядом с замерами, из которых он и
        // считается, а не в карточке расчёта, где стоял особняком.
        if let draftProfile {
            valueRow("Жир", systemImage: "drop",
                     value: String(format: "%.1f", draftProfile.bodyFatPercentage(from: measurement)),
                     unit: "%",
                     color: BodyFatStyle.color(for: draftProfile.bodyFatCategory(from: measurement)),
                     onInfo: { showingBasis = true })
                .accessibilityIdentifier("bodyFatRow")
        }
    } header: {
        // Заголовок отдельным блоком, а не строкой в `Section("…")`: так к
        // нему можно привесить слежение, по которому имя секции переезжает
        // в шапку при прокрутке.
        Text("Параметры тела")
            .tracksSectionHead(String(localized: "Параметры тела"))
    }
    }


}
