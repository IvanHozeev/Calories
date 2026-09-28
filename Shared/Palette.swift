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
    /// Цвет в трёх состояниях. Каждое — пара для градиента дуги.
    struct Ramp {
        let pale: [Color]
        let standard: [Color]
        let vivid: [Color]
    }

    static let kcal = Ramp(pale: [Color(hex: 0x6ADFB9), Color(hex: 0x3AC09C)],
                           standard: [Color(hex: 0x3BE8B0), Color(hex: 0x00C892)],
                           vivid: [Color(hex: 0x1EE1A2), Color(hex: 0x04C28F)])
    static let protein = Ramp(pale: [Color(hex: 0x5DD9E6), Color(hex: 0x389FBC)],
                              standard: [Color(hex: 0x23DCF0), Color(hex: 0x0098C4)],
                              vivid: [Color(hex: 0x05D3E9), Color(hex: 0x0494BE)])
    static let fat = Ramp(pale: [Color(hex: 0xF5B591), Color(hex: 0xF59172)],
                          standard: [Color(hex: 0xFFA06B), Color(hex: 0xFF6B3D)],
                          vivid: [Color(hex: 0xF78C51), Color(hex: 0xF7511D)])
    /// Сирень. Сочный конец смещён по тону к розовому: та же насыщенность,
    /// взятая на своём тоне, давала фиолетовый — цвет из другой палитры.
    static let carbs = Ramp(pale: [Color(hex: 0xCAA8F5), Color(hex: 0xA77DF5)],
                            standard: [Color(hex: 0xC08CFF), Color(hex: 0x8B4DFF)],
                            vivid: [Color(hex: 0xCC76F7), Color(hex: 0xA02FF7)])
    /// Перебор — красно-коралловый, а не системный оранжевый: тот спорил бы по
    /// тону с цветом жиров.
    static let over = Ramp(pale: [Color(hex: 0xF57B72), Color(hex: 0xC04E56)],
                           standard: [Color(hex: 0xFF4A3D), Color(hex: 0xC81E2B)],
                           vivid: [Color(hex: 0xF72C1D), Color(hex: 0xC20412)])

    /// Ниже этой светимости дуга тонет в тёмной теме.
    ///
    /// Порог нужен потому, что тона светят по-разному: сине-фиолетовый вдвое
    /// темнее мяты при той же яркости, и на почти чёрном фоне читался как
    /// выключенный. Поднимаем сначала яркостью, а когда она уже на максимуме —
    /// капелькой белого: чуть более светлая орхидея на чёрном выглядит лучше,
    /// чем электрический фиолетовый на нём же.
    static let darkLuminanceFloor = 0.20

    /// Цвета на экран: состояние между `pale` и `vivid` по выбранной
    /// насыщенности, с поправкой на тёмную тему.
    static func colors(_ ramp: Ramp, intensity: Double) -> [Color] {
        let factor = min(max(intensity, PaletteIntensity.range.lowerBound),
                         PaletteIntensity.range.upperBound)
        let standard = PaletteIntensity.standard
        let (from, to, amount): ([Color], [Color], Double) = factor <= standard
            ? (ramp.pale, ramp.standard,
               (factor - PaletteIntensity.range.lowerBound) / (standard - PaletteIntensity.range.lowerBound))
            : (ramp.standard, ramp.vivid,
               (factor - standard) / (PaletteIntensity.range.upperBound - standard))
        return zip(from, to).map { $0.blended(with: $1, amount: amount).liftedOnDark() }
    }
}

/// Насыщенность палитры — общий множитель для всех цветов кольца.
///
/// Один и тот же набор оттенков одним людям кажется блёклым, другим кричащим,
/// и спорить тут не о чем: вкус. Поэтому тон задан в приложении, а сочность
/// человек выбирает сам — от пастели до плаката.
enum PaletteIntensity {
    static let key = "palette_intensity"
    /// Границы: на них приходятся `pale` и `vivid`, середина — `standard`.
    static let range: ClosedRange<Double> = 0.6...1.35
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
