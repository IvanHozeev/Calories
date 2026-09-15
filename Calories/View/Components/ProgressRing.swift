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

/// Кольцо дня: калории и макросы, каждый своей дугой-прогрессом.
///
/// Калории — половина круга: это главное число дня. Вторая половина делится
/// между белками, жирами и углеводами по их целям в граммах, поэтому у типичной
/// сушки самая длинная дуга углеводная, а самая короткая — жировая. Длина дуги
/// — сколько нужно съесть, заливка — сколько уже съедено. Тот же знак на иконке
/// и лаунч-скрине, только там без калорий: буква «С».
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

    /// Поворот как у знака на иконке: разрыв между концом калорий и началом
    /// углеводов уходит на ту же диагональ, и кольцо узнаётся как тот же знак.
    private static let rotation: Double = -40

    /// Тоньше прежних 18: рядом с тонкими полосками и стеклом толстое кольцо
    /// было единственной тяжёлой формой на экране.
    private let lineWidth: CGFloat = 14
    private let size: CGFloat = 230
    /// Зазор между дугами в градусах — с запасом на скруглённые концы.
    private let gap: Double = 11

    private struct Segment: Identifiable {
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
    static let kcalColors = [Color(hex: 0x3FD673), Color(hex: 0x21C45A)]
    static let proteinColors = [Color(hex: 0x4C9BFF), Color(hex: 0x2F7BFF)]
    static let fatColors = [Color(hex: 0xFFA23D), Color(hex: 0xFF8A1F)]
    static let carbColors = [Color(hex: 0xB85CFF), Color(hex: 0xA63BFF)]

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

    private var segments: [Segment] {
        let calorieProgress = showsTargets ? 1 : (goal > 0 ? min(Double(consumed) / Double(goal), 1) : 0)
        let calorieColors: [Color] = consumed > goal ? [.orange, .red] : Self.kcalColors

        // Доли макросов — по граммам целей. Без целей (профиль не заполнен)
        // поровну; совсем крошечной дуге не даём пропасть — её не разглядеть.
        let targets = [proteinTarget ?? 0, fatTarget ?? 0, carbsTarget ?? 0]
        let total = targets.reduce(0, +)
        let rawShares = total > 0 ? targets.map { $0 / total } : [1.0 / 3, 1.0 / 3, 1.0 / 3]
        let floored = rawShares.map { max($0, 0.08) }
        let shares = floored.map { $0 / floored.reduce(0, +) }

        var result = [Segment(id: "kcal", start: gap / 2, end: 180 - gap / 2,
                              progress: calorieProgress, colors: calorieColors)]
        let macroParts: [(String, Double, [Color])] = [
            ("protein", showsTargets ? 1 : Self.ratio(macros.protein, proteinTarget), Self.proteinColors),
            ("fat", showsTargets ? 1 : Self.ratio(macros.fat, fatTarget), Self.fatColors),
            ("carbs", showsTargets ? 1 : Self.ratio(macros.carbs, carbsTarget), Self.carbColors),
        ]
        var cursor = 180.0
        for (index, part) in macroParts.enumerated() {
            let span = 180 * shares[index]
            result.append(Segment(id: part.0, start: cursor + gap / 2, end: cursor + span - gap / 2,
                                  progress: part.1, colors: part.2))
            cursor += span
        }
        return result
    }

    var body: some View {
        ZStack {
            ForEach(segments) { segment in
                // Дорожка — цвет самой дуги, приглушённый, как у полосок
                // макросов под кольцом. Вместо серой канавки: пустое кольцо
                // уже показывает, на что делится день.
                RingArc(start: segment.start, end: segment.end)
                    .stroke(segment.colors[0].opacity(0.18),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                if segment.progress > 0 {
                    RingArc(start: segment.start,
                            end: segment.start + (segment.end - segment.start) * segment.progress)
                        // Градиент вдоль самой дуги, а не по всему кольцу: иначе дуга
                        // в углу получала бы только один край градиента.
                        .stroke(LinearGradient(colors: segment.colors,
                                               startPoint: Self.point(at: segment.start),
                                               endPoint: Self.point(at: segment.end)),
                                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                }
            }
            .padding(lineWidth / 2)
            // Одним слоем: каждая дуга крутилась отдельно,
            // и на обороте цвета размазывались друг по другу. Склеенное кольцо
            // поворачивается как цельная картинка.
            .compositingGroup()
            .modifier(RefreshSpin(baseRotation: Self.rotation, pullAngle: pullAngle, spinTicket: spinTicket))
            .animation(.spring(response: 0.65, dampingFraction: 0.85), value: consumed)
            .animation(.spring(response: 0.65, dampingFraction: 0.85), value: macros)

            centerLabel
                .id(consumed)
                .transition(.opacity.combined(with: .scale(scale: 0.85)))
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
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(verbatim: "\(goal)")
                    .font(.system(size: 42, weight: .bold))
                Text("ккал в день")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            })
        }
        return AnyView(VStack(spacing: 2) {
            // Тихо, как подписи плашек: цвет только у слова «Перебор», число
            // остаётся обычным — красная цифра во весь круг кричала.
            Text(overGoal ? "Перебор" : "Остаток")
                .font(.caption)
                .foregroundStyle(overGoal ? Color.orange : Color.secondary)
            Text("\(abs(remaining))")
                .font(.system(size: 42, weight: .bold))
                .foregroundStyle(Color.primary)
                .contentTransition(.numericText())
            Text("из \(goal) ккал")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("съедено \(consumed)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .contentTransition(.numericText())
        })
    }
}

/// Дуга кольца. Углы — в градусах от 12 часов по часовой стрелке.
/// Анимируется по концу, чтобы заливка росла, а не перескакивала.
private struct RingArc: Shape {
    var start: Double
    var end: Double

    var animatableData: Double {
        get { end }
        set { end = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(center: CGPoint(x: rect.midX, y: rect.midY),
                    radius: min(rect.width, rect.height) / 2,
                    startAngle: .degrees(start - 90),
                    endAngle: .degrees(end - 90),
                    clockwise: false)
        return path
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

    /// Системный звук щелчка колеса выбора — тот же, что у барабанов даты.
    /// Как и все системные звуки, молчит при выключенном звонке.
    private static let clickSound: SystemSoundID = 1157

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
        soundQueue.async { AudioServicesPlaySystemSound(clickSound) }
    }

    /// Щелчки на пути от угла к углу за время оборота.
    ///
    /// Всё расписание отдаётся сразу — отложенными вызовами от одного начала
    /// отсчёта. Цепочка задержек на главном потоке набегала и уводила щелчки
    /// от кольца.
    @MainActor static func play(from start: Double, to end: Double) {
        guard end > start else { return }
        let times = crossingTimes(from: start, to: end)
        let origin = DispatchTime.now()
        for time in times {
            soundQueue.asyncAfter(deadline: origin + time) { AudioServicesPlaySystemSound(clickSound) }
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
