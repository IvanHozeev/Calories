import SwiftUI
import Charts

extension View {
    /// Ось дней у графика: у недели — буквы дней, у месяца и трёх — даты через шаг.
    ///
    /// Шаг такой, чтобы подписей оставалось пять-шесть при любой длине диапазона:
    /// на тридцати днях подписи каждого дня наезжают друг на друга и ось
    /// перестаёт читаться. Правило было скопировано в график калорий и в график
    /// веса — и меняться должно сразу в обоих, потому что это одна и та же ось
    /// на двух экранах.
    func dayAxis(points: Int) -> some View {
        chartXAxis {
            if points <= 7 {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: true)
                }
            } else {
                AxisMarks(values: .stride(by: .day, count: max(1, points / 6))) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.day().month(.defaultDigits))
                }
            }
        }
    }
}
