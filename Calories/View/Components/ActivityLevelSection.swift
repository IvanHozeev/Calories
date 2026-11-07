import SwiftUI

/// Секция выбора уровня активности — показана только когда расход считается
/// по формуле. Измеренный расход уже знает работу и зал, множитель не нужен.
struct ActivityLevelSection: View {
    @Binding var activityLevel: ActivityLevel
    @Binding var pendingActivity: ActivityLevel?
    let usesFact: Bool

    var body: some View {
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
                explain("Считай сумму работы и зала, а не один зал: восемь часов на ногах — это те же 300–600 ккал в день, что и пара тренировок. Множитель в любом случае приблизительный, точный расход покажет тренд веса за две-три недели.").map { Text($0) }
            }
        }
    }
}
