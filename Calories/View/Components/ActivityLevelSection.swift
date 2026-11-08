import SwiftUI

/// Уровень активности — множитель, на который считается расход по формуле.
///
/// Пока норма идёт от факта, множитель ни на что не влияет: расход измерен, а
/// не угадан. Тогда секции здесь нет вовсе, а выбор уезжает в лист «Как
/// считаем» — вместе с переключателем, который его включает.
struct ActivityLevelSection: View {
    @Binding var draft: ProfileDraft
    let usesFact: Bool

    /// Выбранный, но ещё не подтверждённый уровень.
    @State private var pending: ActivityLevel?

    /// Показываем не «вы уверены», а во что именно обойдётся смена: новую
    /// норму калорий и разницу с текущей.
    private func changeMessage(to level: ActivityLevel) -> String {
        let current = draft.profile
        var updated = current
        updated.activityLevel = level
        let delta = updated.calorieTarget - current.calorieTarget
        let sign = delta > 0 ? "+" : ""
        return String(
            format: String(localized: "Норма станет %d ккал вместо %d — это %@%d ккал в день."),
            updated.calorieTarget, current.calorieTarget, sign, delta
        )
    }

    var body: some View {
        if !usesFact {
            Section {
                ForEach(ActivityLevel.allCases) { level in
                    Button {
                        // Уровень активности множит TDEE, то есть меняет норму
                        // калорий на сотни. Промахнуться по соседней строке
                        // легко, а последствие молчаливое: цифра назавтра
                        // другая, а почему — непонятно.
                        guard level != draft.activityLevel else { return }
                        pending = level
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
                            if draft.activityLevel == level {
                                Image(systemName: "checkmark")
                                    .font(.app(.subheadline, weight: .semibold))
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }
            } header: {
                Text("Уровень активности")
                    .tracksSectionHead(String(localized: "Уровень активности"))
            } footer: {
                explain("Считай сумму работы и зала, а не один зал: восемь часов на ногах — это те же 300–600 ккал в день, что и пара тренировок. Множитель в любом случае приблизительный, точный расход покажет тренд веса за две-три недели.").map { Text($0) }
            }
            .alert("Сменить уровень активности?", isPresented: Binding(
                get: { pending != nil },
                set: { if !$0 { pending = nil } }
            ), presenting: pending) { level in
                Button("Отмена", role: .cancel) { pending = nil }
                Button("Сменить") {
                    draft.activityLevel = level
                    pending = nil
                }
            } message: { level in
                Text(changeMessage(to: level))
            }
        }
    }
}
