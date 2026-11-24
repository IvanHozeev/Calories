import SwiftUI

/// Итог одного дня из истории: кольцо, число, вердикт и три макроса с нормой.
///
/// Раньше сверху стояли два числа — «Итого» и «Цель» — и строка макросов без
/// нормы: чтобы понять, хорошо ли прошёл день, надо было сравнивать их в
/// уме. Теперь вердикт сказан словом («Перебор на 410 ккал»), а у каждого
/// макроса рядом с числом его норма и полоска.
struct DaySummaryCard: View {
    let calories: Int
    let goal: Int
    let macros: Macros
    let hasEntries: Bool
    let proteinTarget: Double?
    let fatTarget: Double?
    let carbsTarget: Double?

    @Environment(\.colorScheme) private var colorScheme

    private var standing: DayStanding {
        DayStanding(consumed: calories, goal: goal, hasEntries: hasEntries)
    }

    private var verdict: (text: Text, color: Color)? {
        switch standing {
        case .empty: return nil
        case .onGoal: return (Text("В норме"), ProgressRing.kcalColors[0])
        case .under(let kcal): return (Text("Недобор на \(kcal) ккал"), ProgressRing.overColors[0])
        case .over(let kcal): return (Text("Перебор на \(kcal) ккал"), ProgressRing.overColors[0])
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 16) {
                ProgressRing(consumed: calories, goal: goal, macros: macros,
                             proteinTarget: proteinTarget, fatTarget: fatTarget,
                             carbsTarget: carbsTarget, miniature: 84, onOpen: {})
                    .frame(width: 84, height: 84)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(calories) ккал")
                        .font(.app(.title, weight: .bold))
                        .monospacedDigit()
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    Text("Цель \(goal) ккал")
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    if let verdict {
                        verdict.text
                            .font(.app(.subheadline, weight: .semibold))
                            .foregroundStyle(verdict.color)
                            .monospacedDigit()
                    }
                }
                Spacer(minLength: 0)
            }

            HStack(alignment: .top, spacing: 12) {
                column(.protein, value: macros.protein, target: proteinTarget)
                column(.fat, value: macros.fat, target: fatTarget)
                column(.carbs, value: macros.carbs, target: carbsTarget)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tileSurface(cornerRadius: 20)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("daySummary")
    }

    private func column(_ kind: MacroKind, value: Double, target: Double?) -> some View {
        let progress = target.map { $0 > 0 ? min(value / $0, 1) : 0 } ?? 0
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Circle().fill(kind.color).frame(width: 7, height: 7)
                Text(kind.title)
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(verbatim: "\(Int(value.rounded()))")
                    .font(.app(.headline, weight: .bold))
                    // Чёрным в светлой теме: голубой и персиковый на белом
                    // читаются хуже. Цвет макроса — в точке и полоске.
                    .foregroundStyle(colorScheme == .dark ? kind.color : Color.primary)
                if let target {
                    Text(verbatim: "/ \(Int(target.rounded())) \(String(localized: "г"))")
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                }
            }
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            // С объёмом, как у полосок макросов на «Сегодня» и у дуг кольца:
            // плоская заливка в карточке дня читалась другим материалом, хотя
            // это тот же макрос и тот же цвет.
            RubberBar(color: kind.color, progress: progress, height: 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
