import SwiftUI
import Charts

struct WeeklyChartView: View {
    let days: [DaySummary]
    var title: String = "Эта неделя"

    private var goal: Int {
        days.first?.goal ?? 0
    }

    private var useWeekdayLabels: Bool {
        days.count <= 7
    }

    /// Шаг между подписями на оси X — чтобы при 30/90 днях подписи не наезжали друг на друга,
    /// показываем примерно 5-6 подписей независимо от длины диапазона.
    private var axisStride: Int {
        max(1, days.count / 6)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Text("Цель: \(goal) ккал")
                    .font(.caption)
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

                RuleMark(y: .value("Цель", goal))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            .chartXAxis {
                if useWeekdayLabels {
                    AxisMarks(values: .stride(by: .day)) { _ in
                        AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: true)
                    }
                } else {
                    AxisMarks(values: .stride(by: .day, count: axisStride)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.day().month(.defaultDigits))
                    }
                }
            }
            .frame(height: 200)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
