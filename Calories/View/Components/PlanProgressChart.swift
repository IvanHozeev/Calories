import SwiftUI
import Charts

/// Факт против плана: пунктир — линейный прогноз от старта к цели, сплошная — реальные взвешивания.
/// Одним взглядом отвечает на вопрос «я в графике?», ради которого раньше приходилось
/// читать три строки цифр в секции «Как идёт план».
struct PlanProgressChart: View {
    let plan: Plan
    let entries: [WeightEntry]

    private var actual: [WeightEntry] {
        entries.filter { $0.date >= plan.startDate }.sorted { $0.date < $1.date }
    }

    private var bounds: ClosedRange<Double> {
        let values = actual.map(\.weightKg) + [plan.startWeightKg, plan.targetWeightKg]
        let low = (values.min() ?? plan.startWeightKg) - 1
        let high = (values.max() ?? plan.startWeightKg) + 1
        return low...high
    }

    private let planSeries = String(localized: "План")
    private let actualSeries = String(localized: "Факт")

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Chart {
                ForEach([
                    (plan.startDate, plan.startWeightKg),
                    (plan.endDate, plan.targetWeightKg)
                ], id: \.0) { point in
                    LineMark(
                        x: .value("Дата", point.0),
                        y: .value("Вес", point.1),
                        series: .value("", planSeries)
                    )
                    .foregroundStyle(by: .value("", planSeries))
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                }

                ForEach(actual) { entry in
                    LineMark(
                        x: .value("Дата", entry.date),
                        y: .value("Вес", entry.weightKg),
                        series: .value("", actualSeries)
                    )
                    .foregroundStyle(by: .value("", actualSeries))
                    .interpolationMethod(.catmullRom)
                    .symbol(Circle())
                }
            }
            .chartForegroundStyleScale([
                actualSeries: Color.blue,
                planSeries: Color.secondary
            ])
            .chartYScale(domain: bounds)
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                    AxisValueLabel()
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.day().month(.defaultDigits))
                }
            }
            .frame(height: 180)
        }
        .padding(.vertical, 4)
    }
}
