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

    /// Дуга калорий — своя у каждой схемы (`PaletteScheme`).
    static var kcal: Ramp { PaletteScheme.current.kcal }
    /// Дуги макросов — тоже по схеме: у каждой своя тройка бирюзы, персика и
    /// сирени, в тон её кольцу и кнопкам.
    static var protein: Ramp { PaletteScheme.current.protein }
    static var fat: Ramp { PaletteScheme.current.fat }
    static var carbs: Ramp { PaletteScheme.current.carbs }

    /// Мимо нормы — перебор и недобор — малиновым.
    ///
    /// Цвета состояний не должны совпадать с цветами макросов: оранжевый
    /// перебор читался бы соседом персиковых жиров, бирюзовый недобор — белком.
    /// Малинового среди макросов нет, и красное семейство само говорит
    /// «мимо». Пары с зелёным, которую путают дальтоники, больше нет: норма —
    /// индиго. Направление видно по кольцу, а не по цвету: недобор — короткая
    /// дуга, перебор — полное кольцо с тёмным концом.
    static let over = Ramp(name: "over",
                           faint: [Color(hex: 0xF9BFCD), Color(hex: 0xF5A3B8)],
                           pale: [Color(hex: 0xF2849F), Color(hex: 0xD1456F)])

    /// Заливка главной кнопки — по схеме. Подпись на ней — `onBrand`.
    static var brand: Color { PaletteScheme.current.brand }
    /// Подпись на главной кнопке: белая на цветной, чёрная на белой кнопке
    /// тёмной темы у чёрно-белых схем.
    static var onBrand: Color { PaletteScheme.current.onBrand }
    /// Акцент значков, ссылок и переключателей — по схеме.
    static var tint: Color { PaletteScheme.current.tint }
    /// «Получилось»: в норме, по плану, белок закрыт — по схеме.
    static var good: Color { PaletteScheme.current.good }
    /// «Мимо»: перебор, отставание, вес вверх на сушке — текстом и значками.
    /// Тот же малиновый, что дуга перебора, на белом не ниже 4,5 : 1. Общий
    /// для всех схем: его нет ни среди макросов, ни среди дуг калорий.
    static let warn = Color(light: 0xC23A63, dark: 0xF2849F)

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

/// Цветовая схема: дуга калорий, главные кнопки, акцент и цвет успеха.
///
/// Макросы во всех схемах — бирюза, персик и сирень, но каждая берёт их в
/// своём ключе: прежние, земляные или дымчатые. Тоны остаются, и выученное в
/// первые дни не теряется. Перебор и недобор общие — малиновые.
///
/// Новые схемы держат правило палитры: их дуга калорий не ближе 25° по тону
/// к любому макросу, иначе кольцо сливается (так было с чистым индиго и
/// сиренью). «Свежесть» — прежний вид как есть, её мята к бирюзе ближе.
/// Проверяет `PaletteSchemeTests`.
enum PaletteScheme: String, CaseIterable, Identifiable {
    /// Мята и чёрные кнопки — то, с чем приложение жило до 21.11.2026.
    case fresh
    /// Индиго — программа и доверие. По умолчанию.
    case trust
    /// Шалфей и кофейные кнопки. Не терракота: она стояла бы вплотную к
    /// персику жиров.
    case warm
    /// Чёрно-белое, кольцо — лайм: единственный яркий цвет на сером
    /// замечают первым.
    case graphite

    var id: String { rawValue }

    static let key = "palette_scheme"
    /// Общий контейнер группы: виджет рисует ту же схему, а настроек
    /// приложения он не видит.
    static let store = UserDefaults(suiteName: "group.calories.shared")
    static let standard: PaletteScheme = .trust

    /// Просьба пересобрать экраны в выбранной схеме. Шлют корни вкладок, когда
    /// к ним вернулись; слушает `RootView` и пересобирает, только если схема
    /// и правда сменилась.
    static let applyNotification = Notification.Name("PaletteScheme.apply")

    static func requestApply() {
        NotificationCenter.default.post(name: applyNotification, object: nil)
    }

    static var current: PaletteScheme {
        store?.string(forKey: key).flatMap(PaletteScheme.init(rawValue:)) ?? standard
    }

    var kcal: Palette.Ramp {
        switch self {
        case .fresh: return Self.freshKcal
        case .trust: return Self.trustKcal
        case .warm: return Self.warmKcal
        case .graphite: return Self.graphiteKcal
        }
    }

