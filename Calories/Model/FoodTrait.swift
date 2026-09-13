import SwiftUI

/// Свойство продукта, которое стоит знать на сушке, кроме самих калорий.
///
/// Считается только по тому, что в базе есть у каждого продукта: калориям и
/// макросам на 100 г. Сахара и клетчатки в базе нет, поэтому «легко переесть»
/// — не формальный критерий гипервкусной еды (там нужен сахар), а его
/// приближение: много жира вместе с большим количеством углеводов при высокой
/// калорийности. Шоколад, выпечку, мороженое и чипсы оно ловит; орехи (почти
/// один жир) и крупы (почти одни углеводы) — нет.
enum FoodTrait: String, CaseIterable, Identifiable {
    /// До 30 ккал на 100 г: огурцы, листья, кабачок.
    case almostNoCalories
    /// До 60 ккал на 100 г: капуста, ягоды, большинство фруктов, супы.
    case eatALot
    /// Белок — не меньше половины калорий: на его переваривание уходит
    /// четверть его же энергии, втрое больше, чем у жира и углеводов.
    case highThermicEffect
    /// Жирное вместе с углеводным и калорийное — такое легко переесть.
    case easyToOvereat

    var id: String { rawValue }

    static let almostNoCaloriesLimit = 30
    static let eatALotLimit = 60
    static let thermicProteinShare = 0.5
    static let thermicMinimumProtein = 10.0
    static let overeatMacroShare = 0.35
    static let overeatMinimumCalories = 350

    var title: String {
        switch self {
        case .almostNoCalories:  return String(localized: "Почти без калорий")
        case .eatALot:           return String(localized: "Можно много")
        case .highThermicEffect: return String(localized: "Термический эффект")
        case .easyToOvereat:     return String(localized: "Легко переесть")
        }
    }

    var explanation: String {
        switch self {
        case .almostNoCalories:
            return String(localized: "Меньше 30 ккал на 100 г: объём и сытость почти даром.")
        case .eatALot:
            return String(localized: "Меньше 60 ккал на 100 г: можно есть много и остаться в норме.")
        case .highThermicEffect:
            return String(localized: "Больше половины калорий — белок. На его переваривание уходит около четверти его энергии.")
        case .easyToOvereat:
            return String(localized: "Жирное вместе с углеводным и калорийное: такое съедается незаметно и не насыщает.")
        }
    }

    var symbol: String {
        switch self {
        case .almostNoCalories:  return "leaf.fill"
        case .eatALot:           return "leaf"
        case .highThermicEffect: return "flame"
        case .easyToOvereat:     return "exclamationmark.triangle"
        }
    }

    var color: Color {
        switch self {
        case .almostNoCalories, .eatALot: return .green
        case .highThermicEffect:          return .orange
        case .easyToOvereat:              return .red
        }
    }

    /// Минус, а не плюс: показывается предупреждением.
    var isWarning: Bool { self == .easyToOvereat }

    /// Свойства продукта по калориям и макросам на 100 г.
    ///
    /// Напитки не получают «можно много»: жидкие калории не насыщают, и
    /// сладкая газировка с её 42 ккал выглядела бы полезной находкой.
    static func traits(caloriesPer100g kcal: Int, macros: Macros, category: FoodCategory? = nil) -> [FoodTrait] {
        guard kcal > 0 || macros.protein + macros.fat + macros.carbs > 0 else { return [] }
        var result: [FoodTrait] = []

        if category != .drinks {
            if kcal <= almostNoCaloriesLimit {
                result.append(.almostNoCalories)
            } else if kcal <= eatALotLimit {
                result.append(.eatALot)
            }
        }

        let proteinKcal = macros.protein * MacroTargets.kcalPerProteinGram
        let fatKcal = macros.fat * MacroTargets.kcalPerFatGram
        let carbKcal = macros.carbs * MacroTargets.kcalPerCarbGram
        let total = proteinKcal + fatKcal + carbKcal
        guard total > 0 else { return result }

        if proteinKcal / total >= thermicProteinShare, macros.protein >= thermicMinimumProtein {
            result.append(.highThermicEffect)
        }
        if kcal >= overeatMinimumCalories,
           fatKcal / total >= overeatMacroShare, carbKcal / total >= overeatMacroShare {
            result.append(.easyToOvereat)
        }
        return result
    }
}

extension FoodItem {
    var traits: [FoodTrait] {
        FoodTrait.traits(caloriesPer100g: caloriesPer100g, macros: macrosPer100g, category: foodCategory)
    }
}

extension Dish {
    var traits: [FoodTrait] {
        FoodTrait.traits(caloriesPer100g: caloriesPer100g, macros: macrosPer100g)
    }
}
