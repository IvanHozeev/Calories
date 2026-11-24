import SwiftUI

/// Знак приложения: незамкнутое кольцо из трёх дуг — углеводы, жиры, белки.
///
/// Тот же, что на иконке и лаунч-скрине (Tools/brand_assets.swift): доли дуг
/// как у типичной сушки, разрыв повёрнут на 40° против часовой, плоские дуги
/// цветами кольца «Сегодня». Толщина — как на лаунч-скрине: 90 единиц при
/// внешнем радиусе 372, зазоры считаются от толщины так же, как там. Иначе
/// заставка, которая продолжает лаунч-скрин, на первом кадре бы от него отличалась.
///
/// С `animated` знак живёт по кругу: дуги заполняются, знак прокручивается,
/// дуги убегают за хвостом — и снова. Конец цикла совпадает с началом
/// (пустое кольцо, поворот на полный оборот), поэтому шов не виден.
struct BrandMark: View {
    var animated = false

    /// Углеводы, жиры, белки — граммы типичной сушки на 80 кг.
    private static let grams: [Double] = [250, 64, 160]
    /// Цвета дуг кольца «Сегодня» — те же, что на иконке.
    private static let colors: [[Color]] = [ProgressRing.carbColors, ProgressRing.fatColors, ProgressRing.proteinColors]
    private static let rotation: Double = 40
    /// Толщина к внешнему радиусу — как на лаунч-скрине, а тот повторяет
    /// иконку. Плотнее прежнего: тонкий знак рядом с плотной иконкой читался
    /// как другой.
    private static let widthToOuterRadius: Double = 105.0 / 372.0

    private struct Arc: Identifiable {
        let id: Int
        let start: Double
        let end: Double
    }

