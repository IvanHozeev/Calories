import SwiftUI
import Charts

struct WeeklyChartView: View {
    let days: [DaySummary]

    private var goal: Int {
        days.first?.goal ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Эта неделя")
                .font(.headline)

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
                    .cornerRadius(6)
                }

                RuleMark(y: .value("Цель", goal))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("Цель: \(goal)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: true)
                }
            }
            .frame(height: 200)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
