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


    /// Экран оплаты со строки «Premium» внизу профиля.
    @State private var showingPaywall = false
    @State private var showingSettings = false
    @State private var showingWeight = false
    @State private var showingMeasurements = false

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
        var order: [String] = []
        if showsGoalRow { order.append(String(localized: "Расчёт")) }
        if store.plan == nil, !store.isPremium { order.append(String(localized: "Цель")) }
        order.append(String(localized: "Параметры тела"))
        order.append(String(localized: "Питание"))
        if !usesFact { order.append(String(localized: "Активность")) }
        return order
    }

    var body: some View {
        List {
            // Как идёт тело: вес, жир, сухая масса и тренд веса за полтора
            // месяца. Только смотреть — править в параметрах ниже.
            if let weight = store.weightKg {
                Section {
                    BodySnapshotCard(weightKg: weight,
                                     fatPercent: store.measuredBodyFatPercent,
                                     leanKg: draftProfile?.leanMassKg(from: measurement),
                                     trend: store.weightTrendSeries(weeks: 6),
                                     weeks: 6,
                                     imperial: useImperial,
                                     measuredOn: store.latestMeasurement?.date,
                                     onOpenWeight: { showingWeight = true },
                                     onOpenBody: { showingMeasurements = true })
                        // Без своих отступов: карточка во всю ширину секции,
                        // как строки соседних карточек. С шестнадцатью точками
                        // по бокам она выходила уже остальных.
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }
            }

            // Подписка — второй карточкой, под тем, как идёт тело: профиль
            // открывают ради тела, а оплата — со словом, а не звёздочками в
            // углу: значок без подписи не говорил, что за ним оплата.
            Section {
                Button { showingPaywall = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.tint)
                            .frame(width: 22)
                        // Название и одной строкой, что внутри: «Premium» без
                        // подписи не говорил, за что платят.
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Premium")
                                .font(.app(.body, weight: .semibold))
                                .foregroundStyle(.primary)
                            Text("План, расход по факту, недельный обзор")
                                .font(.app(.caption))
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        if store.isPremium {
                            Text("Активен")
                                .font(.app(.subheadline))
                                .foregroundStyle(.secondary)
                        }
                        Image(systemName: "chevron.right")
                            .font(.app(.caption, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("subscription")
            }

            // Норма — под ней, когда она отличается от расхода. Сам расход стоит
            // в параметрах тела, из которых он считается.
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
            NutritionSection(store: store, draft: $draft, openPicker: $openPicker,
                             measurement: measurement)

            // Пока норма идёт от факта, множитель активности ни на что не
            // влияет: расход измерен, а не угадан. Тогда выбор уезжает в лист
            // «Как считаем» — вместе с переключателем, который его включает.
            // Иначе — одной строкой с выбранным уровнем, а пять вариантов на
            // своём экране.
            if !usesFact {
                Section {
                    NavigationLink {
                        ActivityLevelScreen(draft: $draft, usesFact: usesFact)
                    } label: {
                        settingLabel(systemImage: "figure.run") {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(verbatim: draft.activityLevel.title)
                                Text(verbatim: draft.activityLevel.subtitle)
                                    .font(.app(.caption))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityIdentifier("openActivityLevel")
                } header: {
                    Text("Активность")
                        .tracksSectionHead(String(localized: "Активность"))
                }
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
        .navigationDestination(isPresented: $showingWeight) {
            WeightDetailView(store: store)
        }
        .navigationDestination(isPresented: $showingMeasurements) {
            MeasurementsView(store: store)
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
    /// Расход, взятый из параметров тела: тратят то, что есть у тела, и число
    /// стоит там же, где вес, рост и возраст, из которых оно считается.
    var expenditure: Double? {
        guard let draftProfile else { return nil }
        return usesFact ? (store.smoothedTDEE ?? draftProfile.tdee) : draftProfile.tdee
    }

    /// Норма показывается отдельно, только когда она отличается от расхода:
    /// на поддержании это то же число, и второй раз его писать незачем.
    var showsGoalRow: Bool {
        guard let expenditure else { return false }
        return abs(Double(store.dailyGoal) - expenditure) >= 5
    }

    /// Расчёт: сколько есть. Расход ушёл в параметры тела, и секция остаётся,
    /// только когда норма от него отличается.
    @ViewBuilder
    var calculationSection: some View {
        if showsGoalRow {
            Section {
                valueRow("Норма", systemImage: "fork.knife",
                         value: store.dailyGoal.formatted(), unit: "ккал",
                         color: ProgressRing.kcalColors[0], onInfo: nil)
                    // Своё число — только без плана: с планом норму ведёт он.
                    .tappableRow {
                        guard store.plan == nil else { return }
                        goalText = String(store.dailyGoal)
                        showingGoalEditor = true
                    }
                    .accessibilityIdentifier("calorieTargetRow")
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
                    Text(birthDate.formatted(date: .long, time: .omitted))
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
                // Талия — то, что люди смотрят в замерах первым; дата снятия
                // уже стоит в карточке сверху.
                if let last = store.latestMeasurement {
                    Text(last.waistCm > 0
                         ? String(format: String(localized: "талия %@ см"), String(format: "%.0f", last.waistCm))
                         : last.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.app(.subheadline))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            }
        }
        .accessibilityIdentifier("openMeasurementsRow")

        // Расход — последней строкой параметров: он считается из них, и «i»
        // объясняет как.
        if let expenditure {
            valueRow("Расход", systemImage: "flame",
                     value: Int(expenditure.rounded()).formatted(), unit: "ккал",
                     detail: usesFact ? "по факту" : "по формуле",
                     color: .primary,
                     onInfo: { showingBasis = true })
                .accessibilityIdentifier("adaptiveTDEE")
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
