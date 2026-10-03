import SwiftUI
import AudioToolbox

struct RingView<Label: View>: View {
    let progress: Double
    let colors: [Color]
    let labelID: AnyHashable
    /// Растёт с каждым обновлением — кольцо делает оборот вместо спиннера.
    var spinTicket: Int = 0
    /// Насколько кольцо повернули, потянув список вниз, в градусах.
    var pullAngle: Double = 0
    @ViewBuilder let label: () -> Label

    /// Толщина кольца одной константой: трек, дуга и её отступ обязаны совпадать,
    /// а раньше это было три числа в разных местах, которые легко разъезжались.
    private let lineWidth: CGFloat = 9

    /// Дорожка цветом кольца, приглушённым, — как у кольца «Сегодня» и полосок.
    private var channel: some View {
        Circle()
            .inset(by: lineWidth / 2)
            .stroke((colors.first ?? .secondary).opacity(0.18), style: StrokeStyle(lineWidth: lineWidth))
    }

    /// Заливка вровень с дорожкой, без свечения.
    private var filling: some View {
        Circle()
            .inset(by: lineWidth / 2)
            .trim(from: 0, to: progress)
            .stroke(
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
            .rotationEffect(.degrees(-90))
            .animation(.spring(response: 0.65, dampingFraction: 0.85), value: progress)
    }

    var body: some View {
        ZStack {
            ZStack {
                channel
                filling
            }
            .compositingGroup()
            .modifier(RefreshSpin(baseRotation: 0, pullAngle: pullAngle, spinTicket: spinTicket))
            label()
                .id(labelID)
                .transition(.opacity.combined(with: .scale(scale: 0.85)))
        }
        .frame(width: 220, height: 220)
        // Кольцо — фиксированные 220pt, текст внутри масштабировать некуда.
        // Ограничиваем шкалу, иначе на крупных размерах цифры вылезают за круг.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }
}

/// Кольцо дня — это знак приложения, собранный из макросов.
///
/// Три дуги: углеводы, жиры, белки. Длина каждой — её норма в граммах, заливка
/// — сколько уже съедено, поэтому у типичной сушки самая длинная дуга
/// углеводная, а самая короткая жировая. Разрыв и порядок дуг те же, что на
/// иконке и лаунч-скрине: это один и тот же знак, а не похожий.
///
/// Калорийной дуги здесь нет намеренно. Она занимала половину круга и говорила
/// ровно то же, что крупное число в центре, — а остальное кольцо приходилось
/// делить на оставшуюся половину, и знак переставал быть знаком. Калории
/// остались числом, которое и так читают первым.
///
/// Нажатие открывает добавление приёма пищи. Еду записывают по нескольку раз
/// в день, а на план смотрят раз в неделю: самая крупная мишень экрана должна
/// обслуживать частое действие. Меню со сканером и камерой живёт на плюсе.
struct ProgressRing: View {
    let consumed: Int
    let goal: Int
    var macros: Macros = .zero
    var proteinTarget: Double? = nil
    var fatTarget: Double? = nil
    var carbsTarget: Double? = nil
    /// Растёт с каждым обновлением «Сегодня» — кольцо делает оборот, как знак
    /// на запуске. Счётчик, а не флаг: два обновления подряд должны дать два оборота.
    var spinTicket: Int = 0
    /// Насколько кольцо уже повернули, потянув список вниз, в градусах.
    /// Пока тянут, оно идёт за пальцем — вместо системного спиннера.
    var pullAngle: Double = 0
    /// Показ нормы, а не дня: все дуги полные, в центре дневная норма. Для
    /// онбординга — там съеденного ещё нет, а пустое кольцо не показывает,
    /// на что делится день.
    var showsTargets = false
    /// Что делать по нажатию — записать еду.
    let onOpen: () -> Void

    /// Поворот как у знака на иконке: разрыв уходит на ту же диагональ,
    /// между часом и двумя, и кольцо узнаётся как тот же знак.
    private static let rotation: Double = -40

    /// Верхний конец «С» в неповёрнутой рамке. После поворота на -40° он
    /// встаёт туда же, где у знака, — на 14° от двенадцати часов.
    private static let topEnd: Double = 54
    /// Разрыв знака. Шире, чем у иконки: там дуга плотная и короткий разрыв
    /// читается, а здесь линия тоньше — с узким разрывом буква закрывалась.
    private static let opening: Double = 84

    /// Тоньше иконки и чуть толще прежнего кольца: внутри живёт крупное число
    /// остатка, и ему нужен воздух, но дуга из трёх макросов должна читаться
    /// как знак, а не как волосяная линия.
    private let lineWidth: CGFloat = 20
    /// Меньше прежних 230, но ненамного: знак — единственная крупная вещь на
    /// экране, и слишком маленький он теряет вес, ради которого на него и
    /// смотрят.
    private let size: CGFloat = 216

    struct Segment: Identifiable, Equatable {
        let id: String
        let start: Double
        let end: Double
        let progress: Double
        let colors: [Color]
    }

    // Пары близкие: цвет почти однотонный, градиент только оживляет дугу.
    // Эмаль иконки с глубоким градиентом пробовали — на кольце с его тонкими
    // дугами прежние мягкие цвета смотрелись лучше.
    // Открыты для карточки макросов: цифры под кольцом должны быть того же
    // цвета, что дуги, а не системных синего, оранжевого и фиолетового.
    // Сами оттенки лежат в общей палитре: те же цвета рисует виджет, и держать
    // их в двух местах — значит однажды показать рядом два разных приложения.
    // На экран они выходят с поправкой на выбранную человеком насыщенность.
    private static func tuned(_ ramp: Palette.Ramp) -> [Color] {
        Palette.colors(ramp, intensity: PaletteIntensity.current)
    }

    static var kcalColors: [Color] { tuned(Palette.kcal) }
    static var proteinColors: [Color] { tuned(Palette.protein) }
    static var fatColors: [Color] { tuned(Palette.fat) }
    static var carbColors: [Color] { tuned(Palette.carbs) }
    /// Перебор — глубокий красный.
    ///
    /// Системные оранжевый с красным брать больше нельзя: жиры стали мягким
    /// персиком, и системный оранжевый оказывался их соседом по тону — дуга
    /// перебора читалась как ещё один макрос, а не как тревога. Этот темнее и
    /// насыщеннее всего, что есть в кольце.
    static var overColors: [Color] { tuned(Palette.over) }

    /// Путь кольца до остановки перед финишем.
    static let spinDuration = RingTicks.duration
    /// Обновление держится чуть дольше, чем кольцо идёт до остановки: пауза
    /// перед финишем, а докрут — уже вместе с возвратом экрана.
    static let refreshHold = RingTicks.duration + 0.3

    /// Точка на окружности в долях рамки — для градиента вдоль дуги.
    private static func point(at degrees: Double) -> UnitPoint {
        let radians = degrees * .pi / 180
        return UnitPoint(x: 0.5 + 0.5 * sin(radians), y: 0.5 - 0.5 * cos(radians))
    }

    private static func ratio(_ value: Double, _ target: Double?) -> Double {
        guard let target, target > 0 else { return 0 }
        return min(max(value / target, 0), 1)
    }

    /// Зазор между дугами — тот же расчёт, что у знака: скруглённые концы
    /// съедают тем больше градусов, чем толще дуга при том же радиусе.
    private var gap: Double {
        let radius = (size - lineWidth) / 2
        return 1.25 / (radius / lineWidth) * 180 / .pi
    }

    private var segments: [Segment] {
        // Доли дуг — по граммам целей. Без целей (профиль не заполнен)
        // поровну; совсем крошечной дуге не даём пропасть — её не разглядеть.
        let targets = [carbsTarget ?? 0, fatTarget ?? 0, proteinTarget ?? 0]
        let total = targets.reduce(0, +)
        let rawShares = total > 0 ? targets.map { $0 / total } : [1.0 / 3, 1.0 / 3, 1.0 / 3]
        let floored = rawShares.map { max($0, 0.08) }
        let shares = floored.map { $0 / floored.reduce(0, +) }

        // Порядок как на иконке: сверху от разрыва углеводы, ниже жиры, у
        // нижнего конца «С» белки. Дуги идут вниз от верхнего конца, поэтому
        // заливка каждой растёт снизу вверх, к разрыву.
        let parts: [(String, Double, [Color])] = [
            ("carbs", showsTargets ? 1 : Self.ratio(macros.carbs, carbsTarget), Self.carbColors),
            ("fat", showsTargets ? 1 : Self.ratio(macros.fat, fatTarget), Self.fatColors),
            ("protein", showsTargets ? 1 : Self.ratio(macros.protein, proteinTarget), Self.proteinColors),
        ]
        let gap = gap
        let available = 360 - Self.opening - gap * Double(parts.count - 1)
        var cursor = Self.topEnd
        return parts.enumerated().map { index, part in
            let span = available * shares[index]
            let segment = Segment(id: part.0, start: cursor - span, end: cursor,
                                  progress: part.1, colors: part.2)
            cursor -= span + gap
            return segment
        }
    }

    var body: some View {
        ZStack {
            // Дуги — своей вьюхой, и это не про порядок в файле.
            //
            // Пока список тянут вниз, угол меняется на каждом кадре, и тело
            // кольца пересчитывалось целиком: доли макросов, цвета, восемь дуг
            // с градиентами. Вынесенные дуги получают те же самые доли и цвета,
            // SwiftUI видит, что аргументы не изменились, и не перерисовывает
            // их — поворачивается уже готовая картинка.
            RingArcs(segments: segments, lineWidth: lineWidth)
                // Одним слоем: каждая дуга крутилась отдельно,
                // и на обороте цвета размазывались друг по другу. Склеенное кольцо
                // поворачивается как цельная картинка.
                .compositingGroup()
            .modifier(RefreshSpin(baseRotation: Self.rotation, pullAngle: pullAngle, spinTicket: spinTicket))
            // Дуга доезжает до новой длины пружиной — на любое изменение
            // съеденного, откуда бы оно ни пришло.
            .animation(.spring(response: 0.65, dampingFraction: 0.85), value: consumed)
            .animation(.spring(response: 0.65, dampingFraction: 0.85), value: macros)

            centerLabel
                // Без своей анимации contentTransition ничего не делает, и
                // число подменялось за кадр, пока дуга ехала.
                .animation(.spring(response: 0.65, dampingFraction: 0.85), value: consumed)
        }
        .frame(width: size, height: size)
        // Размер кольца фиксирован, текст внутри масштабировать некуда.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .contentShape(Circle())
        .onTapGesture(perform: onOpen)
        // Своей подписи нет намеренно: VoiceOver читает содержимое кольца
        // («Остаток 2183 из 2582 ккал»), и это точнее любой общей фразы.
        // А «Добавить еду» тут ещё и совпало бы с пунктом меню на плюсе.
        .accessibilityIdentifier("addFromRing")
        .accessibilityAddTraits(.isButton)
    }

    private var centerLabel: some View {
        // Крупным идёт остаток, а не съеденное: смотрят на кольцо ради одного
        // вопроса — сколько ещё можно. Съеденное осталось, но ушло вниз: это
        // справка, а не то, ради чего сюда смотрят.
        let remaining = goal - consumed
        let overGoal = remaining < 0
        if showsTargets {
            return AnyView(VStack(spacing: 2) {
                Text("Норма")
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
                Text(verbatim: "\(goal)")
                    .font(.app(size: 40, weight: .bold))
                Text("ккал в день")
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
            })
        }
        return AnyView(VStack(spacing: 2) {
            // Тихо, как подписи плашек: цвет только у слова «Перебор», число
            // остаётся обычным — красная цифра во весь круг кричала.
            Text(overGoal ? "Перебор" : "Остаток")
                .font(.app(.caption))
                // Тем же цветом, что и дуга перебора: подпись и дуга говорят
                // об одном, а системный оранжевый рядом с персиковыми жирами
                // читался третьим, ничего не значащим оттенком.
                .foregroundStyle(overGoal ? Self.overColors[0] : Color.secondary)
            // Чуть мельче прежнего: знак уже кольца, и прежние 42 упирались
            // в дуги на четырёхзначном остатке.
            Text("\(abs(remaining))")
                .font(.app(size: 40, weight: .bold))
                .foregroundStyle(Color.primary)
                .contentTransition(.numericText())
            Text("из \(goal) ккал")
                .font(.app(.caption))
                .foregroundStyle(.secondary)
            Text("съедено \(consumed)")
                .font(.app(.caption2))
                .foregroundStyle(.tertiary)
                .contentTransition(.numericText())
        })
    }
}

/// Дуги кольца: дорожка и залитая часть на каждый сегмент.
///
/// Отдельной вьюхой ради жеста: поворот кольца за пальцем меняется на каждом
/// кадре, а дуги при этом те же. Отдельная вьюха с теми же аргументами
/// перерисовываться не будет.
private struct RingArcs: View {
    let segments: [ProgressRing.Segment]
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            ForEach(segments) { segment in
                // Дорожка — цвет самой дуги, приглушённый, как у полосок
                // макросов под кольцом. Вместо серой канавки: пустое кольцо
                // уже показывает, на что делится день.
                RingArc(start: segment.start, end: segment.end)
                    // Толще дуга — заметнее и дорожка, поэтому она бледнее
                    // прежнего: на иконке дорожки нет вовсе, и здесь она
                    // должна читаться как место под цвет, а не как второй знак.
                    .stroke(segment.colors[0].opacity(0.15),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                // Своей дугой, а не общей: у этой есть анимируемые данные, и
                // заливка растёт плавно, а не перескакивает.
                RingArc(start: segment.start,
                        end: segment.start + (segment.end - segment.start) * segment.progress)
                    // Градиент вдоль самой дуги, а не по всему кольцу: иначе дуга
                    // в углу получала бы только один край градиента.
                    .stroke(LinearGradient(colors: segment.colors,
                                           startPoint: CircleArc.point(at: segment.start),
                                           endPoint: CircleArc.point(at: segment.end)),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    // Скруглённые концы у нулевой длины дают точку — её и гасим.
                    .opacity(segment.progress > 0 ? 1 : 0)
            }
        }
        .padding(lineWidth / 2)
    }
}

/// Дуга кольца — общая `CircleArc` плюс анимация по концу, чтобы заливка
/// росла, а не перескакивала. Своим типом именно ради этого: у общей дуги
/// анимируемых данных нет, и знаку «С» с виджетом они не нужны.
private struct RingArc: Shape {
    var start: Double
    var end: Double

    var animatableData: Double {
        get { end }
        set { end = newValue }
    }

    func path(in rect: CGRect) -> Path {
        CircleArc(start: start, end: end).path(in: rect)
    }
}

/// Щелчки колеса при повороте кольца — как у барабана выбора.
///
/// Во время оборота значения угла SwiftUI наружу не отдаёт, поэтому моменты
/// щелчков считаются заранее по той же кривой, что и анимация: где угол
/// пересекает очередное деление, там и щелчок. Так они сами редеют к концу,
/// как у докручивающегося колеса.
enum RingTicks {
    /// Путь до остановки перед финишем. Неторопливо: быстрый оборот щёлкал
    /// сплошной трелью.
    static let duration = 1.7
    static let step = 30.0
    static let curve = Animation.timingCurve(c1.x, c1.y, c2.x, c2.y, duration: duration)

    private static let c1 = (x: 0.4, y: 0.0)
    private static let c2 = (x: 0.2, y: 1.0)

    /// Звук идёт со своей очереди: запущенный с главной, он стопорил кадры
    /// анимации, и оборот подлагивал на каждом щелчке.
    private static let soundQueue = DispatchQueue(label: "calories.ring.click", qos: .userInteractive)

    static func notch(_ angle: Double) -> Int { Int((angle / step).rounded(.down)) }

    /// Один щелчок — пока кольцо идёт за пальцем.
    ///
    /// Только звук, без вибрации. Вибромотор на щелчках почти не ощущался, но
    /// сам щёлкал — и через динамик под звуком колеса был слышен второй, тихий
    /// звук, будто каждый щелчок двоится.
    @MainActor static func tick() {
        guard let sound = RingSound.current.soundID else { return }
        soundQueue.async { AudioServicesPlaySystemSound(sound) }
    }

    /// Щелчки на пути от угла к углу за время оборота.
    ///
    /// Всё расписание отдаётся сразу — отложенными вызовами от одного начала
    /// отсчёта. Цепочка задержек на главном потоке набегала и уводила щелчки
    /// от кольца.
    @MainActor static func play(from start: Double, to end: Double) {
        guard end > start, let sound = RingSound.current.soundID else { return }
        let times = crossingTimes(from: start, to: end)
        let origin = DispatchTime.now()
        for time in times {
            soundQueue.asyncAfter(deadline: origin + time) { AudioServicesPlaySystemSound(sound) }
        }
    }

    /// Когда по кривой анимации угол проходит каждое деление.
    static func crossingTimes(from start: Double, to end: Double) -> [Double] {
        var times: [Double] = []
        var next = (Double(notch(start)) + 1) * step
        let samples = 400
        for i in 0...samples {
            let s = Double(i) / Double(samples)
            let x = bezier(s, c1.x, c2.x)
            let angle = start + (end - start) * bezier(s, c1.y, c2.y)
            while angle >= next, next <= end {
                times.append(x * duration)
                next += step
            }
        }
        return times
    }

    private static func bezier(_ t: Double, _ p1: Double, _ p2: Double) -> Double {
        let u = 1 - t
        return 3 * u * u * t * p1 + 3 * u * t * t * p2 + t * t * t
    }
}

/// Звук щелчков кольца — на выбор в настройках.
///
/// Системные звуки: у приложения нет своих файлов, а системные звучат так же,
/// как клавиатура и барабаны даты, и, как все системные, молчат при
/// выключенном звонке.
enum RingSound: String, CaseIterable, Identifiable {
    case wheel, click, tock, tink, off

    static let defaultsKey = "ring_sound"

    var id: String { rawValue }

    /// Выбранный звук. Читается при каждом обороте, а не держится в памяти:
    /// выбор в настройках действует сразу.
    static var current: RingSound {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(RingSound.init(rawValue:)) ?? .wheel
    }

    var title: String {
        switch self {
        case .wheel: return String(localized: "Колесо")
        case .click: return String(localized: "Щелчок")
        case .tock:  return String(localized: "Тук")
        case .tink:  return String(localized: "Динь")
        case .off:   return String(localized: "Без звука")
        }
    }

    var soundID: SystemSoundID? {
        switch self {
        case .wheel: return 1157 // барабан выбора даты
        case .click: return 1104 // клавиша клавиатуры
        case .tock:  return 1105 // «ток» клавиатуры
        case .tink:  return 1103 // «тинь»
        case .off:   return nil
        }
    }
}

/// Оборот кольца вместо спиннера обновления — общий для «Сегодня» и «Шагов».
///
/// Пока список тянут, кольцо идёт за пальцем и щёлкает на делениях. Отпустили —
/// кольцо идёт вперёд до полного оборота и ещё одного, но встаёт за 45° до
/// финиша, ждёт, когда экран тронется вверх, и докручивает остаток одним
/// движением вместе с ним.
struct RefreshSpin: ViewModifier {
    /// Постоянный поворот кольца, поверх которого идёт оборот.
    let baseRotation: Double
    let pullAngle: Double
    let spinTicket: Int

    @State private var turn: Double = 0
    /// Кольцо не слушает палец: идёт оборот, или после него список ещё не
    /// вернулся в покой. Место под скрытым спиннером держит список стянутым,
    /// пока идёт обновление, и без этой паузы кольцо откручивалось назад
    /// вместе с возвращающимся списком.
    @State private var ignoresPull = false
    /// Кольцо встало перед финишем и ждёт, когда экран тронется вверх:
    /// здесь лежит, насколько список был стянут в этот момент.
    ///
    /// Докрут запускается одним движением по первому сдвигу списка, а не
    /// следует за ним: система возвращает список в два приёма, и кольцо,
    /// повторявшее каждый, дёргалось на финише дважды.
    @State private var settleFromPull: Double?
    @State private var settling = false

    /// Сколько градусов оборота оставлять на возврат экрана.
    static let settleAngle = 45.0

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(baseRotation + turn + (ignoresPull ? 0 : pullAngle)))
            .onChange(of: spinTicket) { _, _ in spin() }
            .onChange(of: pullAngle) { old, angle in
                if let hold = settleFromPull {
                    if !settling, angle < hold - 2 { settle() }
                    return
                }
                // Меньше градуса — уже покой: отскок списка редко останавливается ровно в ноль.
                if angle < 1, turn == 0 { ignoresPull = false }
                // Щелчок на каждом делении, пока кольцо идёт за пальцем.
                if !ignoresPull, RingTicks.notch(angle) != RingTicks.notch(old) {
                    RingTicks.tick()
                }
            }
    }

