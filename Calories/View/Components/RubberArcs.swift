import SwiftUI

/// Объём дуги кольца в одних числах: большое кольцо дня, кольца недели и знак
/// на иконке рисуются одним рецептом — свет сверху слева, толщина из сдвинутых
/// копий, мягкая тень и затемнение внутри формы.
///
/// Числа в долях толщины дуги, поэтому кольцо любого диаметра остаётся тем же
/// предметом. Глубину задаёт вызывающий: у иконки копий одиннадцать, у кольца
/// в интерфейсе — четыре, потому что индикатор не должен тянуть экран на себя.
enum RubberArcRecipe {
    /// Сдвиг копии в долях толщины дуги: вправо и вниз, вниз сильнее.
    static let depthStep = CGSize(width: 0.012, height: 0.022)
    /// Сколько копий складывают толщину. Меньше — плоско, больше — предмет.
    static let depthCopies = 4

    /// Смещение, повёрнутое так, чтобы после поворота кольца на `turn` градусов
    /// оно смотрело в ту же сторону экрана.
    static func offset(_ dx: CGFloat, _ dy: CGFloat, compensating turn: Double) -> CGSize {
        let a = turn * .pi / 180
        return CGSize(width: dx * cos(a) - dy * sin(a), height: dx * sin(a) + dy * cos(a))
    }

    /// Рисует дуги с объёмом поверх уже нарисованных плоских дорожек.
    ///
    /// Порядок проходов важен и потому вынесен сюда: сначала тени всех дуг,
    /// потом толщина всех, и только потом лица. Иначе толщина соседней дуги
    /// ложилась бы поверх лица предыдущей на стыке сегментов.
    static func draw(_ context: inout GraphicsContext,
                     arcs: [(path: Path, colour: Color)],
                     lineWidth lw: CGFloat,
                     style: StrokeStyle,
                     field: CGRect,
                     centre: CGPoint,
                     radius: CGFloat,
                     dark: Bool,
                     shift: (CGFloat, CGFloat) -> CGSize) {
        guard !arcs.isEmpty else { return }

        // Тень: короткая и мягкая.
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: lw * 0.16))
            let colour = dark ? Color.black.opacity(0.55) : Color(red: 70 / 255, green: 55 / 255, blue: 40 / 255).opacity(0.28)
            for arc in arcs {
                let s = shift(lw * 0.04, lw * 0.12)
                layer.stroke(arc.path.offsetBy(dx: s.width, dy: s.height), with: .color(colour), style: style)
            }
        }

        // Толщина: копии, каждая на шаг дальше и темнее лица.
        for k in stride(from: depthCopies, through: 1, by: -1) {
            for arc in arcs {
                let s = shift(CGFloat(k) * lw * depthStep.width, CGFloat(k) * lw * depthStep.height)
                context.stroke(arc.path.offsetBy(dx: s.width, dy: s.height),
                               with: .color(arc.colour.mix(with: .black, by: 0.30)), style: style)
            }
        }

        // Лицо и свет внутри формы.
        let up = shift(0, lw * 0.055), down = shift(0, -lw * 0.07)
        for arc in arcs {
            let outline = arc.path.strokedPath(style)
            let shading = GraphicsContext.Shading.linearGradient(
                Gradient(stops: [.init(color: arc.colour.mix(with: .white, by: 0.12), location: 0),
                                 .init(color: arc.colour, location: 0.5),
                                 .init(color: arc.colour.mix(with: .black, by: 0.06), location: 1)]),
                startPoint: CGPoint(x: centre.x - radius * 0.4, y: centre.y - radius),
                endPoint: CGPoint(x: centre.x + radius * 0.4, y: centre.y + radius))
            context.stroke(arc.path, with: shading, style: style)

            context.drawLayer { layer in
                layer.clip(to: outline)
                layer.addFilter(.blur(radius: lw * 0.05))
                var inverse = Path(); inverse.addRect(field); inverse.addPath(outline.offsetBy(dx: up.width, dy: up.height))
                layer.fill(inverse, with: .color(.white.opacity(0.38)), style: FillStyle(eoFill: true))
            }
            context.drawLayer { layer in
                layer.clip(to: outline)
                layer.addFilter(.blur(radius: lw * 0.07))
                var inverse = Path(); inverse.addRect(field); inverse.addPath(outline.offsetBy(dx: down.width, dy: down.height))
                layer.fill(inverse, with: .color(.black.opacity(0.14)), style: FillStyle(eoFill: true))
            }
        }
    }
}

