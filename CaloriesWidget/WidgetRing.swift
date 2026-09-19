import SwiftUI
import WidgetKit

/// Кольцо «Сегодня» и знак «С» для виджетов.
///
/// Копия по устройству, а не общий код: папки проекта синхронизированы с файловой
/// системой, и файл приложения в таргет виджета не попадает. Если правишь кольцо в
/// `ProgressRing` или знак в `BrandMark`, загляни и сюда — доли, поворот и цвета
/// должны совпадать, иначе виджет перестанет узнаваться как то же кольцо.
enum WidgetPalette {
    static let kcal = [Color(hex: 0x3FD673), Color(hex: 0x21C45A)]
    static let protein = [Color(hex: 0x4C9BFF), Color(hex: 0x2F7BFF)]
    static let fat = [Color(hex: 0xFFA23D), Color(hex: 0xFF8A1F)]
    static let carbs = [Color(hex: 0xB85CFF), Color(hex: 0xA63BFF)]
    /// Шаги красятся цветом акцента из настроек приложения: у этого кольца
    /// цвет ничего не означает, и пусть он будет тем, который человек выбрал.
    /// Приложение кладёт выбор в общие настройки группы.
    static var steps: [Color] {
        switch UserDefaults(suiteName: "group.calories.shared")?.string(forKey: "widget_accent") {
        case "kcal":    return kcal
        case "protein": return protein
        case "fat":     return fat
        case "carbs":   return carbs
        default:        return [Color(hex: 0x5AC8FF), Color(hex: 0x2F7BFF)]
        }
    }

    /// Поле виджета — как у иконки: белое, чуть сереющее книзу, а в тёмной
    /// теме почти чёрное. Графит под «С» в чёрном стекле ушёл вместе с ней:
    /// рядом со светлой иконкой тёмный виджет выглядел чужим.
    static var surface: LinearGradient {
        LinearGradient(colors: [dynamic(light: 0xFFFFFF, dark: 0x1C1C1F),
                                dynamic(light: 0xF1F3F7, dark: 0x0A0A0B)],
                       startPoint: .top, endPoint: .bottom)
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(Color(hex: traits.userInterfaceStyle == .dark ? dark : light))
        })
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.displayP3,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// Одна дуга: где лежит, насколько залита и каким цветом.
struct WidgetRingSegment: Identifiable {
    let id: String
    let start: Double
    let end: Double
    let progress: Double
    let colors: [Color]
}

enum WidgetRingLayout {
    private static func ratio(_ value: Double, _ target: Double) -> Double {
        target > 0 ? min(max(value / target, 0), 1) : 0
    }

    /// Доли макросов по граммам целей. Совсем крошечной дуге пропасть не даём.
    private static func shares(_ targets: [Double]) -> [Double] {
        let total = targets.reduce(0, +)
        let raw = total > 0 ? targets.map { $0 / total } : Array(repeating: 1.0 / Double(targets.count), count: targets.count)
        let floored = raw.map { max($0, 0.08) }
        let sum = floored.reduce(0, +)
        return floored.map { $0 / sum }
    }

    /// Кольцо «Сегодня»: калории на правой половине, макросы делят левую.
    /// Поворот на −40° делается снаружи, как в приложении.
    static func today(consumed: Int, goal: Int,
                      protein: Double, fat: Double, carbs: Double,
                      proteinTarget: Double, fatTarget: Double, carbsTarget: Double) -> [WidgetRingSegment] {
        let gap = 11.0
        let calorieProgress = goal > 0 ? min(Double(consumed) / Double(goal), 1) : 0
        var result = [WidgetRingSegment(id: "kcal", start: gap / 2, end: 180 - gap / 2, progress: calorieProgress,
                                        colors: consumed > goal ? [.orange, .red] : WidgetPalette.kcal)]
        let parts: [(String, Double, [Color])] = [
            ("protein", ratio(protein, proteinTarget), WidgetPalette.protein),
            ("fat", ratio(fat, fatTarget), WidgetPalette.fat),
            ("carbs", ratio(carbs, carbsTarget), WidgetPalette.carbs),
        ]
        let split = shares([proteinTarget, fatTarget, carbsTarget])
        var cursor = 180.0
        for (index, part) in parts.enumerated() {
            let span = 180 * split[index]
            result.append(WidgetRingSegment(id: part.0, start: cursor + gap / 2, end: cursor + span - gap / 2,
                                            progress: part.1, colors: part.2))
            cursor += span
        }
        return result
    }

