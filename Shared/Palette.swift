import SwiftUI

/// Палитра кольца — общая для приложения и виджетов.
///
/// Папка `Shared` входит в оба таргета, и это единственный способ держать цвета
/// в одном месте: файлы `Calories` в таргет виджета не попадают, поэтому раньше
/// здесь жили две копии — оттенки, насыщенность и перевод из шестнадцатеричного.
/// Копии успевали разойтись: виджет ещё рисовал старую пару «небесный → морской»,
/// когда кольцо в приложении уже позеленело.
///
/// У каждого цвета три состояния, а не одно с формулой поверх. Формула —
/// умножение насыщенности — на сине-фиолетовом врала в обе стороны: на минимуме
/// сирень выцветала в серый, на максимуме уходила в электрический фиолетовый.
/// Дело в том, что насыщенность читается не одинаково по тонам: сине-фиолетовые
/// теряют себя гораздо раньше зелёных и оранжевых. Поэтому оба конца заданы
/// руками: `pale` — запылённый, `vivid` — сочный, и у сирени он ведёт тон к
/// розовому, а не к синему, иначе это уже не сирень.
enum Palette {
    /// Цвет в состояниях пастели. Каждое — пара для градиента дуги.
    ///
    /// Насыщенных состояний здесь больше нет. Они были — «стандарт» и
    /// «контраст», — и до экрана не доходили: приложение про лёгкость, а
    /// плакатные цвета на нём читались как чужие. Осталась пастель, и
    /// выбирать в ней есть из чего: от дымки до плотной.
    struct Ramp {
        /// Имя нужно не для показа, а для памяти готовых цветов: по нему они
        /// и лежат в кэше.
        let name: String
        /// Самый светлый конец: цвета почти ушли в белый.
        let faint: [Color]
        /// Плотный конец — та пастель, что была в приложении до сих пор.
        let pale: [Color]
    }

    static let kcal = Ramp(name: "kcal",
                           faint: [Color(hex: 0xAAFCE2), Color(hex: 0x8EFADD)],
                           pale: [Color(hex: 0x6ADFB9), Color(hex: 0x3AC09C)])
    /// Дальний конец дуги раньше уходил в стальной синий: светимость падала
    /// вдвое (0.58 → 0.29), вчетверо круче, чем у жиров, и белок читался
    /// тяжёлым даже на минимальной насыщенности. Теперь падение такое же, как
    /// у соседей, и цвет остаётся бирюзовым, а не синеет.
    static let protein = Ramp(name: "protein",
                              faint: [Color(hex: 0xA0F4FD), Color(hex: 0x80E3FC)],
                              pale: [Color(hex: 0x5DD9E6), Color(hex: 0x2DBBDF)])
    static let fat = Ramp(name: "fat",
                          faint: [Color(hex: 0xFED5BE), Color(hex: 0xFEBEAA)],
                          pale: [Color(hex: 0xF5B591), Color(hex: 0xF59172)])
    /// Сирень. Сочный конец смещён по тону к розовому: та же насыщенность,
    /// взятая на своём тоне, давала фиолетовый — цвет из другой палитры.
    static let carbs = Ramp(name: "carbs",
                            faint: [Color(hex: 0xE3CDFE), Color(hex: 0xCCB1FE)],
                            pale: [Color(hex: 0xCAA8F5), Color(hex: 0xA77DF5)])
    /// Перебор — красно-коралловый, а не системный оранжевый: тот спорил бы по
    /// тону с цветом жиров.
    static let over = Ramp(name: "over",
                           faint: [Color(hex: 0xFEB0AA), Color(hex: 0xFA9EA4)],
                           pale: [Color(hex: 0xF57B72), Color(hex: 0xC04E56)])

    /// Ниже этой светимости дуга тонет в тёмной теме.
    ///
    /// Порог нужен потому, что тона светят по-разному: сине-фиолетовый вдвое
    /// темнее мяты при той же яркости, и на почти чёрном фоне читался как
    /// выключенный. Поднимаем сначала яркостью, а когда она уже на максимуме —
    /// капелькой белого: чуть более светлая орхидея на чёрном выглядит лучше,
    /// чем электрический фиолетовый на нём же.
    static let darkLuminanceFloor = 0.20

    /// Готовые цвета: считаются один раз на каждое сочетание цвета и
    /// насыщенности.
    ///
    /// Кольцо спрашивает их на каждой перерисовке — а перерисовывается оно на
    /// каждом кадре, пока список тянут вниз. Каждый вопрос стоил двух переводов
    /// в HSB, подъёма светимости и создания динамического цвета: полмиллисекунды
    /// на кадр там, где весь кадр — шестнадцать. Насыщенность человек меняет
    /// ползунком раз в месяц, так что помнить нечего, кроме десятка пар.
    private nonisolated(unsafe) static var cache: [String: [Color]] = [:]
    private static let cacheLock = NSLock()