    /// Оборот на обновление: с того угла, где кольцо оставил палец, вперёд
    /// до полного оборота и ещё один. Назад оно не крутится никогда — поэтому
    /// угол от пальца сначала переносится в оборот, а список возвращается на
    /// место уже без влияния на кольцо.
    private func spin() {
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) {
            turn += pullAngle
            ignoresPull = true
            settleFromPull = nil
        }
        // Встаём за 45° до полного оборота (и ещё одного) и ждём возврата экрана.
        let stop = (ceil(turn / 360) + 1) * 360 - Self.settleAngle
        RingTicks.play(from: turn, to: stop)
        withAnimation(RingTicks.curve) {
            turn = stop
        } completion: {
            if pullAngle > 5 {
                settleFromPull = pullAngle
                // Страховка: если список так и не тронулся, финиш не ждёт вечно.
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1.5))
                    if settleFromPull != nil, !settling { settle() }
                }
            } else {
                // Список уже вернулся сам — докручиваем без него.
                settle()
            }
        }
    }

    /// Последние градусы — одним плавным движением, вместе с подъёмом экрана.
    private func settle() {
        settling = true
        withAnimation(.timingCurve(0.25, 0.1, 0.25, 1, duration: 0.5)) {
            turn += Self.settleAngle
        } completion: {
            finishSpin()
        }
    }

    /// Оборот закончен: последний щелчок, угол сводится к нулю — на вид то же
    /// самое, полный оборот, — и кольцо снова слушает палец.
    private func finishSpin() {
        var instant = Transaction()
        instant.disablesAnimations = true
        RingTicks.tick()
        withTransaction(instant) {
            turn = 0
            settleFromPull = nil
            settling = false
            ignoresPull = pullAngle >= 1
        }
    }

}
