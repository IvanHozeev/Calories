import SwiftUI
import Charts

struct WeeklyChartView: View {
    let days: [DaySummary]
    var title: LocalizedStringKey = "Эта неделя"

    private var uniqueGoals: [Int] {
        Array(Set(days.map(\.goal))).sorted()
    }

    /// Если у всех дней одна и та же цель — не цикл, можно рисовать единую линию/подпись.
    private var flatGoal: Int? {
        uniqueGoals.count == 1 ? uniqueGoals.first : nil
    }

    private var goalLabel: String {
        let goal = String(localized: "Цель:")
        let kcal = String(localized: "ккал")
        if let flatGoal {
            return "\(goal) \(flatGoal) \(kcal)"
        } else if let min = uniqueGoals.first, let max = uniqueGoals.last {
            let cycle = String(localized: "цикл")
            return "\(goal) \(min)–\(max) \(kcal) (\(cycle))"
        }
        return ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.app(.headline))
                Spacer()
                Text(verbatim: goalLabel)
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 8)

            Chart {
                ForEach(days) { day in
                    BarMark(
                        x: .value("День", day.date, unit: .day),
                        y: .value("Калории", day.totalCalories)
                    )
                    .foregroundStyle(
                        day.totalCalories > day.goal
                            ? Color.red.gradient
                            : Color.green.gradient
                    )
                    .cornerRadius(4)
                }

                // Линию цели рисуем только когда она одна на все дни — при цикле она бы
                // просто путала (день сравнивается со своей целью через цвет столбца, не с линией).
                if let flatGoal {
                    RuleMark(y: .value("Цель", flatGoal))
                        .foregroundStyle(.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                    AxisValueLabel()
                }
            }
            .dayAxis(points: days.count)
            .frame(height: 200)
        }
        .padding()
        .glassCard()
    }
}
