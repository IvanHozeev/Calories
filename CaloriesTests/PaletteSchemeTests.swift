import Testing
import SwiftUI
import UIKit
@testable import Calories

/// Схемы палитры: каждая держит правила, на которых палитра и строилась.
@MainActor
struct PaletteSchemeTests {
    private func resolved(_ color: Color, dark: Bool) -> Color {
        let traits = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
        return Color(uiColor: UIColor(color).resolvedColor(with: traits))
    }

    private func contrast(_ a: Color, _ b: Color) -> Double {
        let la = a.luminance, lb = b.luminance
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// Расстояние по кругу тонов, в градусах.
    private func hueDistance(_ a: Color, _ b: Color) throws -> Double {
        let ha = try #require(a.hsb).hue * 360, hb = try #require(b.hsb).hue * 360
        let delta = abs(ha - hb).truncatingRemainder(dividingBy: 360)
        return min(delta, 360 - delta)
    }

    /// Дуга калорий не сливается ни с одним макросом: так сливались чистое
    /// индиго и сирень углеводов.
    ///
    /// «Свежесть» — прежний вид как есть, и её мята стоит к бирюзе белка
    /// ближе (около 16°): так приложение выглядело всегда, и эту схему
    /// выбирают именно ради прежнего вида. Новые схемы правило держат.
    @Test func theCaloriesArcStaysClearOfEveryMacro() throws {
        let macros = [("белок", Palette.protein), ("жиры", Palette.fat), ("углеводы", Palette.carbs)]
        for scheme in PaletteScheme.allCases where scheme != .fresh {
            for (name, ramp) in macros {
                let distance = try hueDistance(scheme.kcal.pale[1], ramp.pale[1])
                #expect(distance >= 25, "\(scheme): до цвета «\(name)» \(Int(distance))°")
            }
        }
    }

    /// Подпись главной кнопки читается в каждой схеме и в обеих темах.
    @Test func theMainButtonLabelReadsInEverySchemeAndTheme() {
        for scheme in PaletteScheme.allCases {
            for dark in [false, true] {
                let ratio = contrast(resolved(scheme.brand, dark: dark), resolved(scheme.onBrand, dark: dark))
                #expect(ratio >= 4.5, "\(scheme), \(dark ? "тёмная" : "светлая"): \(ratio)")
            }
        }
    }

    /// Дуга калорий не тонет в тёмной теме ни в одной схеме.
    @Test func noCaloriesArcSinksIntoTheDarkTheme() {
        for scheme in PaletteScheme.allCases {
            for intensity in [PaletteIntensity.range.lowerBound, PaletteIntensity.range.upperBound] {
                for color in Palette.colors(scheme.kcal, intensity: intensity) {
                    let luminance = resolved(color, dark: true).luminance
                    #expect(luminance >= Palette.darkLuminanceFloor - 0.01, "\(scheme) при \(intensity): \(luminance)")
                }
            }
        }
    }

    /// Готовые цвета лежат в кэше по имени рампы: у двух схем имена разные,
    /// иначе после смены схемы кольцо осталось бы прежнего цвета.
    @Test func everySchemeCachesItsArcUnderItsOwnName() {
        let names = Set(PaletteScheme.allCases.map(\.kcal.name))
        #expect(names.count == PaletteScheme.allCases.count)
    }

    /// Ничего не выбрано или выбрано несуществующее — индиго.
    @Test func anUnknownSchemeFallsBackToTheStandard() {
        let store = PaletteScheme.store
        let saved = store?.string(forKey: PaletteScheme.key)
        defer { store?.set(saved, forKey: PaletteScheme.key) }
        store?.removeObject(forKey: PaletteScheme.key)
        #expect(PaletteScheme.current == .trust)
        store?.set("neon", forKey: PaletteScheme.key)
        #expect(PaletteScheme.current == .trust)
        store?.set(PaletteScheme.warm.rawValue, forKey: PaletteScheme.key)
        #expect(PaletteScheme.current == .warm)
    }
}
