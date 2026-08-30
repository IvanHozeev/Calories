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
    @State private var heightInt: Int
    @State private var ageInt: Int
    @State private var proteinTenths: Int
    @State private var showWeightPicker = false
    @State private var showHeightPicker = false
    @State private var showAgePicker = false
    @State private var showProteinPicker = false
    @State private var sex: Sex
    @State private var activityLevel: ActivityLevel
    @State private var goal: Goal
    @State private var waistCm: Int
    @State private var neckCm: Int
    @State private var hipCm: Int
    @AppStorage("use_imperial") private var useImperial = false

    private func weightDisplayText(_ tenths: Int) -> String {
        let kg = Double(tenths) / 10.0
        return useImperial
            ? String(format: "%.1f \(String(localized: "фунт"))", kg * 2.20462)
            : String(format: "%.1f \(String(localized: "кг"))", kg)
    }

    private func heightDisplayText(_ cm: Int) -> String {
        guard useImperial else { return "\(cm) \(String(localized: "см"))" }
        let totalInches = Double(cm) / 2.54
        let feet = Int(totalInches) / 12
        let inches = Int(totalInches.truncatingRemainder(dividingBy: 12))
        return "\(feet)' \(inches)\""
    }

    init(store: CalorieStore) {
        self.store = store
        let profile = store.profile
        let wKg = store.latestWeight?.weightKg ?? profile?.weightKg ?? 70.0
        _weightTenths = State(initialValue: max(300, Int((wKg * 10).rounded())))
        let hCm = Int((profile?.heightCm ?? 170).rounded())
        _heightInt = State(initialValue: hCm > 0 ? hCm : 170)
        _ageInt = State(initialValue: profile?.age ?? 25)
        let pKg = profile?.proteinPerKg ?? UserProfile.defaultProteinPerKg
        _proteinTenths = State(initialValue: max(10, Int((pKg * 10).rounded())))
        _sex = State(initialValue: profile?.sex ?? .male)
        _activityLevel = State(initialValue: profile?.activityLevel ?? .moderate)
        _goal = State(initialValue: profile?.goal ?? .maintenance)
        _waistCm = State(initialValue: Int((profile?.waistCm ?? 0).rounded()))
        _neckCm = State(initialValue: Int((profile?.neckCm ?? 0).rounded()))
        _hipCm = State(initialValue: Int((profile?.hipCm ?? 0).rounded()))
    }

    private var waist: Double? { waistCm > 0 ? Double(waistCm) : nil }
    private var neck: Double? { neckCm > 0 ? Double(neckCm) : nil }
    private var hip: Double? { hipCm > 0 ? Double(hipCm) : nil }

    private var draftProfile: UserProfile? {
        UserProfile(
            weightKg: Double(weightTenths) / 10.0,
            heightCm: Double(heightInt),
            age: ageInt,
            sex: sex,
            activityLevel: activityLevel,
            goal: goal,
            proteinPerKg: Double(proteinTenths) / 10.0,
            waistCm: waist,
            neckCm: neck,
            hipCm: hip
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
                    HStack {
                        Text(LocalizedStringKey(useImperial ? "Вес, фунт" : "Вес, кг"))
                        Spacer()
                        Text(weightDisplayText(weightTenths))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showWeightPicker.toggle()
                            if showWeightPicker { showHeightPicker = false; showAgePicker = false; showProteinPicker = false }
                        }
                    }
                    if showWeightPicker {
                        Picker("Вес", selection: $weightTenths) {
                            ForEach(300...1500, id: \.self) { v in
                                Text(useImperial
                                     ? String(format: "%.1f", Double(v) / 10.0 * 2.20462)
                                     : String(format: "%.1f", Double(v) / 10.0)
                                ).tag(v)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(height: 160)
                    }
                    NavigationLink {
                        WeightDetailView(store: store)
                    } label: {
                        HStack {
                            Text("Динамика")
                            Spacer()
                            if let trend = weightTrend {
                                Text(trend.caption)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                WeightSparkline(points: trend.points)
                                    .frame(width: 56, height: 20)
                            } else {
                                Text("Мало данных")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .accessibilityIdentifier("openWeight")

                    HStack {
                        Text(LocalizedStringKey(useImperial ? "Рост, фт+дюйм" : "Рост, см"))
                        Spacer()
                        Text(heightDisplayText(heightInt))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showHeightPicker.toggle()
                            if showHeightPicker { showWeightPicker = false; showAgePicker = false; showProteinPicker = false }
                        }
                    }
                    if showHeightPicker {
                        Picker("Рост", selection: $heightInt) {
                            ForEach(100...250, id: \.self) { v in
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
                            if showAgePicker { showWeightPicker = false; showHeightPicker = false; showProteinPicker = false }
                        }
                    }
                    if showAgePicker {
                        Picker("Возраст", selection: $ageInt) {
                            ForEach(5...100, id: \.self) { Text("\($0)").tag($0) }
                        }
                        .pickerStyle(.wheel)
                        .frame(height: 160)
                    }
                    NavigationLink {
                        BodyFatDetailView(
                            waistCm: $waistCm,
                            neckCm: $neckCm,
                            hipCm: $hipCm,
                            sex: sex,
                            profile: draftProfile
                        )
                    } label: {
                        HStack {
                            Text("Жир % (оценка)")
                                .foregroundStyle(.secondary)
                            Spacer()
                            if let draftProfile {
                                Text(String(format: "%.1f%%", draftProfile.bodyFatPercentage))
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(BodyFatStyle.color(for: draftProfile.bodyFatCategory))
                                Text("· ") + Text(LocalizedStringKey(draftProfile.bodyFatCategory))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("—")
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }

                    NavigationLink {
                        MeasurementsView(store: store)
                    } label: {
                        HStack {
                            Text("Замеры")
                            Spacer()
                            Text(measurementsCaption)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("openMeasurements")
                }

                Section("Уровень активности") {
                    ForEach(ActivityLevel.allCases) { level in
                        Button {
                            activityLevel = level
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
                }

                Section {
                    HStack {
                        Text("Белка на кг веса")
                        Spacer()
                        Text(String(format: "%.1f \(String(localized: "г/кг"))", Double(proteinTenths) / 10.0))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showProteinPicker.toggle()
                            if showProteinPicker { showWeightPicker = false; showHeightPicker = false; showAgePicker = false }
                        }
                    }
                    if showProteinPicker {
                        Picker("Белок", selection: $proteinTenths) {
                            ForEach(10...50, id: \.self) { Text(String(format: "%.1f", Double($0) / 10.0)).tag($0) }
                        }
                        .pickerStyle(.wheel)
                        .frame(height: 160)
                    }
                } header: {
                    Text("Норма белка")
                } footer: {
                    Text("Обычно 1.6–2.2 г на кг веса при цели набора массы или похудения с сохранением мышц.")
                }

                if let draftProfile {
                    Section("Расчёт") {
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
                        resultRow(title: "Целевые калории", value: "\(draftProfile.calorieTarget) \(String(localized: "ккал"))", highlighted: true)
                        resultRow(title: "Целевой белок", value: "\(Int(draftProfile.proteinTargetGrams.rounded())) \(String(localized: "г"))", highlighted: true)
                    }
                }
        }
        .glassRow()
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
        .scrollIndicators(.hidden)
        .navigationTitle("Тело")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink {
                    SettingsView(store: store)
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityIdentifier("openSettings")
            }
        }
        .onChange(of: draftProfile) { _, newProfile in
            if let p = newProfile { store.updateProfile(p) }
        }
    }

    private var measurementsCaption: String {
        guard let latest = store.latestMeasurement else { return String(localized: "Нет замеров") }
        return latest.date.formatted(.dateTime.day().month(.abbreviated))
    }

    /// Динамика за месяц: искра и изменение. Строка с одной лишь стрелкой «дальше»
    /// ничего не сообщала бы, а так тренд виден не заходя внутрь.
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

private struct BodyFatDetailView: View {
    @Binding var waistCm: Int
    @Binding var neckCm: Int
    @Binding var hipCm: Int
    let sex: Sex
    let profile: UserProfile?

    @State private var showWaistPicker = false
    @State private var showNeckPicker = false
    @State private var showHipPicker = false


    var body: some View {
        Form {
            if let profile {
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(format: "%.1f%%", profile.bodyFatPercentage))
                                .font(.largeTitle.weight(.bold))
                                .foregroundStyle(BodyFatStyle.color(for: profile.bodyFatCategory))
                            Text(LocalizedStringKey(profile.bodyFatCategory))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: profile.isNavyMethod ? "ruler" : "scalemass")
                            .font(.title2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                } footer: {
                    if profile.isNavyMethod {
                        Text("Метод ВМС США: расчёт по обхватам талии и шеи. Точность ±2–3%. Меряй в одном месте каждый раз.")
                    } else {
                        Text("Формула Дойренберга: расчёт по ИМТ. Не различает мышцы и жир — у спортивных людей завышает на 3–5%. Для точности укажи обхваты ниже.")
                    }
                }
            }

            Section {
                HStack {
                    Text("Талия, см")
                    Spacer()
                    Text(waistCm > 0 ? "\(waistCm) см" : "—")
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showWaistPicker.toggle()
                        if showWaistPicker { showNeckPicker = false; showHipPicker = false }
                    }
                }
                if showWaistPicker {
                    Picker("Талия", selection: $waistCm) {
                        Text("—").tag(0)
                        ForEach(50...150, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 160)
                }

                HStack {
                    Text("Шея, см")
                    Spacer()
                    Text(neckCm > 0 ? "\(neckCm) см" : "—")
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showNeckPicker.toggle()
                        if showNeckPicker { showWaistPicker = false; showHipPicker = false }
                    }
                }
                if showNeckPicker {
                    Picker("Шея", selection: $neckCm) {
                        Text("—").tag(0)
                        ForEach(25...60, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 160)
                }

                if sex == .female {
                    HStack {
                        Text("Бёдра, см")
                        Spacer()
                        Text(hipCm > 0 ? "\(hipCm) см" : "—")
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showHipPicker.toggle()
                            if showHipPicker { showWaistPicker = false; showNeckPicker = false }
                        }
                    }
                    if showHipPicker {
                        Picker("Бёдра", selection: $hipCm) {
                            Text("—").tag(0)
                            ForEach(60...150, id: \.self) { Text("\($0)").tag($0) }
                        }
                        .pickerStyle(.wheel)
                        .frame(height: 160)
                    }
                }
            } header: {
                Text("Замеры")
            } footer: {
                Text("Меряй утром натощак сантиметровой лентой. Талия — на уровне пупка, шея — под кадыком.")
            }
        }
        .glassRow()
        .navigationTitle("Жир %")
        .navigationBarTitleDisplayMode(.inline)
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
