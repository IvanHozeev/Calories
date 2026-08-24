import SwiftUI

struct OnboardingView: View {
    var store: CalorieStore
    @AppStorage("onboarding_completed") private var onboardingCompleted = false

    @State private var step = 0
    @State private var goal: Goal = .fatLoss
    @State private var sex: Sex = .male
    @State private var age = 25
    @State private var heightInt = 170
    @State private var weightTenths = 750  // 75.0 kg
    @State private var activityLevel: ActivityLevel = .moderate

    private var draftProfile: UserProfile {
        UserProfile(
            weightKg: Double(weightTenths) / 10.0,
            heightCm: Double(heightInt),
            age: age,
            sex: sex,
            activityLevel: activityLevel,
            goal: goal,
            proteinPerKg: UserProfile.defaultProteinPerKg
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if step > 0 { topBar }

            Group {
                switch step {
                case 0: welcomeStep
                case 1: goalStep
                case 2: sexStep
                case 3: ageStep
                case 4: heightStep
                case 5: weightStep
                case 6: activityStep
                case 7: resultStep
                default: EmptyView()
                }
            }
            .id(step)
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        ZStack {
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { step -= 1 }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack(spacing: 6) {
                ForEach(1...7, id: \.self) { i in
                    Capsule()
                        .fill(i < step ? Color.green : i == step ? Color.green : Color(.systemGray5))
                        .frame(width: i == step ? 22 : 8, height: 6)
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
            VStack(spacing: 20) {
                Text("🔥")
                    .font(.system(size: 80))
                Text("Привет!")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                Text("Давай настроим твою персональную норму калорий — займёт меньше минуты.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            Spacer()
            primaryButton(title: "Начать") {
                withAnimation(.easeInOut(duration: 0.25)) { step = 1 }
            }
        }
    }

    private var goalStep: some View {
        stepShell(title: "Какая цель?", subtitle: "Это влияет на твою дневную норму калорий") {
            VStack(spacing: 12) {
                ForEach(Goal.allCases) { g in
                    rowCard(icon: goalIcon(g), title: g.title, selected: goal == g) {
                        goal = g
                    }
                }
            }
        } next: {
            withAnimation(.easeInOut(duration: 0.25)) { step += 1 }
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
        } next: {
            withAnimation(.easeInOut(duration: 0.25)) { step += 1 }
        }
    }

    private var ageStep: some View {
        stepShell(title: "Сколько лет?", subtitle: "Возраст влияет на базовый обмен") {
            Picker("Возраст", selection: $age) {
                ForEach(10...100, id: \.self) { Text("\($0) лет").tag($0) }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: 240)
        } next: {
            withAnimation(.easeInOut(duration: 0.25)) { step += 1 }
        }
    }

    private var heightStep: some View {
        stepShell(title: "Рост, см", subtitle: "Нужен для расчёта базового обмена") {
            Picker("Рост", selection: $heightInt) {
                ForEach(100...220, id: \.self) { Text("\($0) см").tag($0) }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: 240)
        } next: {
            withAnimation(.easeInOut(duration: 0.25)) { step += 1 }
        }
    }

    private var weightStep: some View {
        stepShell(title: "Вес, кг", subtitle: "Нужен для расчёта нормы калорий и белка") {
            Picker("Вес", selection: $weightTenths) {
                ForEach(300...2000, id: \.self) { v in
                    Text(String(format: "%.1f кг", Double(v) / 10.0)).tag(v)
                }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: 240)
        } next: {
            withAnimation(.easeInOut(duration: 0.25)) { step += 1 }
        }
    }

    private var activityStep: some View {
        stepShell(title: "Активность", subtitle: "Средняя нагрузка за типичную неделю") {
            VStack(spacing: 8) {
                ForEach(ActivityLevel.allCases) { level in
                    Button {
                        activityLevel = level
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(level.title)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(.primary)
                                Text(level.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if activityLevel == level {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(activityLevel == level ? Color.green.opacity(0.1) : Color(.secondarySystemBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(activityLevel == level ? Color.green : Color.clear, lineWidth: 1.5)
                        )
                    }
                }
            }
        } next: {
            withAnimation(.easeInOut(duration: 0.25)) { step += 1 }
        }
    }

    private var resultStep: some View {
        let p = draftProfile
        return VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 24) {
                Text("🎯")
                    .font(.system(size: 64))
                Text("Готово!")
                    .font(.system(size: 34, weight: .bold, design: .rounded))

                VStack(spacing: 10) {
                    statRow(title: "Базовый обмен (BMR)", value: "\(Int(p.bmr.rounded())) ккал")
                    statRow(title: "С активностью (TDEE)", value: "\(Int(p.tdee.rounded())) ккал")

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Норма калорий")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(p.calorieTarget)")
                                .font(.system(size: 36, weight: .bold, design: .rounded))
                                .foregroundStyle(.green)
                            Text("ккал / день")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("Норма белка")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(Int(p.proteinTargetGrams.rounded()))")
                                .font(.system(size: 36, weight: .bold, design: .rounded))
                                .foregroundStyle(.blue)
                            Text("г / день")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal, 24)
            }
            Spacer()
            primaryButton(title: "Начать") {
                store.updateProfile(draftProfile)
                onboardingCompleted = true
            }
        }
    }

    // MARK: - Layout helpers

    @ViewBuilder
    private func stepShell<Content: View>(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        @ViewBuilder content: () -> Content,
        next: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 20)
            .padding(.horizontal, 24)

            Spacer()

            content()
                .padding(.horizontal, 24)

            Spacer()

            primaryButton(title: "Далее", action: next)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func primaryButton(title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.green)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 44)
    }

    private func rowCard(icon: String, title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Text(icon).font(.title2)
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(selected ? Color.green.opacity(0.1) : Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(selected ? Color.green : Color.clear, lineWidth: 1.5)
            )
        }
    }

    private func tileCard(icon: String, title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Text(icon).font(.system(size: 36))
                Text(title)
                    .font(.body.weight(.medium))
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
    }

    private func statRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func goalIcon(_ g: Goal) -> String {
        switch g {
        case .fatLoss: return "🔻"
        case .maintenance: return "⚖️"
        case .muscleGain: return "💪"
        }
    }
}
