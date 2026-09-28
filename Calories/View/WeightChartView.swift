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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(caption)
                .font(.app(.headline))

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
            .dayAxis(points: entries.count)
            .frame(height: 200)
        }
        .padding()
        .glassCard()
    }
}
