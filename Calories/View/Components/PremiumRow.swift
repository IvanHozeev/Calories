import SwiftUI

/// Строка выбора цели — только пока нет ни плана, ни подписки.
///
/// С премиумом режим задаётся планом: вне плана идёт поддержание, и множитель
/// из профиля означал бы вечный дефицит по настройке, о которой забыли.
struct PremiumRow: View {
    let plan: Plan?
    let isPremium: Bool
    let profile: UserProfile?
    @Binding var goal: Goal

    var body: some View {
        if plan == nil, !isPremium {
            Section {
                Picker("Цель", selection: $goal) {
                    ForEach(Goal.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Цель")
            } footer: {
                if profile == nil {
                    Text("Сначала сохрани профиль — план считается по твоим BMR/TDEE.")
                }
            }
        }
    }
}
