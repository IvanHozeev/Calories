import SwiftUI

/// Знак приложения: незамкнутое кольцо из трёх дуг — углеводы, жиры, белки.
///
/// Тот же, что на иконке и лаунч-скрине (Tools/brand_assets.swift): доли дуг
/// как у типичной сушки, разрыв повёрнут на 40° против часовой. Нарисован как
/// кольцо на «Сегодня» — тонкие дуги, мягкие цвета, лёгкое свечение, — чтобы
/// лаунч-скрин, этот знак и кольцо читались одной вещью.
///
/// С `animated` знак живёт по кругу: дуги заполняются, знак прокручивается,
/// дуги убегают за хвостом — и снова. Конец цикла совпадает с началом
/// (пустое кольцо, поворот на полный оборот), поэтому шов не виден.
struct BrandMark: View {
    var animated = false

    /// Углеводы, жиры, белки — граммы типичной сушки на 80 кг.
    private static let grams: [Double] = [250, 64, 160]
    private static let colors: [[Color]] = [
        [Color(.displayP3, red: 0.72, green: 0.36, blue: 1), Color(.displayP3, red: 0.65, green: 0.23, blue: 1)],
        [Color(.displayP3, red: 1, green: 0.64, blue: 0.24), Color(.displayP3, red: 1, green: 0.54, blue: 0.12)],
        [Color(.displayP3, red: 0.30, green: 0.61, blue: 1), Color(.displayP3, red: 0.18, green: 0.48, blue: 1)],
    ]
    private static let rotation: Double = 40
    private static let opening: Double = 60
    private static let gap: Double = 16

    private struct Arc: Identifiable {
        let id: Int
        let start: Double
        let end: Double
    }

    /// Дуги по часовой от нижнего конца «С» к верхнему. Углы — от 12 часов.
    private static let arcs: [Arc] = {
        let top = 90 - rotation - opening / 2
        let available = 360 - opening - gap * Double(grams.count - 1)
        let total = grams.reduce(0, +)
        var cursor = top
        return grams.enumerated().map { index, value in
            let end = cursor
            let start = end - available * value / total
            cursor = start - gap
            return Arc(id: index, start: start, end: end)
        }
    }()

    /// Начинается с полного знака — таким он стоит на лаунч-скрине, и первый
    /// кадр анимации совпадает с ним. Дальше дуги убегают за хвостом с полным
    /// оборотом, пустое кольцо незаметно возвращается в исходный поворот и
    /// заполняется снова.
    private enum Phase: CaseIterable {
        case filled, drained, empty
        var trimFrom: Double { self == .drained ? 1 : 0 }
        var trimTo: Double { self == .empty ? 0 : 1 }
        var turn: Double { self == .drained ? 360 : 0 }
    }

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let lineWidth = side * 18 / 230
            if animated {
                PhaseAnimator(Phase.allCases) { phase in
                    mark(lineWidth: lineWidth, from: phase.trimFrom, to: phase.trimTo)
                        .rotationEffect(.degrees(phase.turn))
                } animation: { phase in
                    // Кривые мягкие с обоих концов: резкий старт после пустого
                    // кольца и резкая остановка на полном читались как рывок.
                    switch phase {
                    case .empty:   return nil
                    case .filled:  return .timingCurve(0.45, 0, 0.2, 1, duration: 1.05)
                    case .drained: return .timingCurve(0.55, 0, 0.35, 1, duration: 1.25)
                    }
                }
            } else {
                mark(lineWidth: lineWidth, from: 0, to: 1)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private func mark(lineWidth: CGFloat, from: Double, to: Double) -> some View {
        ZStack {
            ForEach(Self.arcs) { arc in
                MarkArc(start: arc.start, end: arc.end)
                    .trim(from: from, to: to)
                    .stroke(LinearGradient(colors: Self.colors[arc.id], startPoint: .top, endPoint: .bottom),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .shadow(color: Self.colors[arc.id][1].opacity(0.25), radius: lineWidth * 0.35)
            }
        }
        .padding(lineWidth / 2)
    }
}

private struct MarkArc: Shape {
    let start: Double
    let end: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(center: CGPoint(x: rect.midX, y: rect.midY),
                    radius: min(rect.width, rect.height) / 2,
                    startAngle: .degrees(start - 90), endAngle: .degrees(end - 90), clockwise: false)
        return path
    }
}

/// Продолжение лаунч-скрина: тот же фон и тот же знак на том же месте.
///
/// Размеры повторяют картинку лаунч-скрина (Tools/brand_assets.swift): знак
/// 230 pt — как кольцо на «Сегодня» — по центру экрана без учёта безопасных
/// зон. Иначе на стыке двух экранов знак бы прыгал.
struct SplashView: View {
    var body: some View {
        ZStack {
            Color("LaunchBackground")
            BrandMark(animated: true)
                .frame(width: 230, height: 230)
        }
        .ignoresSafeArea()
    }
}

#Preview {
    VStack(spacing: 40) {
        BrandMark().frame(width: 150)
        BrandMark(animated: true).frame(width: 150)
    }
}
