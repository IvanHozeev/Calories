import SwiftUI

struct ProfileView: View {
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
    @State private var showingPlan = false
    @State private var showingPaywall = false
    @State private var showingAddWeight = false
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

    private func bodyFatColor(_ category: String) -> Color {
        switch category {
        case "Атлетический", "Фитнес": return .green
        case "Норма": return .yellow
        default: return .red
        }
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
                                    .foregroundStyle(bodyFatColor(draftProfile.bodyFatCategory))
                                Text("· ") + Text(LocalizedStringKey(draftProfile.bodyFatCategory))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("—")
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
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

                Section("Настройки") {
                    NavigationLink {
                        UnitsSettingsView()
                    } label: {
                        Label("Единицы измерения", systemImage: "globe")
                    }
                    NavigationLink {
                        RemindersView()
                    } label: {
                        Label("Напоминания", systemImage: "bell")
                    }
                    NavigationLink {
                        LanguageSettingsView()
                    } label: {
                        Label("Язык", systemImage: "character.bubble")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)
            .navigationTitle("Профиль")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        if store.isPremium {
                            showingPlan = true
                        } else {
                            showingPaywall = true
                        }
                    } label: {
                        Image(systemName: store.plan != nil ? "sparkles" : "sparkles")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(store.plan != nil ? .yellow : .secondary)
                    }
                    .disabled(store.profile == nil && !store.isPremium)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        WeightView(store: store)
                    } label: {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddWeight = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .onChange(of: draftProfile) { _, newProfile in
                if let p = newProfile { store.updateProfile(p) }
            }
            .sheet(isPresented: $showingPlan) {
                PlanView(store: store)
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView(store: store)
            }
            .sheet(isPresented: $showingAddWeight) {
                AddWeightView(store: store)
                    .presentationDetents([.medium])
            }
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

private struct UnitsSettingsView: View {
    @AppStorage("use_imperial") private var useImperial = false

    var body: some View {
        List {
            Section {
                Picker("Система", selection: $useImperial) {
                    Text("Метрическая").tag(false)
                    Text("Американская").tag(true)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Система")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Единицы измерения")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct LanguageSettingsView: View {
    @State private var selectedLanguage: String
    @State private var showRestartAlert = false

    init() {
        let saved = UserDefaults.standard.array(forKey: "AppleLanguages")?.first as? String
        let lang: String
        if let saved {
            lang = String(saved.prefix(2))
        } else {
            lang = Locale.preferredLanguages.first?.hasPrefix("ru") == true ? "ru" : "en"
        }
        _selectedLanguage = State(initialValue: lang)
    }

    var body: some View {
        List {
            Section {
                languageRow(code: "ru", title: "Русский", flag: "🇷🇺")
                languageRow(code: "en", title: "English", flag: "🇺🇸")
                languageRow(code: "he", title: "עברית", flag: "🇮🇱")
                languageRow(code: "es", title: "Español", flag: "🇪🇸")
                languageRow(code: "ar", title: "العربية", flag: "🇸🇦")
                languageRow(code: "pt", title: "Português", flag: "🇧🇷")
                languageRow(code: "fr", title: "Français", flag: "🇫🇷")
                languageRow(code: "de", title: "Deutsch", flag: "🇩🇪")
            } footer: {
                Text("Для применения нового языка перезапусти приложение.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Язык")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Перезапусти приложение", isPresented: $showRestartAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Закрой и открой приложение заново, чтобы язык применился.")
        }
    }

    private func languageRow(code: String, title: String, flag: String) -> some View {
        Button {
            guard selectedLanguage != code else { return }
            selectedLanguage = code
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
            showRestartAlert = true
        } label: {
            HStack {
                Text(flag)
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                if selectedLanguage == code {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.green)
                }
            }
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

    private func bodyFatColor(_ category: String) -> Color {
        switch category {
        case "Атлетический", "Фитнес": return .green
        case "Норма": return .yellow
        default: return .red
        }
    }

    var body: some View {
        Form {
            if let profile {
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(format: "%.1f%%", profile.bodyFatPercentage))
                                .font(.largeTitle.weight(.bold))
                                .foregroundStyle(bodyFatColor(profile.bodyFatCategory))
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
        .navigationTitle("Жир %")
        .navigationBarTitleDisplayMode(.inline)
    }
}
