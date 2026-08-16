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
    }

    private var weight: Double? { Double(weightText.replacingOccurrences(of: ",", with: ".")) }
    private var height: Double? { Double(heightText.replacingOccurrences(of: ",", with: ".")) }
    private var age: Int? { Int(ageText) }
    private var proteinPerKg: Double? { Double(proteinPerKgText.replacingOccurrences(of: ",", with: ".")) }

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
            proteinPerKg: proteinPerKg
        )
    }

    var body: some View {
        Form {
            Section {
                Picker("Цель", selection: $goal) {
                    ForEach(Goal.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                if goal != .maintenance {
                    Button {
                        if store.isPremium {
                            showingPlan = true
                        } else {
                            showingPaywall = true
                        }
                    } label: {
                        HStack {
                            Image(systemName: "sparkles")
                            Text(store.plan != nil ? "План активен — открыть" : "Получить план под эту цель")
                            Spacer()
                            if !store.isPremium {
                                Text("PRO")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.yellow.opacity(0.3))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .disabled(store.profile == nil)
                }
            } header: {
                Text("Цель")
            } footer: {
                if goal != .maintenance, store.profile == nil {
                    Text("Сначала сохрани профиль — план считается по твоим BMR/TDEE.")
                }
            }

            Section {
                HStack {
                    Text("Текущий вес")
                    Spacer()
                    if let latest = store.latestWeight {
                        Text(String(format: "%.1f кг", latest.weightKg))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Не записан")
                            .foregroundStyle(.secondary)
                    }
                }
                Button {
                    showingAddWeight = true
                } label: {
                    Label(store.hasWeighedToday ? "Обновить вес за сегодня" : "Записать вес", systemImage: "plus.circle")
                }
                NavigationLink {
                    WeightView(store: store)
                } label: {
                    Label("История и график", systemImage: "chart.line.uptrend.xyaxis")
                }
            } header: {
                Text("Вес")
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
                        resultRow(title: "Базовый обмен (BMR)", value: "\(Int(draftProfile.bmr.rounded())) ккал")
                        resultRow(title: "Расход с активностью (TDEE)", value: "\(Int(draftProfile.tdee.rounded())) ккал")
                        resultRow(title: "Целевые калории", value: "\(draftProfile.calorieTarget) ккал", highlighted: true)
                        resultRow(title: "Целевой белок", value: "\(Int(draftProfile.proteinTargetGrams.rounded())) г", highlighted: true)
                    }
                }
            }
            .navigationTitle("Профиль")
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
