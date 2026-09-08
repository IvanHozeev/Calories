import SwiftUI
import Charts

/// Факт против плана: пунктир — прогноз по фазам, сплошная — реальные взвешивания.
/// Одним взглядом отвечает на вопрос «я в графике?», ради которого раньше приходилось
/// читать три строки цифр в секции «Как идёт план».
struct PlanProgressChart: View {
    let plan: Plan
    let entries: [WeightEntry]

    private var actual: [WeightEntry] {
        entries.filter { $0.date >= plan.startDate }.sorted { $0.date < $1.date }
    }

    /// Прогноз ломаной по границам фаз, а не прямой от старта к цели.
    /// У цепочки «сушка — поддержание — набор» прямая соединяет два конца
    /// и проходит мимо всего, что между ними: на поддержании она продолжает
    /// снижаться, и факт рядом с ней выглядит отставанием.
    private var planned: [(date: Date, weightKg: Double)] {
        var points: [(Date, Double)] = [(plan.startDate, plan.startWeightKg)]
        for index in plan.phases.indices {
            let end = Calendar.current.date(
                byAdding: .day,
                value: plan.phases.prefix(index + 1).reduce(0) { $0 + $1.durationWeeks } * 7,
                to: plan.startDate
            ) ?? plan.endDate
            points.append((end, plan.weight(atStartOfPhaseAt: index + 1)))
        }
        return points.map { (date: $0.0, weightKg: $0.1) }
    }

    private var bounds: ClosedRange<Double> {
        let values = actual.map(\.weightKg) + planned.map(\.weightKg)
        let low = (values.min() ?? plan.startWeightKg) - 1
        let high = (values.max() ?? plan.startWeightKg) + 1
        return low...high
    }

    private let planSeries = String(localized: "План")
    private let actualSeries = String(localized: "Факт")

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Chart {
                ForEach(planned, id: \.date) { point in
                    LineMark(
                        x: .value("Дата", point.date),
                        y: .value("Вес", point.weightKg),
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
