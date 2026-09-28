import SwiftUI

/// Дуга окружности: углы в градусах от 12 часов по часовой стрелке.
///
/// Одна на всё приложение и виджеты. Копий было три — у кольца, у знака «С» и
/// в виджете, — и все три считали одно и то же: центр рамки, радиус по меньшей
/// стороне, поворот на четверть оборота, чтобы ноль оказался наверху. Папка
/// `Shared` входит в оба таргета, поэтому держать копии больше незачем.
struct CircleArc: Shape {
    let start: Double
    let end: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(center: CGPoint(x: rect.midX, y: rect.midY),
                    radius: min(rect.width, rect.height) / 2,
                    startAngle: .degrees(start - 90),
                    endAngle: .degrees(end - 90),
                    clockwise: false)
        return path
    }

    /// Точка на окружности в долях рамки — для градиента вдоль дуги.
    static func point(at degrees: Double) -> UnitPoint {
        let radians = degrees * .pi / 180
        return UnitPoint(x: 0.5 + 0.5 * sin(radians), y: 0.5 - 0.5 * cos(radians))
    }
}
