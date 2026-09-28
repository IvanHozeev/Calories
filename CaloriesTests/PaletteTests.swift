import Testing
import SwiftUI
import UIKit
@testable import Calories

/// Палитра кольца: оба конца ползунка должны оставаться собой.
@MainActor
struct PaletteTests {
    private let ramps: [(name: String, ramp: Palette.Ramp)] = [
        ("калории", Palette.kcal), ("белок", Palette.protein), ("жиры", Palette.fat),
        ("углеводы", Palette.carbs), ("перебор", Palette.over),
    ]

    private func resolved(_ color: Color, dark: Bool) -> Color {
        let traits = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
        return Color(uiColor: UIColor(color).resolvedColor(with: traits))
    }

    /// Динамические цвета сравнивать напрямую нельзя: `==` у них про то, один и
    /// тот же это объект или нет, а не про то, как они выглядят.
    private func look(_ colors: [Color], dark: Bool = false) -> [String] {
        colors.map { color in
            let parts = resolved(color, dark: dark).hsb
            return String(format: "%.3f/%.3f/%.3f",
                          parts?.hue ?? -1, parts?.saturation ?? -1, parts?.brightness ?? -1)
        }
    }

    /// Ползунок задаёт положение между бледным и сочным состоянием, а за его
    /// границами ничего нового не происходит.
    @Test func theSliderEndsAreTheHandPickedStates() {
        let low = Palette.colors(Palette.carbs, intensity: PaletteIntensity.range.lowerBound)
        let high = Palette.colors(Palette.carbs, intensity: PaletteIntensity.range.upperBound)
        #expect(look(low) != look(high))
        #expect(look(Palette.colors(Palette.carbs, intensity: 0.1)) == look(low),
                "Ниже границы — та же бледная пара")
        #expect(look(Palette.colors(Palette.carbs, intensity: 9)) == look(high),
                "Выше границы — та же сочная пара")
    }

    /// Сирень на обоих концах остаётся сиренью: тон гуляет внутри
    /// фиолетово-розового участка круга, а не уезжает в синеву.
    @Test func lilacStaysLilacAtBothEnds() throws {
        for intensity in [0.6, 1.0, 1.35] {
            for color in Palette.colors(Palette.carbs, intensity: intensity) {
                let hue = try #require(resolved(color, dark: false).hsb).hue * 360
                #expect(hue >= 255 && hue <= 300, "Тон \(Int(hue))° при насыщенности \(intensity)")
            }
        }
    }

    /// Ни одна дуга не тонет в тёмной теме.
    ///
    /// Раньше сирень на максимуме давала светимость 0.16 — вдвое меньше мяты, —
    /// и на почти чёрном фоне читалась как выключенная.
    @Test func noArcSinksIntoTheDarkTheme() {
        for (name, ramp) in ramps {
            for intensity in [0.6, 1.0, 1.35] {
                for color in Palette.colors(ramp, intensity: intensity) {
                    let luminance = resolved(color, dark: true).luminance
                    #expect(luminance >= Palette.darkLuminanceFloor - 0.01,
                            "\(name) при \(intensity): светимость \(luminance)")
                }
            }
        }
    }

    /// На светлой теме порог ничего не трогает: там фон белый, и поднимать
    /// светимость значит выцвести.
    @Test func theLightThemeKeepsTheChosenColour() {
        let plain = Color(hex: 0x8B4DFF)
        let floored = plain.liftedOnDark()
        #expect(resolved(floored, dark: false).luminance == plain.luminance)
        #expect(resolved(floored, dark: true).luminance > plain.luminance)
    }

    /// Светлым цветам порог не нужен — их не поднимают.
    @Test func brightColoursAreLeftAlone() {
        let mint = Color(hex: 0x00C892)
        #expect(mint.luminance > Palette.darkLuminanceFloor)
        #expect(mint.lifted(toLuminance: Palette.darkLuminanceFloor).luminance == mint.luminance)
    }

    /// Насыщенность вне допустимых границ зажимается — в том числе та, что
    /// пришла из общего контейнера группы к виджету.
    @Test func storedIntensityIsClamped() {
        let defaults = UserDefaults(suiteName: "palette-tests")
        defaults?.removePersistentDomain(forName: "palette-tests")
        defaults?.set(4.2, forKey: PaletteIntensity.key)
        #expect(PaletteIntensity.current(groupDefaults: defaults) == PaletteIntensity.range.upperBound)
        defaults?.set(0.1, forKey: PaletteIntensity.key)
        #expect(PaletteIntensity.current(groupDefaults: defaults) == PaletteIntensity.range.lowerBound)
        defaults?.removePersistentDomain(forName: "palette-tests")
        #expect(PaletteIntensity.current(groupDefaults: defaults) == PaletteIntensity.standard)
    }
}