    /// Знак «С»: только макросы, разрыв повёрнут на 40° против часовой — как на
    /// иконке. Сверху вниз против часовой: углеводы, жиры, белки.
    static func mark(protein: Double, fat: Double, carbs: Double,
                     proteinTarget: Double, fatTarget: Double, carbsTarget: Double) -> [WidgetRingSegment] {
        let opening = 60.0, gap = 16.0, rotation = 40.0
        let split = shares([carbsTarget, fatTarget, proteinTarget])
        let parts: [(String, Double, [Color])] = [
            ("carbs", ratio(carbs, carbsTarget), WidgetPalette.carbs),
            ("fat", ratio(fat, fatTarget), WidgetPalette.fat),
            ("protein", ratio(protein, proteinTarget), WidgetPalette.protein),
        ]
        let available = 360 - opening - gap * Double(parts.count - 1)
        var cursor = 90 - rotation - opening / 2
        return parts.enumerated().map { index, part in
            let end = cursor
            let start = end - available * split[index]
            cursor = start - gap
            // Заливка идёт от верхнего конца «С» вниз — как читают букву.
            return WidgetRingSegment(id: part.0, start: start, end: end, progress: part.1, colors: part.2)
        }
    }
}

/// Дуги в канавках. Цвет — только в полноцветном режиме: на тонированном
/// экране и на блокировке система перекрашивает всё по яркости, и там дуги
/// рисуются одним цветом, заливка — ярко, пустая часть — тускло.
struct WidgetRing: View {
    let segments: [WidgetRingSegment]
    var lineWidth: CGFloat
    var rotation: Double = 0
    /// Заливка идёт от конца дуги к началу — для «С», которую читают сверху.
    var fillsFromEnd = false
    @Environment(\.widgetRenderingMode) private var renderingMode

    /// Градиент вдоль дуги. У почти замкнутого кольца начало и конец дуги в
    /// одной точке, и такой градиент вырождается в резкий шов — там он идёт
    /// по диагонали.
    private func gradient(for segment: WidgetRingSegment) -> LinearGradient {
        if segment.end - segment.start > 300 {
            return LinearGradient(colors: segment.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        return LinearGradient(colors: segment.colors,
                              startPoint: WidgetArc.point(at: segment.start),
                              endPoint: WidgetArc.point(at: segment.end))
    }

    var body: some View {
        ZStack {
            ForEach(segments) { segment in
                // Дорожка цветом дуги, приглушённым, — как кольцо в приложении.
                // На тонированном экране цвета нет, там дорожка просто тусклая.
                WidgetArc(start: segment.start, end: segment.end)
                    .stroke(renderingMode == .fullColor ? segment.colors[0].opacity(0.2) : Color.white.opacity(0.25),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                if segment.progress > 0 {
                    let span = (segment.end - segment.start) * segment.progress
                    let arc = fillsFromEnd
                        ? WidgetArc(start: segment.end - span, end: segment.end)
                        : WidgetArc(start: segment.start, end: segment.start + span)
                    if renderingMode == .fullColor {
                        arc.stroke(gradient(for: segment),
                                   style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    } else {
                        arc.stroke(Color.white, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                            .widgetAccentable()
                    }
                }
            }
        }
        .padding(lineWidth / 2)
        .rotationEffect(.degrees(rotation))
    }
}

/// Дуга: углы в градусах от 12 часов по часовой стрелке.
struct WidgetArc: Shape {
    let start: Double
    let end: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(center: CGPoint(x: rect.midX, y: rect.midY),
                    radius: min(rect.width, rect.height) / 2,
                    startAngle: .degrees(start - 90), endAngle: .degrees(end - 90), clockwise: false)
        return path
    }

    /// Точка на окружности в долях рамки — для градиента вдоль дуги.
    static func point(at degrees: Double) -> UnitPoint {
        let radians = degrees * .pi / 180
        return UnitPoint(x: 0.5 + 0.5 * sin(radians), y: 0.5 - 0.5 * cos(radians))
    }
}