/// Дуги кольца дня с лёгким объёмом.
///
/// Тот же приём, что у знака на иконке и заставке (`RubberRing`): свет сверху слева,
/// толщина — копии дуги, сдвинутые вправо-вниз и потемнее, мягкая тень, блик сверху
/// и затемнение снизу внутри формы. Только очень тонко. С полной глубиной знака
/// (16 копий, длинная тень) кольцо тянуло экран на себя и спорило с плоскими
/// плитками под ним; с четырьмя копиями оно читается глянцевым, как стеклянные
/// карточки рядом, а не отдельным предметом.
///
/// Дорожка — плоская, как и была: пустая часть не должна выглядеть вещью. Цвет лица
/// почти ровный, без перехода от светлого к глубокому: у макроса один цвет на дуге,
/// на полоске под кольцом и в названии продукта.
///
/// Заливка анимируется, как у плоских дуг: доли отдаются системе как вектор чисел,
/// и пружина по `consumed` растит каждую дугу, а не перескакивает.
struct RubberArcs: View, Animatable {
    let segments: [ProgressRing.Segment]
    let lineWidth: CGFloat
    let trackOpacity: Double
    /// Насколько кольцо повёрнуто снаружи, в градусах по часовой. Свет и толщина
    /// должны смотреть вправо-вниз на экране, а не на кольце: смещение копий
    /// поворачивается на столько же в обратную сторону.
    let lightTurn: Double

    @Environment(\.colorScheme) private var scheme

    init(segments: [ProgressRing.Segment], lineWidth: CGFloat, trackOpacity: Double, lightTurn: Double) {
        self.segments = segments
        self.lineWidth = lineWidth
        self.trackOpacity = trackOpacity
        self.lightTurn = lightTurn
        let p = segments.map(\.progress) + [0, 0, 0]
        self.fill = AnimatablePair(p[0], AnimatablePair(p[1], p[2]))
    }

    /// Доли заливки трёх дуг — единственное, что меняется плавно. Дуг всегда три
    /// (углеводы, жиры, белки), поэтому хватает вложенной пары: вектор произвольной
    /// длины SwiftUI наружу не отдаёт.
    private var fill: AnimatablePair<Double, AnimatablePair<Double, Double>>

    var animatableData: AnimatablePair<Double, AnimatablePair<Double, Double>> {
        get { fill }
        set { fill = newValue }
    }

    private func progress(_ index: Int) -> Double {
        switch index {
        case 0: return fill.first
        case 1: return fill.second.first
        default: return fill.second.second
        }
    }

    /// Сдвиг копии, повёрнутый так, чтобы после поворота кольца на `lightTurn`
    /// градусов он смотрел в ту же сторону экрана.
    static func offset(_ dx: CGFloat, _ dy: CGFloat, compensating turn: Double) -> CGSize {
        RubberArcRecipe.offset(dx, dy, compensating: turn)
    }

    var body: some View {
        Canvas { context, size in
            draw(&context, size: size)
        }
        // Поле под толщину и тень: Canvas обрезает всё, что выходит за рамку. Рамка
        // кольца при этом остаётся прежней — поле добавляется и тут же снимается.
        .padding(-lineWidth)
        .padding(lineWidth / 2)
        .accessibilityHidden(true)
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize) {
        let lw = lineWidth
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = (min(size.width, size.height) - 2 * lw) / 2
        let style = StrokeStyle(lineWidth: lw, lineCap: .round)
        let dark = scheme == .dark

        func end(_ index: Int) -> Double {
            let s = segments[index]
            let p = progress(index)
            return s.start + (s.end - s.start) * p
        }
        func path(_ index: Int, to end: Double) -> Path {
            Path { p in
                p.addArc(center: centre, radius: radius,
                         startAngle: .degrees(segments[index].start - 90), endAngle: .degrees(end - 90),
                         clockwise: false)
            }
        }
        func shift(_ dx: CGFloat, _ dy: CGFloat) -> CGSize { Self.offset(dx, dy, compensating: lightTurn) }

        // Дорожки — плоские.
        for index in segments.indices {
            context.stroke(path(index, to: segments[index].end),
                           with: .color(segments[index].colors[0].opacity(trackOpacity)), style: style)
        }

        // Скруглённый конец у нулевой длины даёт точку — такие дуги не рисуем.
        let drawn = segments.indices.filter { progress($0) > 0.0001 }
        guard !drawn.isEmpty else { return }

        let field = CGRect(x: -lw * 4, y: -lw * 4, width: size.width + lw * 8, height: size.height + lw * 8)
        RubberArcRecipe.draw(&context,
                             arcs: drawn.map { (path: path($0, to: end($0)), colour: segments[$0].colors[0]) },
                             lineWidth: lw, style: style, field: field,
                             centre: centre, radius: radius, dark: dark, shift: shift)
    }
}