    var brand: Color {
        switch self {
        case .fresh, .graphite: return Self.ink
        case .trust: return Self.trustBrand
        case .warm: return Self.warmBrand
        }
    }

    var onBrand: Color {
        switch self {
        case .fresh, .graphite: return Self.onInk
        case .trust, .warm: return .white
        }
    }

    var tint: Color {
        switch self {
        case .fresh: return Self.freshTint
        case .trust: return Self.trustTint
        case .warm: return Self.warmTint
        case .graphite: return Self.graphiteTint
        }
    }

    var good: Color {
        switch self {
        case .fresh: return Self.freshGood
        case .trust: return Self.trustTint
        case .warm: return Self.warmGood
        case .graphite: return Self.graphiteGood
        }
    }

    var protein: Palette.Ramp {
        switch self {
        case .fresh, .trust: return Self.classicProtein
        case .warm: return Self.warmProtein
        case .graphite: return Self.graphiteProtein
        }
    }

    var fat: Palette.Ramp {
        switch self {
        case .fresh, .trust: return Self.classicFat
        case .warm: return Self.warmFat
        case .graphite: return Self.graphiteFat
        }
    }

    var carbs: Palette.Ramp {
        switch self {
        case .fresh, .trust: return Self.classicCarbs
        case .warm: return Self.warmCarbs
        case .graphite: return Self.graphiteCarbs
        }
    }

    /// Цвет текста макроса на белом: тот же тон, что у дуги, насыщеннее и чуть
    /// глубже — без примеси чёрного, которая гасит пастель в грязь. Порядок —
    /// белок, жиры, углеводы.
    var inks: (protein: Color, fat: Color, carbs: Color) {
        switch self {
        case .fresh, .trust: return (Color(hex: 0x0E9FCB), Color(hex: 0xEC5F37), Color(hex: 0x8F5CF0))
        case .warm: return (Color(hex: 0x2F7C9A), Color(hex: 0xCB7D22), Color(hex: 0x8452AE))
        case .graphite: return (Color(hex: 0x3E8BD4), Color(hex: 0xD4703A), Color(hex: 0x8D6BD1))
        }
    }

    // Готовые цвета — постоянными: кольцо спрашивает дугу на каждом кадре, и
    // собирать её заново из чисел каждый раз незачем.

    // Макросы «Свежести» и «Уверенности» — прежние, с ними приложение жило
    // с самого начала; индиго подстроено под них, а не наоборот.

    /// Дальний конец дуги раньше уходил в стальной синий: светимость падала
    /// вдвое (0.58 → 0.29), вчетверо круче, чем у жиров, и белок читался
    /// тяжёлым даже на минимальной насыщенности. Теперь падение такое же, как
    /// у соседей, и цвет остаётся бирюзовым, а не синеет.
    fileprivate static let classicProtein = Palette.Ramp(name: "protein",
                              faint: [Color(hex: 0xA0F4FD), Color(hex: 0x80E3FC)],
                              pale: [Color(hex: 0x5DD9E6), Color(hex: 0x2DBBDF)])
    fileprivate static let classicFat = Palette.Ramp(name: "fat",
                          faint: [Color(hex: 0xFED5BE), Color(hex: 0xFEBEAA)],
                          pale: [Color(hex: 0xF5B591), Color(hex: 0xF59172)])
    /// Сирень. Сочный конец смещён по тону к розовому: та же насыщенность,
    /// взятая на своём тоне, давала фиолетовый — цвет из другой палитры.
    fileprivate static let classicCarbs = Palette.Ramp(name: "carbs",
                            faint: [Color(hex: 0xE3CDFE), Color(hex: 0xCCB1FE)],
                            pale: [Color(hex: 0xCAA8F5), Color(hex: 0xA77DF5)])

