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
        _fatTenths = State(initialValue: max(4, Int((fKg * 10).rounded())))
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
            macroBudgetRow("Белки", grams: protein, color: .blue)
            macroBudgetRow("Жиры", grams: fat, color: .orange)
            if carbs > 0 {
                macroBudgetRow("Углеводы", grams: carbs, color: .purple)
            } else {
                Label(
                    String(
                        format: String(localized: "Белок и жир не помещаются в норму: не хватает %d ккал. Подними калораж или опусти норму белка."),
                        Int((locked - goal).rounded())
                    ),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.footnote)
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
                .font(.body.weight(.semibold))
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
            if store.plan == nil {
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
                                .font(.caption)
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
                            VStack(alignment: .leading, spacing: 2) {
                                Text(level.title)
                                    .foregroundStyle(.primary)
                                Text(level.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if activityLevel == level {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                }
            } header: {
                Text("Уровень активности")
            } footer: {
                Text("Считай сумму работы и зала, а не один зал: восемь часов на ногах — это те же 300–600 ккал в день, что и пара тренировок. Множитель в любом случае приблизительный, точный расход покажет тренд веса за две-три недели.")
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
                            .font(.body.weight(.semibold))
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
                        ForEach(4...20, id: \.self) { Text(String(format: "%.1f", Double($0) / 10.0)).tag($0) }
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
                            .font(.body.weight(.semibold))
                    }
                }
            } header: {
                Text("Норма жира")
            } footer: {
                Text("Обычно 0.8 г на кг веса. Ниже 0.5 это уже не диета, а ставка на гормоны — жир нужен телу постоянно, а не по остаточному принципу.")
            }

            if let draftProfile, store.dailyGoal > 0 {
                macroBudgetSection(draftProfile)
            }
            
            if let draftProfile {
                Section {
                    HStack {
                        Text("Жир % (оценка)")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.1f%%", draftProfile.bodyFatPercentage(from: measurement)))
                            .font(.body.weight(.semibold))
                            .foregroundStyle(BodyFatStyle.color(for: draftProfile.bodyFatCategory(from: measurement)))
                        Text("· ") + Text(LocalizedStringKey(draftProfile.bodyFatCategory(from: measurement)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("bodyFatRow")
                    
                    HStack {
                        Text("ИМТ")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.1f", draftProfile.bmi))
                            .font(.body.weight(.semibold))
                            .foregroundStyle(bmiColor(draftProfile.bmi))
                        (Text("· ") + Text(LocalizedStringKey(bmiLabel(draftProfile.bmi))))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    resultRow(title: "Базовый обмен (BMR)", value: "\(Int(draftProfile.bmr.rounded())) \(String(localized: "ккал"))")
                    resultRow(title: "Расход с активностью (TDEE)", value: "\(Int(draftProfile.tdee.rounded())) \(String(localized: "ккал"))")
                    // Цель редактируется здесь, а не долгим нажатием на кольцо.
                    // Жест был невидимый и позволял вписать число, спорящее
                    // с планом: план цель считает, и правка руками потом молча
                    // отменялась на первой же смене профиля.
                    if store.plan != nil {
                        HStack {
                            Text("Целевые калории")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(verbatim: "\(store.dailyGoal) \(String(localized: "ккал"))")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.green)
                            Image(systemName: "target")
                                .font(.caption)
                                .foregroundStyle(.yellow)
                        }
                        .accessibilityIdentifier("calorieTargetRow")
                    } else {
                        Button {
                            goalText = String(store.dailyGoal)
                            showingGoalEditor = true
                        } label: {
                            HStack {
                                Text("Целевые калории")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(verbatim: "\(store.dailyGoal) \(String(localized: "ккал"))")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.green)
                                Image(systemName: "pencil")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("calorieTargetRow")
                    }
                    resultRow(title: "Целевой белок", value: "\(Int(draftProfile.proteinTargetGrams(from: measurement).rounded())) \(String(localized: "г"))", highlighted: true)
                } header: {
                    Text("Расчёт")
                } footer: {
                    if store.plan != nil {
                        Text("Норму задаёт план — он пересчитывает её на каждый день фазы. Чтобы поменять, правь план.")
                    }
                    Text(draftProfile.isNavyMethod(from: measurement)
                         ? String(localized: "Жир считается методом ВМС США по обхватам из замеров, точность ±2–3%. Чтобы уточнить, снимай их в одном и том же месте.")
                         : String(localized: "Жир считается по формуле Дойренберга от ИМТ, точность ±5%: она не различает мышцы и жир. Сними шею и пояс в замерах — тогда включится метод по обхватам."))
                }
            }
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
        .navigationTitle("Тело")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
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

                    NavigationLink {
                        SettingsView(store: store)
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityIdentifier("openSettings")
                }
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
