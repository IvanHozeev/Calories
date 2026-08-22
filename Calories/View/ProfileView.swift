import SwiftUI

struct ProfileView: View {
    @ObservedObject var store: CalorieStore

    @State private var weightText: String
    @State private var heightText: String
    @State private var ageText: String
    @State private var sex: Sex
    @State private var activityLevel: ActivityLevel
    @State private var goal: Goal
    @State private var proteinPerKgText: String
    @State private var waistText: String
    @State private var neckText: String
    @State private var hipText: String
    @State private var showingPlan = false
    @State private var showingPaywall = false
    @State private var showingAddWeight = false

    init(store: CalorieStore) {
        self.store = store
        let profile = store.profile
        _weightText = State(initialValue: store.latestWeight.map { String(format: "%.0f", $0.weightKg) } ?? profile.map { String(format: "%.0f", $0.weightKg) } ?? "")
        _heightText = State(initialValue: profile.map { String(format: "%.0f", $0.heightCm) } ?? "")
        _ageText = State(initialValue: profile.map { String($0.age) } ?? "")
        _sex = State(initialValue: profile?.sex ?? .male)
        _activityLevel = State(initialValue: profile?.activityLevel ?? .moderate)
        _goal = State(initialValue: profile?.goal ?? .maintenance)
        _proteinPerKgText = State(initialValue: profile.map { String(format: "%.1f", $0.proteinPerKg) } ?? String(format: "%.1f", UserProfile.defaultProteinPerKg))
        _waistText = State(initialValue: profile?.waistCm.map { String(format: "%.0f", $0) } ?? "")
        _neckText = State(initialValue: profile?.neckCm.map { String(format: "%.0f", $0) } ?? "")
        _hipText = State(initialValue: profile?.hipCm.map { String(format: "%.0f", $0) } ?? "")
    }

    private var weight: Double? { Double(weightText.replacingOccurrences(of: ",", with: ".")) }
    private var height: Double? { Double(heightText.replacingOccurrences(of: ",", with: ".")) }
    private var age: Int? { Int(ageText) }
    private var proteinPerKg: Double? { Double(proteinPerKgText.replacingOccurrences(of: ",", with: ".")) }
    private var waist: Double? { Double(waistText.replacingOccurrences(of: ",", with: ".")).flatMap { $0 > 0 ? $0 : nil } }
    private var neck: Double? { Double(neckText.replacingOccurrences(of: ",", with: ".")).flatMap { $0 > 0 ? $0 : nil } }
    private var hip: Double? { Double(hipText.replacingOccurrences(of: ",", with: ".")).flatMap { $0 > 0 ? $0 : nil } }

    private var draftProfile: UserProfile? {
        guard let weight, weight > 0,
              let height, height > 0,
              let age, age > 0,
              let proteinPerKg, proteinPerKg > 0 else { return nil }
        return UserProfile(
            weightKg: weight,
            heightCm: height,
            age: age,
            sex: sex,
            activityLevel: activityLevel,
            goal: goal,
            proteinPerKg: proteinPerKg,
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
        Form {
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
                        Text("Вес, кг")
                        Spacer()
                        TextField("70", text: $weightText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                    HStack {
                        Text("Рост, см")
                        Spacer()
                        TextField("175", text: $heightText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                    HStack {
                        Text("Возраст")
                        Spacer()
                        TextField("30", text: $ageText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                    NavigationLink {
                        BodyFatDetailView(
                            waistText: $waistText,
                            neckText: $neckText,
                            hipText: $hipText,
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
                                Text("· \(draftProfile.bodyFatCategory)")
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
                        TextField("1.7", text: $proteinPerKgText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                        Text("г")
                            .foregroundStyle(.secondary)
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
                            Text("· \(bmiLabel(draftProfile.bmi))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        resultRow(title: "Базовый обмен (BMR)", value: "\(Int(draftProfile.bmr.rounded())) ккал")
                        resultRow(title: "Расход с активностью (TDEE)", value: "\(Int(draftProfile.tdee.rounded())) ккал")
                        resultRow(title: "Целевые калории", value: "\(draftProfile.calorieTarget) ккал", highlighted: true)
                        resultRow(title: "Целевой белок", value: "\(Int(draftProfile.proteinTargetGrams.rounded())) г", highlighted: true)
                    }
                }

                Section("Настройки") {
                    NavigationLink {
                        RemindersView()
                    } label: {
                        Label("Напоминания", systemImage: "bell")
                    }
                }
            }
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

    private func resultRow(title: String, value: String, highlighted: Bool = false) -> some View {
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
    @Binding var waistText: String
    @Binding var neckText: String
    @Binding var hipText: String
    let sex: Sex
    let profile: UserProfile?

    private var waist: Double? { Double(waistText.replacingOccurrences(of: ",", with: ".")).flatMap { $0 > 0 ? $0 : nil } }
    private var neck: Double? { Double(neckText.replacingOccurrences(of: ",", with: ".")).flatMap { $0 > 0 ? $0 : nil } }
    private var hip: Double? { Double(hipText.replacingOccurrences(of: ",", with: ".")).flatMap { $0 > 0 ? $0 : nil } }

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
                            Text(profile.bodyFatCategory)
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
                    TextField("80", text: $waistText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                }
                HStack {
                    Text("Шея, см")
                    Spacer()
                    TextField("37", text: $neckText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                }
                if sex == .female {
                    HStack {
                        Text("Бёдра, см")
                        Spacer()
                        TextField("95", text: $hipText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
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
        .scrollDismissesKeyboard(.interactively)
    }
}