    // Макросы «Тепла» — земляные: пыльная бирюза, горчица, слива. Те же три
    // тона, но приглушённые, как шалфей и кофе вокруг них.
    private static let warmProtein = Palette.Ramp(name: "protein-warm",
        faint: [Color(hex: 0xC7E0EA), Color(hex: 0xAED1DF)],
        pale: [Color(hex: 0x8CBDD0), Color(hex: 0x4E8DA6)])
    private static let warmFat = Palette.Ramp(name: "fat-warm",
        faint: [Color(hex: 0xF7E5C4), Color(hex: 0xF2D7A8)],
        pale: [Color(hex: 0xEECB8E), Color(hex: 0xE0A04A)])
    private static let warmCarbs = Palette.Ramp(name: "carbs-warm",
        faint: [Color(hex: 0xE5DAEE), Color(hex: 0xD6C7E4)],
        pale: [Color(hex: 0xC6B0D8), Color(hex: 0x9B7BB5)])

    // Макросы «Графита» — дымчатые: на чёрно-белом ярким остаётся только
    // кольцо калорий, макросы ему не спорят.
    private static let graphiteProtein = Palette.Ramp(name: "protein-graphite",
        faint: [Color(hex: 0xD6E6F5), Color(hex: 0xC0D9F0)],
        pale: [Color(hex: 0xA9CBEB), Color(hex: 0x6FA8DC)])
    private static let graphiteFat = Palette.Ramp(name: "fat-graphite",
        faint: [Color(hex: 0xF9E3D6), Color(hex: 0xF5D2BE)],
        pale: [Color(hex: 0xF3C7AE), Color(hex: 0xE9A27A)])
    private static let graphiteCarbs = Palette.Ramp(name: "carbs-graphite",
        faint: [Color(hex: 0xEAE3F7), Color(hex: 0xDED3F2)],
        pale: [Color(hex: 0xD1C4EC), Color(hex: 0xB39DDB)])

    /// Мята — прежнее кольцо калорий.
    private static let freshKcal = Palette.Ramp(name: "kcal-fresh",
        faint: [Color(hex: 0xAAFCE2), Color(hex: 0x8EFADD)],
        pale: [Color(hex: 0x6ADFB9), Color(hex: 0x3AC09C)])
    /// Индиго, сдвинутое к синему (около 222°): чистое стояло в тридцати
    /// градусах от сирени углеводов, и на кольце они сливались.
    private static let trustKcal = Palette.Ramp(name: "kcal-trust",
        faint: [Color(hex: 0xC6D6FD), Color(hex: 0xAEC4FC)],
        pale: [Color(hex: 0x8FB0FA), Color(hex: 0x5B86F2)])
    /// Шалфей — тёплая зелень, далеко и от бирюзы, и от персика.
    private static let warmKcal = Palette.Ramp(name: "kcal-warm",
        faint: [Color(hex: 0xDCEBC8), Color(hex: 0xCBE0B0)],
        pale: [Color(hex: 0xB9D19A), Color(hex: 0x86A866)])
    /// Лайм.
    private static let graphiteKcal = Palette.Ramp(name: "kcal-graphite",
        faint: [Color(hex: 0xE9FBB5), Color(hex: 0xDDF68F)],
        pale: [Color(hex: 0xCDEB5C), Color(hex: 0xA6CC1E)])

    /// Чёрная кнопка в светлой теме и белая в тёмной — как было до индиго.
    private static let ink = Color(light: 0x111111, dark: 0xFFFFFF)
    private static let onInk = Color(light: 0xFFFFFF, dark: 0x111111)
    /// Белый текст: 5,5 : 1 в светлой, 4,9 : 1 в тёмной.
    private static let trustBrand = Color(light: 0x3360D8, dark: 0x3F68E0)
    /// Кофе: белый текст читается в обеих темах.
    private static let warmBrand = Color(light: 0x6B4430, dark: 0x8A5A3E)

    /// Системный синий — прежний акцент по умолчанию.
    private static let freshTint = Color(light: 0x007AFF, dark: 0x0A84FF)
    private static let trustTint = Color(light: 0x3360D8, dark: 0x8FB0FA)
    private static let warmTint = Color(light: 0x8A5A3E, dark: 0xD9A483)
    /// Акцент графита — сам графит: цвет здесь только у кольца.
    private static let graphiteTint = Color(light: 0x1C1C1E, dark: 0xF2F2F7)

    /// Системный зелёный — прежний «получилось».
    private static let freshGood = Color(light: 0x34C759, dark: 0x30D158)
    private static let warmGood = Color(light: 0x5E8545, dark: 0xA9C98A)
    /// Глубокий лайм — сам лайм на белом не читается.
    private static let graphiteGood = Color(light: 0x4E7A0E, dark: 0xC6EB5A)
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