    /// Цвета на экран: состояние между `pale` и `vivid` по выбранной
    /// насыщенности, с поправкой на тёмную тему.
    static func colors(_ ramp: Ramp, intensity: Double) -> [Color] {
        let factor = min(max(intensity, PaletteIntensity.range.lowerBound),
                         PaletteIntensity.range.upperBound)
        let key = "\(ramp.name)-\(Int((factor * 1000).rounded()))"
        cacheLock.lock()
        let remembered = cache[key]
        cacheLock.unlock()
        if let remembered { return remembered }
        // Один отрезок вместо двух: ползунок идёт от дымки до плотной
        // пастели и дальше не ведёт никуда. Серединной точки, на которой
        // раньше стоял «стандарт», больше нет.
        let span = PaletteIntensity.range.upperBound - PaletteIntensity.range.lowerBound
        let amount = span > 0 ? (factor - PaletteIntensity.range.lowerBound) / span : 1
        let colors = zip(ramp.faint, ramp.pale).map { $0.blended(with: $1, amount: amount).liftedOnDark() }
        cacheLock.lock()
        cache[key] = colors
        cacheLock.unlock()
        return colors
    }
}

/// Плотность пастели — общий множитель для всех цветов кольца.
///
/// Раньше это была насыщенность от пастели до плаката. Плакат убран совсем:
/// приложение про лёгкость, и кричащие цвета в нём выглядели чужими, сколько
/// бы ни стоял ползунок. Выбор остался, но весь внутри пастели — от дымки,
/// где цвет едва намечен, до плотной, с которой приложение и жило.
enum PaletteIntensity {
    static let key = "palette_intensity"
    /// Границы: на них приходятся `faint` и `pale`.
    static let range: ClosedRange<Double> = 0.0...1.0
    /// Значение по умолчанию: плотная пастель — та, что была до сих пор.
    static let standard: Double = 1

    static var current: Double { current(groupDefaults: .standard) }

    /// То же число для виджета — он читает общий контейнер группы.
    static func current(groupDefaults: UserDefaults?) -> Double {
        let stored = groupDefaults?.object(forKey: key) as? Double ?? standard
        return min(max(stored, range.lowerBound), range.upperBound)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.displayP3,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }

    /// Промежуточный цвет между двумя состояниями.
    ///
    /// Тон идёт короткой дугой круга: у сирени сочное состояние смещено к
    /// розовому, и по прямой между числами тон пошёл бы через всю радугу.
    func blended(with other: Color, amount: Double) -> Color {
        let t = min(max(amount, 0), 1)
        guard let from = hsb, let to = other.hsb else { return self }
        var delta = to.hue - from.hue
        if delta > 0.5 { delta -= 1 }
        if delta < -0.5 { delta += 1 }
        return Color(hue: (from.hue + delta * t + 1).truncatingRemainder(dividingBy: 1),
                     saturation: from.saturation + (to.saturation - from.saturation) * t,
                     brightness: from.brightness + (to.brightness - from.brightness) * t)
    }

    /// Тот же цвет, но в тёмной теме не темнее порога.
    ///
    /// Именно динамический цвет, а не два набора палитры: кольцо, карточка
    /// макросов и виджет берут цвет один раз, а тему человек меняет когда
    /// захочет — в том числе автоматически на закате.
    func liftedOnDark(floor: Double = Palette.darkLuminanceFloor) -> Color {
        let lifted = UIColor(lifted(toLuminance: floor))
        let plain = UIColor(self)
        return Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? lifted : plain
        })
    }

    /// Тот же тон, поднятый до нужной светимости.
    ///
    /// Сначала яркостью — она не меняет характер цвета. Когда яркость уже на
    /// максимуме, остаётся отдавать насыщенность: у тёмных тонов вроде
    /// фиолетового яркости не хватает, сколько её ни дай.
    func lifted(toLuminance floor: Double) -> Color {
        guard let parts = hsb, luminance < floor, luminance > 0 else { return self }
        var brightness = min(parts.brightness * pow(floor / luminance, 1 / 2.2), 1)
        var saturation = parts.saturation
        var result = Color(hue: parts.hue, saturation: saturation, brightness: brightness)
        var steps = 0
        while result.luminance < floor, saturation > 0.05, steps < 10 {
            saturation *= 0.92
            brightness = min(brightness * 1.02, 1)
            result = Color(hue: parts.hue, saturation: saturation, brightness: brightness)
            steps += 1
        }
        return result
    }

    /// Относительная светимость: насколько цвет светит, а не насколько он ярок
    /// по HSB. Зелёный при той же яркости светит вчетверо сильнее синего.
    var luminance: Double {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard UIColor(self).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return 1 }
        func linear(_ value: CGFloat) -> Double {
            let value = Double(value)
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// Тон, насыщенность и яркость — то, в чём палитра и рассуждает.
    var hsb: (hue: Double, saturation: Double, brightness: Double)? {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        guard UIColor(self).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        else { return nil }
        return (Double(hue), Double(saturation), Double(brightness))
    }
}
