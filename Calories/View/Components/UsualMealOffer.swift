import SwiftUI

/// Пустой день: привычный приём этого часа и запись одним касанием.
///
/// Стоит на месте значка пустого лотка. Лоток говорил «ничего нет» и ничего
/// не предлагал; эта строка говорит, что человек обычно ест сейчас, и
/// записывает это сразу — без листа, поиска и черновика. Ошибся — запись
/// удаляется свайпом, как любая другая.
struct UsualMealOffer: View {
    let usual: UsualMeal.Suggestion
    let period: MealPeriod
    var onLog: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text("Как обычно")
                    Text(verbatim: "·").foregroundStyle(.tertiary)
                    Text(LocalizedStringKey(period.rawValue))
                }
                .font(.app(.caption))
                .foregroundStyle(.secondary)

                Text(verbatim: usual.parts.map(\.name).joined(separator: ", "))
                    .font(.app(.subheadline, weight: .medium))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(verbatim: String(format: String(localized: "%lld ккал"), usual.calories))
                    .font(.app(.caption))
                    .foregroundStyle(ProgressRing.kcalColors[0])
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
            Button(action: onLog) {
                Text("Записать")
                    .font(.app(.subheadline, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .accessibilityIdentifier("logUsualMeal")
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("usualMealOffer")
    }
}
