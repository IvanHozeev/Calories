import SwiftUI
import Charts

/// Одно место лентой во времени.
///
/// На экране замеров до сих пор был только столбик «изменение против прошлого
/// раза». Он отвечает, стало больше или меньше, но молчит о том, куда это
/// идёт: талия, которая третий месяц качается в пределах сантиметра, и талия,
/// которая медленно уходит, в этом столбике выглядят одинаково.
///
/// Линия честна с третьего сеанса, не раньше: на двух точках она проводится
/// через что угодно, а мерят лентой раз в неделю-две.
struct MeasurementChart: View {
    struct Point: Identifiable {
        let date: Date
        let value: Double
        var id: Date { date }
    }

    /// Сколько сеансов нужно, чтобы линию вообще рисовать.
    static let minimumSessions = 3

    let points: [Point]

    private var low: Double { (points.map(\.value).min() ?? 0) - 1 }
    private var high: Double { (points.map(\.value).max() ?? 0) + 1 }

    var body: some View {
        Chart {
            ForEach(points) { point in
                LineMark(
                    x: .value("Дата", point.date),
                    y: .value("Обхват", point.value)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(.blue)
                .lineStyle(StrokeStyle(lineWidth: 2.5))
                PointMark(
                    x: .value("Дата", point.date),
                    y: .value("Обхват", point.value)
                )
                .foregroundStyle(.blue)
                .symbolSize(28)
            }
        }
        .chartYScale(domain: low...high)
        // Не по дням: между сеансами одна-две недели, и ось, размеченная
        // сутками, превращается в частокол без подписей.
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.day().month(.defaultDigits))
            }
        }
        .frame(height: 160)
    }
}
