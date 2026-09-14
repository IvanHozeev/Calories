import SwiftUI

/// Знак приложения: незамкнутое кольцо из трёх дуг — углеводы, жиры, белки.
///
/// Тот же, что на иконке и лаунч-скрине (Tools/brand_assets.swift): доли дуг
/// как у типичной сушки, разрыв повёрнут на 40° против часовой, эмаль с
/// градиентом от света сверху-слева. Толщина — как на лаунч-скрине: 100 единиц
/// при внешнем радиусе 385, зазоры считаются от толщины так же, как там. Иначе
/// заставка, которая продолжает лаунч-скрин, на первом кадре бы от него отличалась.
///
/// С `animated` знак живёт по кругу: дуги заполняются, знак прокручивается,
/// дуги убегают за хвостом — и снова. Конец цикла совпадает с началом
/// (пустое кольцо, поворот на полный оборот), поэтому шов не виден.
struct BrandMark: View {
    var animated = false
    /// Дуги в канавках, как на иконке и лаунч-скрине: для тёмного фона.
    var engraved = false

    /// Углеводы, жиры, белки — граммы типичной сушки на 80 кг.
    private static let grams: [Double] = [250, 64, 160]
    /// Светлая и глубокая сторона эмали — те же, что на иконке.
    private static let colors: [[Color]] = [
        [Color(hex: 0xDA8CFF), Color(hex: 0x8318DC)],
        [Color(hex: 0xFFC23A), Color(hex: 0xEE5C00)],
        [Color(hex: 0x6EC6FF), Color(hex: 0x0A52DA)],
    ]
    private static let rotation: Double = 40
    /// Толщина к внешнему радиусу — как на лаунч-скрине.
    private static let widthToOuterRadius: Double = 100.0 / 385.0

    private struct Arc: Identifiable {
        let id: Int
        let start: Double
        let end: Double
    }

    /// Дуги по часовой от нижнего конца «С» к верхнему. Углы — от 12 часов.
    /// `radiusInWidths` — радиус середины дуги в толщинах дуги.
    private static func arcs(radiusInWidths: Double) -> [Arc] {
        // Зазор от толщины: скруглённые концы толстой дуги съедают фиксированный зазор.
        let gap = (1.13 + 0.12) / radiusInWidths * 180 / .pi
        let opening = max(72, gap * 1.9)
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
    }

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
            let lineWidth = side / 2 * Self.widthToOuterRadius
            if animated {
                PhaseAnimator(Phase.allCases) { phase in
                    mark(side: side, lineWidth: lineWidth, from: phase.trimFrom, to: phase.trimTo)
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
                mark(side: side, lineWidth: lineWidth, from: 0, to: 1)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private func mark(side: CGFloat, lineWidth: CGFloat, from: Double, to: Double) -> some View {
        // Внешний край прорези — по краю рамки, как на лаунч-скрине.
        let inset = lineWidth * 0.565
        let radius = side / 2 - inset
        let arcs = Self.arcs(radiusInWidths: radius / lineWidth)
        return ZStack {
            ForEach(arcs) { arc in
                if engraved {
                    MarkArc(start: arc.start, end: arc.end)
                        .stroke(.channel(thickness: lineWidth * 1.13),
                                style: StrokeStyle(lineWidth: lineWidth * 1.13, lineCap: .round))
                }
                MarkArc(start: arc.start, end: arc.end)
                    .trim(from: from, to: to)
                    .stroke(Self.gradient(for: arc, radius: radius, lineWidth: lineWidth, inset: inset, side: side),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .shadow(color: Self.colors[arc.id][1].opacity(0.45), radius: lineWidth * 0.17)
            }
        }
        .padding(inset)
    }

    /// Градиент от света сверху-слева в границах самой дуги, как на иконке.
    private static func gradient(for arc: Arc, radius: CGFloat, lineWidth: CGFloat, inset: CGFloat, side: CGFloat) -> LinearGradient {
        var minX = CGFloat.infinity, minY = CGFloat.infinity, maxX = -CGFloat.infinity, maxY = -CGFloat.infinity
        let steps = 24
        for k in 0...steps {
            let degrees = arc.start + (arc.end - arc.start) * Double(k) / Double(steps)
            let radians = degrees * .pi / 180
            // Координаты в рамке дуги (без отступа), y вниз.
            let x = radius + radius * CGFloat(sin(radians))
            let y = radius - radius * CGFloat(cos(radians))
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        }
        let span = radius * 2
        let pad = lineWidth / 2
        return LinearGradient(colors: colors[arc.id],
                              startPoint: UnitPoint(x: (minX - pad) / span, y: (minY - pad) / span),
                              endPoint: UnitPoint(x: (maxX + pad) / span, y: (maxY + pad) / span))
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
///
/// Анимация одна и цельная, а не кусок бесконечного цикла: знак с
/// лаунч-скрина делает один плавный оборот, замирает полным и растворяется.
/// Цикл «убежали — заполнились» обрывался посередине, и экран появлялся
/// на полузаполненном кольце.
struct SplashView: View {
    var onFinish: () -> Void

    @State private var turn: Double = 0
    @State private var dissolving = false

    var body: some View {
        ZStack {
            Color("LaunchBackground")
                .opacity(dissolving ? 0 : 1)
            BrandMark(engraved: true)
                .frame(width: 230, height: 230)
                .rotationEffect(.degrees(turn))
                .scaleEffect(dissolving ? 1.12 : 1)
                .opacity(dissolving ? 0 : 1)
        }
        .ignoresSafeArea()
        // Графит тёмный в любой теме телефона — и канавка должна быть тёмной.
        .environment(\.colorScheme, .dark)
        .task {
            withAnimation(.timingCurve(0.45, 0, 0.2, 1, duration: 1.2)) {
                turn = 360
            } completion: {
                withAnimation(.easeOut(duration: 0.35)) {
                    dissolving = true
                } completion: {
                    onFinish()
                }
            }
        }
    }
}

#Preview {
    VStack(spacing: 40) {
        BrandMark().frame(width: 150)
        BrandMark(animated: true).frame(width: 150)
    }
}