    /// Дуги по часовой от нижнего конца «С» к верхнему. Углы — от 12 часов.
    /// `radiusInWidths` — радиус середины дуги в толщинах дуги.
    private static func arcs(radiusInWidths: Double) -> [Arc] {
        // Зазор от толщины: скруглённые концы толстой дуги съедают фиксированный зазор.
        let gap = 1.25 / radiusInWidths * 180 / .pi
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
        // Внешний край дуги — по краю рамки, как на лаунч-скрине.
        let inset = lineWidth / 2
        let radius = side / 2 - inset
        let arcs = Self.arcs(radiusInWidths: radius / lineWidth)
        return ZStack {
            ForEach(arcs) { arc in
                CircleArc(start: arc.start, end: arc.end)
                    .trim(from: from, to: to)
                    .stroke(Self.gradient(for: arc, radius: radius, lineWidth: lineWidth, inset: inset, side: side),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            }
        }
        .padding(inset)
    }

    /// Градиент по диагонали в границах самой дуги, как на иконке.
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

/// Резиновый знак — тот же, что на иконке: готовая картинка (`Tools/IconRender`) со
/// светлой и тёмной версией. Объём и тень нарисованы заранее, а не слоями на экране.
///
/// Картинка шире самого кольца: вокруг него поле под толщину и тень. Поэтому размер
/// задаётся по кольцу (`ring`), а не по картинке — так он стоит там же, где стоял плоский
/// знак, и лаунч-скрин, нарисованный по тем же числам, совпадает с ним до точки.
struct RubberSign: View {
    /// Кольцо занимает столько от ширины картинки (внешний радиус 380 из 512).
    /// Второй экземпляр числа — `ringShare` в `Tools/IconRender/launch_logo.swift`.
    static let ringShare: CGFloat = 0.7431

    /// Поперечник кольца от края до края, в пунктах.
    let ring: CGFloat

    var body: some View {
        // Рамка — по кольцу, картинка выходит за неё полем: раскладка видит знак
        // того же размера, что и прежний, а тень и объём лежат за рамкой.
        Color.clear
            .frame(width: ring, height: ring)
            .overlay {
                Image("RubberMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: ring / Self.ringShare, height: ring / Self.ringShare)
            }
            .accessibilityHidden(true)
    }
}

/// Резиновое кольцо, нарисованное вживую, — чтобы его можно было крутить по-настоящему.
///
/// Картинку (`RubberSign`) провернуть нельзя: свет сверху слева и тень снизу справа
/// нарисованы в ней, и вместе с ней они поехали бы по кругу — вышла бы вращающаяся
/// наклейка. У настоящего предмета на оси свет стоит на месте, а едет сам предмет. Здесь
/// так же: дуги движутся по кольцу, а сдвиг толщины, тень и блики остаются там, где
/// были — свет и взгляд не вращаются.
///
/// Геометрия и цвета — те же, что у картинки (`Tools/IconRender/rubber.html`, дуги
/// `Ring.svg` в масштабе 1.02): на нуле градусов кольцо совпадает с ней, и заставка
/// продолжает лаунч-скрин. Рисуется в клетке 1024 на 1024, как картинка, и размер
/// задаётся по кольцу.
struct RubberRing: View, Animatable {
    /// Поворот дуг по часовой, в градусах.
    var turn: Double
    let ring: CGFloat
    let dark: Bool

    var animatableData: Double {
        get { turn }
        set { turn = newValue }
    }

    private struct Piece {
        let start: Double, end: Double
        let colour: Color
    }

    /// Углы дуг от трёх часов по часовой — из `Ring.svg`; цвета иконки.
    private static let pieces: [Piece] = [
        Piece(start: 150, end: 290, colour: Color(.sRGB, red: 178 / 255, green: 109 / 255, blue: 1)),                 // углеводы
        Piece(start: -15, end: 82, colour: Color(.sRGB, red: 6 / 255, green: 188 / 255, blue: 220 / 255)),             // белки
        Piece(start: 90, end: 142, colour: Color(.sRGB, red: 1, green: 127 / 255, blue: 66 / 255)),                    // жиры
    ]

    var body: some View {
        let side = ring / RubberSign.ringShare
        Color.clear
            .frame(width: ring, height: ring)
            .overlay {
                Canvas { context, size in
                    draw(&context, size: size)
                }
                .frame(width: side, height: side)
            }
            .accessibilityHidden(true)
    }

    /// Тонкий объём — тот же рецепт, что у картинки знака (`Tools/IconRender/rubber.html`),
    /// у кольца дня (`RubberArcs`) и у полосок макросов (`RubberCapsule`): почти ровный
    /// цвет, блик по верху, четыре копии толщины, короткая мягкая тень. Числа — в единицах
    /// картинки 1024.
    private func draw(_ context: inout GraphicsContext, size: CGSize) {
        let u = size.width / 1024
        let scale = 1.02
        let centre = CGPoint(x: 512 * u, y: 512 * u)
        let radius = 312 * scale * u
        let width = 122 * scale * u
        let style = StrokeStyle(lineWidth: width, lineCap: .round)

        func path(_ piece: Piece, dx: CGFloat = 0, dy: CGFloat = 0) -> Path {
            Path { p in
                p.addArc(center: CGPoint(x: centre.x + dx, y: centre.y + dy), radius: radius,
                         startAngle: .degrees(piece.start + turn), endAngle: .degrees(piece.end + turn),
                         clockwise: false)
            }
        }

        // Тень под знаком: короткая и мягкая.
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 20 * u))
            let shadow = dark ? Color.black.opacity(0.7) : Color(red: 70 / 255, green: 55 / 255, blue: 40 / 255).opacity(0.42)
            for piece in Self.pieces {
                layer.stroke(path(piece, dx: 5 * u, dy: 15 * u), with: .color(shadow), style: style)
            }
        }

        // Толщина: четыре копии вправо-вниз, каждая темнее лица. Сдвиг не зависит от
        // поворота: взгляд на предмет не меняется.
        for k in stride(from: 4, through: 1, by: -1) {
            for piece in Self.pieces {
                context.stroke(path(piece, dx: CGFloat(k) * 1.49 * u, dy: CGFloat(k) * 2.73 * u),
                               with: .color(piece.colour.mix(with: .black, by: 0.30)), style: style)
            }
        }

        // Лицо дуги: почти ровный цвет, вертикальный переход привязан к экрану, а не к дуге.
        let shading = { (piece: Piece) in
            GraphicsContext.Shading.linearGradient(
                Gradient(stops: [.init(color: piece.colour.mix(with: .white, by: 0.12), location: 0),
                                 .init(color: piece.colour, location: 0.5),
                                 .init(color: piece.colour.mix(with: .black, by: 0.06), location: 1)]),
                startPoint: CGPoint(x: (512 - 130) * u, y: (512 - 330) * u),
                endPoint: CGPoint(x: (512 + 130) * u, y: (512 + 330) * u))
        }
        for piece in Self.pieces {
            let arc = path(piece)
            let outline = arc.strokedPath(style)
            context.stroke(arc, with: shading(piece), style: style)

            // Блик сверху и тень снизу внутри формы.
            let big = CGRect(x: -64 * u, y: -64 * u, width: 1152 * u, height: 1152 * u)
            context.drawLayer { layer in
                layer.clip(to: outline)
                layer.addFilter(.blur(radius: 6.2 * u))
                var inverse = Path()
                inverse.addRect(big)
                inverse.addPath(outline.offsetBy(dx: 0, dy: 6.8 * u))
                layer.fill(inverse, with: .color(.white.opacity(0.38)), style: FillStyle(eoFill: true))
            }
            context.drawLayer { layer in
                layer.clip(to: outline)
                layer.addFilter(.blur(radius: 8.7 * u))
                var inverse = Path()
                inverse.addRect(big)
                inverse.addPath(outline.offsetBy(dx: 0, dy: -8.7 * u))
                layer.fill(inverse, with: .color(.black.opacity(0.14)), style: FillStyle(eoFill: true))
            }
        }
    }
}

