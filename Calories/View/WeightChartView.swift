import SwiftUI
import Charts

struct WeightChartView: View {
    let entries: [WeightEntry]

    private var minWeight: Double {
        (entries.map(\.weightKg).min() ?? 0) - 1
    }

    private var maxWeight: Double {
        (entries.map(\.weightKg).max() ?? 0) + 1
    }

    private var useWeekdayLabels: Bool {
        entries.count <= 7
    }

    /// Шаг между подписями на оси X — как в WeeklyChartView, чтобы подписи не наезжали друг на друга.
    private var axisStride: Int {
        max(1, entries.count / 6)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Динамика веса")
                .font(.headline)

            Chart {
                ForEach(entries) { entry in
                    LineMark(
                        x: .value("Дата", entry.date, unit: .day),
                        y: .value("Вес", entry.weightKg)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.blue)
                    .symbol(Circle())
                }
            }
            .chartYScale(domain: minWeight...maxWeight)
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
        .glassCard()
    }
}
