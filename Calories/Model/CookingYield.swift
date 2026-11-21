import Foundation

/// Сухой и готовый продукт.
///
/// Человек вводит данные на сто грамм сухого, взвешивает, сколько получилось
/// готового из такого-то сухого, — и всё. Никаких справочных коэффициентов и
/// подстановок за него: коэффициент — только то, что он сам измерил.
///
/// Арифметика одна: при варке калории и макросы не меняются, меняется вес.
/// Значит на сто грамм готового их столько, сколько на сто грамм сухого,
/// поделённое на коэффициент «во сколько раз потяжелело».
enum CookingYield {
    /// Правдоподобный коэффициент: ниже — почти наверняка перепутаны местами
    /// два веса, выше — опечатка.
    static let allowed: ClosedRange<Double> = 0.2...6.0

    /// Коэффициент по двум весам: из `dry` сухого вышло `cooked` готового.
    static func factor(dry: Double, cooked: Double) -> Double? {
        guard dry > 0, cooked > 0 else { return nil }
        let value = cooked / dry
        return allowed.contains(value) ? value : nil
    }

    /// Калории и макросы на сто грамм готового.
    static func cookedPer100g(calories: Int, macros: Macros, factor: Double) -> (calories: Int, macros: Macros) {
        guard factor > 0 else { return (calories, macros) }
        return (Int((Double(calories) / factor).rounded()),
                Macros(protein: macros.protein / factor, fat: macros.fat / factor, carbs: macros.carbs / factor))
    }
}

extension FoodItem {
    /// Сто грамм готового продукта — если человек измерил, сколько из сухого
    /// выходит готового. nil — продукт без такого измерения.
    var cookedPer100g: (calories: Int, macros: Macros)? {
        guard !isPerUnit, let factor = cookingYield, CookingYield.allowed.contains(factor) else { return nil }
        return CookingYield.cookedPer100g(calories: caloriesPer100g, macros: macrosPer100g, factor: factor)
    }
}