/// Резиновый знак, который медленно «дышит»: чуть растёт и оседает. Объём нарисован заранее,
/// поэтому двигается вся картинка целиком, как предмет на столе, а не слои по отдельности.
struct BreathingSign: View {
    @State private var inhaled = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        RubberSign(ring: 150)
            .scaleEffect(inhaled ? 1.04 : 1)
            .onAppear {
                // Без заставки не дышит: этот флаг выключает её у UI-тестов, а
                // бесконечная анимация не даёт приложению «успокоиться», и тест
                // ждёт каждый экран минутами.
                // Флаг из аргументов запуска приходит строкой «NO», а не булевым
                // значением, поэтому читаем его через `bool`, а не через `as? Bool`.
                let defaults = UserDefaults.standard
                let animates = defaults.object(forKey: "show_launch_splash") == nil
                    || defaults.bool(forKey: "show_launch_splash")
                guard !reduceMotion, animates else { return }
                withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { inhaled = true }
            }
    }
}

/// Продолжение лаунч-скрина: тот же фон и тот же знак на том же месте.
///
/// Размеры повторяют картинку лаунч-скрина (Tools/brand_assets.swift): знак
/// 150 pt по центру экрана без учёта безопасных зон. Иначе на стыке двух
/// экранов знак бы прыгал.
///
/// Не 230, как кольцо на «Сегодня»: там кольцо показывает съеденное за день и
/// занимать экран ему положено, а здесь это знак приложения, и на 57% ширины
/// он читался увеличенным индикатором загрузки.
///
/// Анимация одна и цельная, а не кусок бесконечного цикла: знак с
/// лаунч-скрина делает один плавный оборот, замирает полным и растворяется. Цикл
/// «убежали — заполнились» обрывался посередине, и экран появлялся
/// на полузаполненном кольце.
struct SplashView: View {
    /// Заставка начала уходить. Нужен отдельно от `onFinish`: кольцо дня
    /// должно вырасти вместе с её уходом, а не после него — иначе между
    /// двумя движениями видна пауза, и знак читается не продолженным, а
    /// подменённым.
    var onLeaving: () -> Void = {}
    var onFinish: () -> Void

    /// Поворот дуг, в градусах. Крутятся именно дуги (`RubberRing`), а не картинка:
    /// свет и тень стоят на месте, как у настоящего предмета на оси.
    @State private var turn: Double = 0
    @Environment(\.colorScheme) private var colorScheme
    @State private var dissolving = false

    /// Размер подписи в пунктах — как в `LaunchScreen.storyboard`.
    private static let footerWidth: CGFloat = 158.66666666666666
    private static let footerHeight: CGFloat = 50.333333333333336
    private static var safeBottom: CGFloat {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow)?.safeAreaInsets.bottom ?? 0
    }

    var body: some View {
        ZStack {
            Color("LaunchBackground")
                .opacity(dissolving ? 0 : 1)
            // Тот же состав, что на лаунч-скрине: кольцо по центру экрана и подпись
            // внизу. Первый кадр обязан быть его копией — иначе на запуске видно подмену.
            //
            // Движется только кольцо: подпись стоит на месте и растворяется вместе со знаком.
            RubberRing(turn: turn, ring: BrandLockup.markSize, dark: colorScheme == .dark)
                .scaleEffect(dissolving ? BrandLockup.exitScale : 1)
                .opacity(dissolving ? 0 : 1)
            // Подпись стоит там же, где в раскладке лаунч-скрина: на 24 pt выше нижней
            // безопасной зоны, по центру.
            Image("LaunchFooter")
                .resizable()
                .frame(width: Self.footerWidth, height: Self.footerHeight)
                .position(x: UIScreen.main.bounds.midX,
                          y: UIScreen.main.bounds.maxY - Self.safeBottom - 24 - Self.footerHeight / 2)
                .opacity(dissolving ? 0 : 1)
        }
        .ignoresSafeArea()
        .task {
            withAnimation(.timingCurve(0.45, 0, 0.2, 1, duration: 1.2)) {
                turn = 360
            } completion: {
                onLeaving()
                withAnimation(.easeOut(duration: BrandLockup.exitDuration)) {
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
