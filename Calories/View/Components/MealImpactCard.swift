import SwiftUI

/// «После этого приёма»: что останется от дня и как идёт белок.
///
/// Стоит на экране порции между карточкой продукта и количеством. Человек
/// выбирает граммы, глядя на это число, а не на калории порции самой по себе:
/// сто восемьдесят граммов — это либо «влезает», либо «уже перебор», и сказать
/// это можно только в сравнении с днём. Кольцо слева — тот же знак, что на
/// «Сегодня», но уже с этой порцией.
struct MealImpactCard: View {
    let impact: MealImpact

    /// Интерполяцией, а не `String(format:)`: так число получает разделитель
    /// разрядов по языку — «2 547», а не «2547», как на кольце «Сегодня».
    private var headline: Text {
        impact.isOver
            ? Text("Перебор на \(-impact.remainingAfter) ккал")
            : Text("Останется \(impact.remainingAfter) ккал")
    }

    private var proteinLine: Text? {
        guard let target = impact.day.proteinTarget, target > 0 else { return nil }
        return Text("Белок: \(Int(impact.proteinAfter.rounded())) из \(Int(target.rounded())) г")
    }

    var body: some View {
        HStack(spacing: 14) {
            ProgressRing(consumed: impact.eatenAfter,
                         goal: impact.day.goal,
                         macros: impact.macrosAfter,
                         proteinTarget: impact.day.proteinTarget,
                         fatTarget: impact.day.fatTarget,
                         carbsTarget: impact.day.carbsTarget,
                         miniature: 44,
                         onOpen: {})
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("После этого приёма")
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
                headline
                    .font(.app(.subheadline, weight: .semibold))
                    .monospacedDigit()
                    // Перебор — тем красным, которым он нарисован в кольце.
                    .foregroundStyle(impact.isOver ? ProgressRing.overColors[0] : Color.primary)
                    .contentTransition(.numericText())
                if let proteinLine {
                    proteinLine
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                if impact.closesProtein {
                    Text("Закроет норму белка")
                        .font(.app(.caption, weight: .semibold))
                        .foregroundStyle(MacroKind.protein.color)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tileSurface(cornerRadius: 18)
        .animation(.easeInOut(duration: 0.2), value: impact)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("mealImpact")
    }
}
