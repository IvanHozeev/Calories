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
        for scheme in PaletteScheme.allCases where scheme != .fresh {
            for (name, ramp) in [("белок", scheme.protein), ("жиры", scheme.fat), ("углеводы", scheme.carbs)] {
                let distance = try hueDistance(scheme.kcal.pale[1], ramp.pale[1])
                #expect(distance >= 25, "\(scheme): до цвета «\(name)» \(Int(distance))°")
            }
        }
    }

    /// Перебор и недобор не совпадают по тону ни с одним макросом схемы:
    /// состояниям — свои цвета, макросам — свои.
    @Test func missesStayClearOfEveryMacro() throws {
        for scheme in PaletteScheme.allCases {
            for (name, ramp) in [("белок", scheme.protein), ("жиры", scheme.fat), ("углеводы", scheme.carbs)] {
                let distance = try hueDistance(Palette.over.pale[1], ramp.pale[1])
                #expect(distance >= 25, "\(scheme): перебор до цвета «\(name)» \(Int(distance))°")
            }
        }
    }

    /// Ни одна дуга макросов не тонет в тёмной теме ни в одной схеме.
    @Test func noMacroArcSinksIntoTheDarkTheme() {
        for scheme in PaletteScheme.allCases {
            for ramp in [scheme.protein, scheme.fat, scheme.carbs] {
                for intensity in [PaletteIntensity.range.lowerBound, PaletteIntensity.range.upperBound] {
                    for color in Palette.colors(ramp, intensity: intensity) {
                        let luminance = resolved(color, dark: true).luminance
                        #expect(luminance >= Palette.darkLuminanceFloor - 0.01, "\(scheme), \(ramp.name): \(luminance)")
                    }
                }
            }
        }
    }

    /// Сирень остаётся сиренью в каждой схеме, на обоих концах ползунка.
    @Test func lilacStaysLilacInEveryScheme() throws {
        for scheme in PaletteScheme.allCases {
            for intensity in [PaletteIntensity.range.lowerBound, PaletteIntensity.range.upperBound] {
                for color in Palette.colors(scheme.carbs, intensity: intensity) {
                    let hue = try #require(resolved(color, dark: false).hsb).hue * 360
                    #expect(hue >= 255 && hue <= 300, "\(scheme): тон \(Int(hue))°")
                }
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
        // Макросы: у «Свежести» и «Уверенности» одни и те же — и имя одно.
        for kind in [\PaletteScheme.protein, \PaletteScheme.fat, \PaletteScheme.carbs] {
            let byName = Dictionary(grouping: PaletteScheme.allCases) { $0[keyPath: kind].name }
            for (_, schemes) in byName {
                let looks = Set(schemes.map { $0[keyPath: kind].pale.map { "\($0.hsb?.hue ?? -1)" }.joined() })
                #expect(looks.count == 1, "Под одним именем разные цвета: \(schemes)")
            }
        }
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
