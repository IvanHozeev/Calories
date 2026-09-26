import SwiftUI

/// Профиль: параметры тела, активность, норма белка и производные расчёты.
/// Раньше всё это лежало в «Настройках», где занимало пять секций из восьми — то есть
/// экран назывался настройками, а был в основном анкетой. Профиль правят осознанно
/// и он задаёт всю математику приложения, поэтому у него свой вход в тулбаре «Прогресса».
/// Корень вкладки «Тело». Раньше это был экран «Профиль», спрятанный за ячейкой
/// в списке — лишний шаг к тому, ради чего на вкладку и заходят. Содержимое
/// поднято наружу, а замеры и динамика веса встали в один ряд с остальными
/// параметрами тела.
struct BodyView: View {
    var store: CalorieStore
    
    @State private var weightTenths: Int
    /// Рост в десятых долях сантиметра: 1805 — это 180.5.
    @State private var heightTenths: Int
    @State private var ageInt: Int
    @State private var proteinTenths: Int
    @State private var proteinBasis: ProteinBasis
    @State private var proteinLeanTenths: Int
    @State private var fatTenths: Int
    /// Задавали ли норму на сухую массу руками. Пока нет — при первом переходе
    /// подгоняем её так, чтобы граммы не изменились.
    @State private var proteinLeanIsSet: Bool
    @State private var showingGoalEditor = false
    @State private var showingBasis = false
    @State private var goalText = ""
    @State private var showHeightPicker = false
    @State private var showAgePicker = false
    @State private var showProteinPicker = false
    @State private var showFatPicker = false
    @State private var sex: Sex
    @State private var activityLevel: ActivityLevel
    /// Выбранный, но ещё не подтверждённый уровень активности.
    @State private var pendingActivity: ActivityLevel?
    @State private var goal: Goal
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
        let profile = store.profile
        let wKg = store.latestWeight?.weightKg ?? profile?.weightKg ?? 70.0
        _weightTenths = State(initialValue: max(300, Int((wKg * 10).rounded())))
        // Профиль хранит сантиметры, пикер работает в десятых.
        let hCm = Int(((profile?.heightCm ?? 170) * 10).rounded())
        _heightTenths = State(initialValue: hCm > 0 ? hCm : 1700)
        _ageInt = State(initialValue: profile?.age ?? 25)
        let pKg = profile?.proteinPerKg ?? UserProfile.defaultProteinPerKg
        _proteinTenths = State(initialValue: max(10, Int((pKg * 10).rounded())))
        _sex = State(initialValue: profile?.sex ?? .male)
        _activityLevel = State(initialValue: profile?.activityLevel ?? .moderate)
        _goal = State(initialValue: profile?.goal ?? .maintenance)
        _proteinBasis = State(initialValue: profile?.proteinBasis ?? .bodyweight)
        let pLean = profile?.storedProteinPerLeanKg
        _proteinLeanTenths = State(initialValue: max(10, Int(((pLean ?? UserProfile.defaultProteinPerLeanKg) * 10).rounded())))
        _proteinLeanIsSet = State(initialValue: pLean != nil)
        let fKg = profile?.fatPerKg ?? MacroTargets.fatPerKg
        _fatTenths = State(initialValue: min(max(Int((fKg * 10).rounded()),
                                                 Int(MacroTargets.fatFloorPerKg * 10)),
                                             Int(MacroTargets.fatCeilingPerKg * 10)))
    }
    
    /// Обхваты для оценки жира берутся из замеров в момент расчёта, а не копируются
    /// в профиль: копия рано или поздно расходится с оригиналом.
    private var measurement: BodyMeasurement? { store.latestMeasurement }

    /// Сухая масса известна только по снятым замерам — без них персональный
    /// режим предлагать нечестно, он молча посчитает то же самое от веса.
    private var leanMassKg: Double? { draftProfile?.leanMassKg(from: measurement) }
    
    /// Показываем не «вы уверены», а во что именно обойдётся смена:
    /// новую норму калорий и разницу с текущей.
    private func activityChangeMessage(to level: ActivityLevel) -> String {
        guard let current = draftProfile else {
            return String(localized: "Норма калорий пересчитается.")
        }
        var updated = current
        updated.activityLevel = level
        let delta = updated.calorieTarget - current.calorieTarget
        let sign = delta > 0 ? "+" : ""
        return String(
            format: String(localized: "Норма станет %d ккал вместо %d — это %@%d ккал в день."),
            updated.calorieTarget, current.calorieTarget, sign, delta
        )
    }

    private var activeProteinTenths: Int {
        proteinBasis == .leanMass ? proteinLeanTenths : proteinTenths
    }

    /// Что сказать, если жир вне рабочего коридора.
    private var fatWarning: String? {
        let perKg = Double(fatTenths) / 10
        if perKg < MacroTargets.fatComfortRange.lowerBound {
            return String(localized: "У нижней границы. Держать так можно недолго — в пике сушки, а не всю фазу.")
        }
        if perKg > MacroTargets.fatComfortRange.upperBound {
            return String(localized: "Много: каждый лишний грамм жира — это два с лишним грамма углеводов, которых не будет на тренировке.")
        }
        return nil
    }

    private var proteinFooter: LocalizedStringKey {
        if leanMassKg == nil {
            return "Обычно 1.6–2.2 г на кг веса. Заполни замеры — и норму можно будет считать от сухой массы, а не от общего веса."
        }
        return proteinBasis == .leanMass
            ? "Для сухой массы диапазон другой — обычно 2.2–3.0 г на кг: сухой массы меньше, чем веса, а кормишь ты именно её."
            : "Обычно 1.6–2.2 г на кг веса. От сухой массы точнее: при одном весе на 12% и на 25% жира мышц разное количество, а кормишь ты мышцы."
    }

    /// Смена основы не должна менять норму: она меняет то, от чего норма считается.
    /// Поэтому при первом переходе на сухую массу подбираем число так, чтобы
    /// граммы остались прежними — дальше его правят руками, и оно живёт своей жизнью.
    private func seedLeanProteinIfNeeded() {
        guard !proteinLeanIsSet, let lean = leanMassKg, lean > 0 else { return }
        let grams = Double(proteinTenths) / 10.0 * (Double(weightTenths) / 10.0)
        proteinLeanTenths = min(50, max(10, Int((grams / lean * 10).rounded())))
        proteinLeanIsSet = true
    }

    /// Разбивка дневной нормы. Белок и жир — обязательства, углеводы — остаток;
    /// на сушке именно остаток и есть то, чем управляешь.
    @ViewBuilder
    private func macroBudgetSection(_ profile: UserProfile) -> some View {
        let protein = profile.proteinTargetGrams(from: measurement)
        let fat = profile.fatTargetGrams
        let goal = Double(store.adaptedTodayGoal > 0 ? store.adaptedTodayGoal : store.dailyGoal)
        let locked = protein * MacroTargets.kcalPerProteinGram + fat * MacroTargets.kcalPerFatGram
        let carbs = (goal - locked) / MacroTargets.kcalPerCarbGram

        Section {
            macroBudgetRow("Белки", grams: protein, color: MacroKind.protein.color)
            macroBudgetRow("Жиры", grams: fat, color: MacroKind.fat.color)
            if carbs > 0 {
                macroBudgetRow("Углеводы", grams: carbs, color: MacroKind.carbs.color)
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
            Text("Дневные макросы")
        } footer: {
            Text("Белок и жир заданы телом, углеводы — остаток нормы калорий. В день с повышенной нормой вырастут именно они.")
        }
    }

    private func macroBudgetRow(_ title: LocalizedStringKey, grams: Double, color: Color) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(verbatim: "\(Int(grams.rounded())) \(String(localized: "г"))")
                .font(.app(.body, weight: .semibold))
                .foregroundStyle(color)
        }
    }

    
    
    private var draftProfile: UserProfile? {
        UserProfile(
            weightKg: Double(weightTenths) / 10.0,
            heightCm: Double(heightTenths) / 10,
            age: ageInt,
            sex: sex,
            activityLevel: activityLevel,
            goal: goal,
            proteinPerKg: Double(proteinTenths) / 10.0,
            proteinPerLeanKg: Double(proteinLeanTenths) / 10.0,
            proteinBasis: proteinBasis,
            fatPerKg: Double(fatTenths) / 10.0
        )
    }
    
    
    var body: some View {
        List {
            // Расчёт первым: ради него профиль и открывают — сколько тратишь,
            // сколько есть и сколько белка. Параметры, из которых он собран,
            // правят редко, и им место ниже.
            if let draftProfile {
                Section {
                    calculationCard(draftProfile)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                } header: {
                    Text("Расчёт")
                } footer: {
                    if let fact = store.adaptiveTDEE, store.usesAdaptiveTDEE {
                        // Само число расхода тут не повторяем: оно уже написано
                        // крупно на карточке, и вторая его копия читалась как
                        // ещё одна цифра, которую надо сверить с первой.
                        Text(String(format: String(localized: "Отсюда и число: съедено в среднем %1$lld ккал в день, вес по тренду %2$@ кг в неделю. Формула этого не видит — она не знает ни твоей работы, ни адаптации к дефициту."),
                                    Int(fact.meanIntake.rounded()),
                                    String(format: "%+.2f", fact.weeklyRateKg)))
                    } else {
                        Text(draftProfile.isNavyMethod(from: measurement)
                             ? String(localized: "Жир считается методом ВМС США по обхватам из замеров, точность ±2–3%. Чтобы уточнить, снимай их в одном и том же месте.")
                             : String(localized: "Жир считается по формуле Дойренберга от ИМТ, точность ±5%: она не различает мышцы и жир. Сними шею и пояс в замерах — тогда включится метод по обхватам."))
                    }
                }
            }

            // Выбор цели — только без премиума. С премиумом режим задаётся
            // планом: вне плана идёт поддержание, и множитель из профиля
            // означал бы вечный дефицит по настройке, о которой забыли.
            if store.plan == nil, !store.isPremium {
                Section {
                    Picker("Цель", selection: $goal) {
                        ForEach(Goal.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Цель")
                } footer: {
                    if store.profile == nil {
                        Text("Сначала сохрани профиль — план считается по твоим BMR/TDEE.")
                    }
                }
            }
            
            // Приёмы пищи — в профиле, а не в настройках приложения: это про
            // режим человека, как подъём, отбой и число приёмов, а не про то,
            // как приложение выглядит и куда кладёт копии.
            Section("Питание") {
                NavigationLink {
                    MealScheduleSheet(
                        entries: store.todayEntries.map { (date: $0.date, calories: $0.calories) },
                        dailyGoal: store.adaptedTodayGoal,
                        settings: .shared,
                        isEmbedded: true
                    )
                } label: {
                    Label("Приёмы пищи", systemImage: "fork.knife")
                }
                .accessibilityIdentifier("openMealSchedule")
            }

            Section("Параметры тела") {
                Picker("Пол", selection: $sex) {
                    ForEach(Sex.allCases) { Text($0.title).tag($0) }
                }
                // Вес ведёт на свой экран, а не открывает колесо: он меняется
                // взвешиваниями с датой, и колесо тут же расходилось бы с историей.
                // Динамика переехала туда же — отдельной строке рядом делать нечего.
                NavigationLink {
                    WeightDetailView(store: store)
                } label: {
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
                        Text(weightDisplayText(weightTenths))
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("openWeight")
                
                
                
                HStack {
                    Text(LocalizedStringKey(useImperial ? "Рост, фт+дюйм" : "Рост, см"))
                    Spacer()
                    Text(heightDisplayText(heightTenths))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showHeightPicker.toggle()
                        if showHeightPicker { showAgePicker = false; showProteinPicker = false }
                    }
                }
                if showHeightPicker {
                    Picker("Рост", selection: $heightTenths) {
                        ForEach(Array(stride(from: 1000, through: 2500, by: 1)), id: \.self) { v in
                            Text(heightDisplayText(v)).tag(v)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 160)
                }
                HStack {
                    Text("Возраст")
                    Spacer()
                    Text("\(ageInt) лет")
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showAgePicker.toggle()
                        if showAgePicker { showHeightPicker = false; showProteinPicker = false }
                    }
                }
                if showAgePicker {
                    Picker("Возраст", selection: $ageInt) {
                        ForEach(5...100, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 160)
                }
            }
            
            // Пока норма идёт от факта, множитель активности ни на что не
            // влияет: расход измерен, а не угадан. Тогда выбор уезжает в лист
            // «Как считаем» — вместе с переключателем, который его включает.
            if !usesFact {
            Section {
                ForEach(ActivityLevel.allCases) { level in
                    Button {
                        // Уровень активности множит TDEE, то есть меняет норму калорий
                        // на сотни. Промахнуться по соседней строке легко, а последствие
                        // молчаливое: цифра назавтра другая, а почему — непонятно.
                        guard level != activityLevel else { return }
                        pendingActivity = level
                    } label: {
                        HStack {
                            // Цвета явные: иерархический .primary внутри кнопки
                            // списка берёт акцент, и все пять строк были синими —
                            // самым шумным местом профиля.
                            VStack(alignment: .leading, spacing: 2) {
                                Text(level.title)
                                    .foregroundStyle(Color.primary)
                                Text(level.subtitle)
                                    .font(.app(.caption))
                                    .foregroundStyle(Color.secondary)
                            }
                            Spacer()
                            if activityLevel == level {
                                Image(systemName: "checkmark")
                                    .font(.app(.subheadline, weight: .semibold))
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }
            } header: {
                Text("Уровень активности")
            } footer: {
                Text("Считай сумму работы и зала, а не один зал: восемь часов на ногах — это те же 300–600 ккал в день, что и пара тренировок. Множитель в любом случае приблизительный, точный расход покажет тренд веса за две-три недели.")
            }
            }
            
            Section {
                if leanMassKg != nil {
                    Picker("Считать", selection: $proteinBasis) {
                        ForEach(ProteinBasis.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .accessibilityIdentifier("proteinBasis")
                    .onChange(of: proteinBasis) { _, basis in
                        if basis == .leanMass { seedLeanProteinIfNeeded() }
                    }
                }
                HStack {
                    Text(proteinBasis == .leanMass ? "Белка на кг сухой массы" : "Белка на кг веса")
                    Spacer()
                    Text(String(format: "%.1f \(String(localized: "г/кг"))", Double(activeProteinTenths) / 10.0))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showProteinPicker.toggle()
                        if showProteinPicker { showHeightPicker = false; showAgePicker = false }
                    }
                }
                if showProteinPicker {
                    Picker("Белок", selection: proteinBasis == .leanMass ? $proteinLeanTenths : $proteinTenths) {
                        ForEach(10...50, id: \.self) { Text(String(format: "%.1f", Double($0) / 10.0)).tag($0) }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 160)
                }
                if let draftProfile {
                    HStack {
                        Text("Итого белка")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(verbatim: "\(Int(draftProfile.proteinTargetGrams(from: measurement).rounded())) \(String(localized: "г"))")
                            .font(.app(.body, weight: .semibold))
                    }
                }
            } header: {
                Text("Норма белка")
            } footer: {
                Text(proteinFooter)
            }

            Section {
                HStack {
                    Text("Жира на кг веса")
                    Spacer()
                    Text(String(format: "%.1f \(String(localized: "г/кг"))", Double(fatTenths) / 10.0))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showFatPicker.toggle()
                        if showFatPicker {
                            showProteinPicker = false; showHeightPicker = false; showAgePicker = false
                        }
                    }
                }
                if showFatPicker {
                    Picker("Жир", selection: $fatTenths) {
                        // Колесо ограничено жёсткими границами: за ними не бывает
                        // осознанного выбора, только промах пальцем.
                        ForEach(Int(MacroTargets.fatFloorPerKg * 10)...Int(MacroTargets.fatCeilingPerKg * 10),
                                id: \.self) { Text(String(format: "%.1f", Double($0) / 10.0)).tag($0) }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 160)
                }
                if let draftProfile {
                    HStack {
                        Text("Итого жира")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(verbatim: "\(Int(draftProfile.fatTargetGrams.rounded())) \(String(localized: "г"))")
                            .font(.app(.body, weight: .semibold))
                    }
                }
                // Вне рабочего коридора число разрешено, но о нём сказано вслух.
                if let warning = fatWarning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.app(.caption))
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Норма жира")
            } footer: {
                Text("Рабочий коридор — 0.6–1.2 г на кг веса, обычно 0.8. Меньше 0.5 и больше 1.5 выставить нельзя: ниже это ставка на гормоны, выше жир вытесняет углеводы, на которых работают тренировки.")
            }

            if let draftProfile, store.dailyGoal > 0 {
                macroBudgetSection(draftProfile)
            }


            Section {
                BrandFooter()
                    .brandFooterRow()
            }
        }
        .sheet(isPresented: $showingBasis) {
            CalculationBasisSheet(store: store, activityLevel: $activityLevel)
                .presentationDetents([.medium])
        }
        .glassRow()
        .listStyle(.insetGrouped)
        .alert("Дневная цель", isPresented: $showingGoalEditor) {
            TextField("Ккал в день", text: $goalText)
                .keyboardType(.numberPad)
            Button("Отмена", role: .cancel) { }
            Button("Сохранить") {
                if let value = Int(goalText), value > 0 {
                    store.dailyGoal = value
                }
            }
        } message: {
            Text("Своё число вместо расчётного. Правка профиля пересчитает цель заново.")
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollIndicators(.hidden)
        .alert("Сменить уровень активности?", isPresented: Binding(
            get: { pendingActivity != nil },
            set: { if !$0 { pendingActivity = nil } }
        ), presenting: pendingActivity) { level in
            Button("Отмена", role: .cancel) { pendingActivity = nil }
            Button("Сменить") {
                activityLevel = level
                pendingActivity = nil
            }
        } message: { level in
            Text(activityChangeMessage(to: level))
        }
        .navigationTitle("Профиль")
        .navigationBarTitleDisplayMode(.inline)
        .hiddenNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // Замеры — не строка в параметрах тела: туда заходят смотреть
                // выводы, а не править число, и лежать это должно там же, где
                // остальные входы на свои экраны.
                NavigationLink {
                    MeasurementsView(store: store)
                } label: {
                    Image(systemName: "ruler")
                }
                .accessibilityLabel("Замеры")
                .accessibilityIdentifier("openMeasurementsRow")
            }
        }
        .onChange(of: draftProfile) { _, newProfile in
            if let p = newProfile { store.updateProfile(p) }
        }
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
    
    private func bmiColor(_ bmi: Double) -> Color {
        switch bmi {
        case ..<18.5: return .blue
        case 18.5..<25: return .green
        case 25..<30: return .yellow
        default: return .red
        }
    }
    
    private func bmiLabel(_ bmi: Double) -> String {
        switch bmi {
        case ..<18.5: return "Недовес"
        case 18.5..<25: return "Норма"
        case 25..<30: return "Избыточный"
        default: return "Ожирение"
        }
    }
    
    /// Считаем ли норму от измеренного расхода.
    private var usesFact: Bool { store.usesAdaptiveTDEE && store.adaptiveTDEE != nil }

    /// Расчёт одной карточкой: крупно то, ради чего заходят, мелко — из чего
    /// оно собрано.
    ///
    /// Шесть отдельных плашек были шестью подложками подряд и занимали пол-экрана;
    /// девять строк списка до этого — ещё больше. Здесь один блок: сверху расход,
    /// под чертой четыре числа строкой, ниже серым — откуда что взялось.
    private func calculationCard(_ profile: UserProfile) -> some View {
        let fat = profile.bodyFatPercentage(from: measurement)
        let expenditure = usesFact ? (store.smoothedTDEE ?? profile.tdee) : profile.tdee
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                showingBasis = true
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(usesFact ? "Расход по факту" : "Расход по формуле")
                            .font(.app(.caption2))
                            .foregroundStyle(.tertiary)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(verbatim: "\(Int(expenditure.rounded()))")
                                .font(.app(size: 26, weight: .bold))
                                .monospacedDigit()
                                .foregroundStyle(Color.primary)
                            Text("ккал")
                                .font(.app(.caption))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Spacer(minLength: 8)
                    if let fact = store.adaptiveTDEE, usesFact {
                        Text(verbatim: fact.confidence.title)
                            .font(.app(.caption2))
                            .foregroundStyle(ProgressRing.kcalColors[0])
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(ProgressRing.kcalColors[0].opacity(0.15), in: Capsule())
                    }
                    Image(systemName: "chevron.right")
                        .font(.app(.caption2, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("adaptiveTDEE")

            Divider().opacity(0.4)

            HStack(alignment: .top, spacing: 8) {
                // Норма, совпавшая с расходом, не показывается вовсе: на
                // поддержании едят столько, сколько тратят, и это то же самое
                // число, что крупно стоит выше. Писать его дважды — заставлять
                // сверять две одинаковые цифры.
                //
                // Белка здесь больше нет: он не про расход, а про то, как
                // набрать день, и живёт в макросах на «Сегодня» и в разборе.
                let goalMatchesExpenditure = abs(Double(store.dailyGoal) - expenditure) < 5
                if !goalMatchesExpenditure {
                    if store.plan != nil {
                        miniStat("Норма", "\(store.dailyGoal)", unit: "ккал", color: ProgressRing.kcalColors[0])
                            .accessibilityIdentifier("calorieTargetRow")
                    } else {
                        Button {
                            goalText = String(store.dailyGoal)
                            showingGoalEditor = true
                        } label: {
                            miniStat("Норма", "\(store.dailyGoal)", unit: "ккал", color: ProgressRing.kcalColors[0])
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("calorieTargetRow")
                    }
                }
                // ИМТ убран: он не различает мышцы и жир и на тренированном
                // теле показывает «избыточный вес» рядом с честными двадцатью
                // процентами жира. Там, где он всё же участвует в расчёте —
                // в формуле Дойренберга, — он остался в серой подписи.
                miniStat("Жир %", String(format: "%.1f", fat), unit: "%",
                         color: BodyFatStyle.color(for: profile.bodyFatCategory(from: measurement)))
                    .accessibilityIdentifier("bodyFatRow")
            }

            Text(verbatim: basisCaption(profile))
                .font(.app(.caption2))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(12)
        // Обычная подложка карточки списка, а не стекло: у стекла своя тень,
        // и на светлой теме она ложилась под карточкой грязным пятном. Здесь
        // карточка и так лежит на сером фоне списка — ей хватает заливки.
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16))
    }

    /// Откуда взялись числа — одной серой строкой.
    private func basisCaption(_ profile: UserProfile) -> String {
        var parts: [String] = []
        // Формульный расход в подписи нужен только рядом с измеренным — как
        // то, с чем его сравнивают. Когда считаем по формуле, он уже написан
        // крупно выше, и второй раз это просто то же число.
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

    private func miniStat(_ title: LocalizedStringKey, _ value: String,
                          unit: LocalizedStringKey, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.app(.caption2))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(verbatim: value)
                    .font(.app(.subheadline, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(color)
                Text(unit)
                    .font(.app(.caption2))
                    .foregroundStyle(.tertiary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func resultRow(title: LocalizedStringKey, value: String, highlighted: Bool = false) -> some View {
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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(isOn: Binding(get: { store.usesAdaptiveTDEE },
                                         set: { store.usesAdaptiveTDEE = $0 })) {
                        Text("Считать по факту")
                    }
                    .disabled(store.adaptiveTDEE == nil)
                    .accessibilityIdentifier("useAdaptiveTDEE")
                } footer: {
                    if let fact = store.adaptiveTDEE {
                        Text(String(format: String(localized: "По дневнику и весам: около %1$lld ккал в день, данных за %2$lld дн. Формула даёт %3$lld."),
                                    Int((store.smoothedTDEE ?? fact.tdee).rounded()), fact.loggedDays,
                                    Int((store.profile?.tdee ?? 0).rounded())))
                    } else {
                        Text("Расход по факту появится, когда наберётся две недели дневника и взвешиваний. До тех пор считаем по формуле.")
                    }
                }

                if !(store.usesAdaptiveTDEE && store.adaptiveTDEE != nil) {
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
                        Text("Множитель к базовому обмену. Он нужен, только пока расход считается по формуле: измеренный расход уже знает и работу, и зал.")
                    }
                }
            }
            .glassRow()
            .listStyle(.insetGrouped)
            .navigationTitle("Как считаем")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    CheckmarkButton { dismiss() }
                }
            }
        }
    }
}
