import SwiftUI

/// Строка съеденного за день. Верстка та же, что и в «Рационе» — `FoodRow`:
/// название, вес, макросы цветными тегами, калории справа.
struct EntryRow: View {
    let entry: FoodEntry
    /// Чем запись заметно богата. Считает стор — строке неоткуда знать состав.
    var micros: [Micronutrient] = []
    /// Значки категорий частей приёма по имени части: у записи в дневнике
    /// категорий нет, они остались в базе продуктов.
    var partIcons: (String) -> [String] = { _ in [] }

    /// Вес порции.
    ///
    /// У приёма из нескольких продуктов своего веса нет — он лежит у
    /// составляющих, и раньше строка молчала о весе вовсе. Складываем их, но
    /// только когда вес известен у всех: сумма двух из трёх — не вес приёма,
    /// а полуправда.
    private var portionText: String? {
        if let grams = entry.grams, grams > 0 {
            return String(format: "%.0f \(String(localized: "г"))", grams)
        }
        let parts = entry.components
        guard !parts.isEmpty, parts.allSatisfy({ ($0.grams ?? 0) > 0 }) else { return nil }
        let total = parts.reduce(0.0) { $0 + ($1.grams ?? 0) }
        return String(format: "%.0f \(String(localized: "г"))", total)
    }

    /// Плотность калорий на сто грамм записи: для веса шрифта цифры калорий.
    /// Чем ниже плотность, тем жирнее цифра.
    private var caloriesPer100g: Int? {
        guard let grams = entry.grams, grams > 0 else { return nil }
        return Int(Double(entry.calories) / grams * 100)
    }

    var body: some View {
        FoodRow(
            name: entry.name,
            calories: entry.calories,
            caloriesPer100g: caloriesPer100g,
            portion: portionText ?? "",
            macros: Macros(protein: entry.protein, fat: entry.fat, carbs: entry.carbs),
            icons: [],
            micros: micros,
            offersVitamins: false,
            traits: [],
            parts: entry.components.map {
                .init(name: $0.name,
                      macros: Macros(protein: $0.protein, fat: $0.fat, carbs: $0.carbs),
                      grams: $0.grams,
                      icons: partIcons($0.name))
            }
        )
    }
}
