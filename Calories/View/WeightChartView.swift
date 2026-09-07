import SwiftUI
import Charts

/// Точка тренда — среднее взвешиваний в окне вокруг даты.
nonisolated struct WeightTrendPoint: Identifiable {
    let date: Date
    let weightKg: Double
    var id: Date { date }
}

struct WeightChartView: View {
    let entries: [WeightEntry]
    /// Тренд рисуется линией, сырые взвешивания — точками.
    ///
    /// Раньше линия соединяла сырые числа, и график был про воду: соль, углеводы
    /// и гликоген дают колебания больше килограмма, а натурал в дефиците теряет
    /// граммов семьдесят в день. По такой линии направление не читается вовсе.
    var trend: [WeightTrendPoint] = []

    private var minWeight: Double {
        (entries.map(\.weightKg).min() ?? 0) - 1
    }

    private var maxWeight: Double {
        (entries.map(\.weightKg).max() ?? 0) + 1
    }

    private var caption: LocalizedStringKey {
        trend.isEmpty ? "Динамика веса" : "Динамика веса — линия тренда"
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
            Text(caption)
                .font(.headline)

            Chart {
                ForEach(entries) { entry in
                    PointMark(
                        x: .value("Дата", entry.date, unit: .day),
                        y: .value("Вес", entry.weightKg)
                    )
                    .foregroundStyle(.blue.opacity(trend.isEmpty ? 1 : 0.28))
                    .symbolSize(28)
                }
                ForEach(trend) { point in
                    LineMark(
                        x: .value("Дата", point.date, unit: .day),
                        y: .value("Тренд", point.weightKg)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.blue)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
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
