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

    // Палитра «Уверенность» (21.11.2026): индиго вместо мяты.
    //
    // Приложение продаёт программу — «сбросить и удержать», — а синий в
    // восприятии брендов читается как компетентность и надёжность, и
    // сине-фиолетовый будоражит меньше всех тонов: спокойный фон для тех, кто
    // срывается. Тона макросов прежние — бирюза, персик, сирень, — но сирень
    // сдвинута к орхидее: рядом с индиго калорий прежняя с ним сливалась, а
    // бирюза взята чуть зеленее, чтобы не тянуться к синему.
    static let kcal = Ramp(name: "kcal",
                           faint: [Color(hex: 0xC3CCFB), Color(hex: 0xA6B4F9)],
                           pale: [Color(hex: 0x8C9DF7), Color(hex: 0x5B74F0)])
    /// Дальний конец дуги раньше уходил в стальной синий: светимость падала
    /// вдвое (0.58 → 0.29), вчетверо круче, чем у жиров, и белок читался
    /// тяжёлым даже на минимальной насыщенности. Теперь падение такое же, как
    /// у соседей, и цвет остаётся бирюзовым, а не синеет.
    static let protein = Ramp(name: "protein",
                              faint: [Color(hex: 0xA6F5F1), Color(hex: 0x84EDEA)],
                              pale: [Color(hex: 0x5EE0DC), Color(hex: 0x22C2CF)])
    static let fat = Ramp(name: "fat",
                          faint: [Color(hex: 0xFED5C2), Color(hex: 0xFEBEAA)],
                          pale: [Color(hex: 0xF7B598), Color(hex: 0xF58A6E)])
    /// Сирень. Сочный конец смещён по тону к розовому: та же насыщенность,
    /// взятая на своём тоне, давала фиолетовый — цвет из другой палитры.
    static let carbs = Ramp(name: "carbs",
                            faint: [Color(hex: 0xF0D4FE), Color(hex: 0xE3BDFC)],
                            pale: [Color(hex: 0xDDAAF5), Color(hex: 0xC27BF0)])
    /// Мимо нормы — перебор и недобор — малиновым.
    ///
    /// Цвета состояний не должны совпадать с цветами макросов: оранжевый
    /// перебор читался бы соседом персиковых жиров, бирюзовый недобор — белком.
    /// Малинового среди макросов нет, и красное семейство само говорит
    /// «мимо». Пары с зелёным, которую путают дальтоники, больше нет: норма —
    /// индиго. Направление видно по кольцу, а не по цвету: недобор — короткая
    /// дуга, перебор — полное кольцо с тёмным концом.
    static let over = Ramp(name: "over",
                           faint: [Color(hex: 0xF6B3CA), Color(hex: 0xEF94B3)],
                           pale: [Color(hex: 0xE8628F), Color(hex: 0xC2255C)])

    /// Заливка главной кнопки. На ней белый текст, контраст не ниже 4,9 : 1
    /// в обеих темах; светлое индиго тёмной темы под белым текстом не читалось бы.
    static let brand = Color(light: 0x2F45C8, dark: 0x4C63E6)
    /// Акцент значков, ссылок и переключателей. В тёмной теме светлее: тёмное
    /// индиго на почти чёрном фоне тонет.
    static let tint = Color(light: 0x2F45C8, dark: 0x8C9DF7)
    /// «Получилось»: в норме, по плану, белок закрыт. Тот же индиго, что и
    /// бренд — успех здесь не зелёный, а цвет самого приложения.
    static let good = tint
    /// «Мимо»: перебор, отставание, вес вверх на сушке — текстом и значками.
    /// Тот же малиновый, что дуга перебора, на белом не ниже 4,5 : 1.
    static let warn = Color(light: 0xC2255C, dark: 0xF0749C)
    /// Коралл — только «Пора есть». Один цвет — одно значение: тёплый там, где
    /// приложение зовёт к еде, и больше нигде.
    static let mealTime = Color(light: 0xE5603D, dark: 0xFF8A6B)

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
    /// Цвет с отдельными оттенками для светлой и тёмной темы.
    init(light: UInt32, dark: UInt32) {
        let light = UIColor(Color(hex: light))
        let dark = UIColor(Color(hex: dark))
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }

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
