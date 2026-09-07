import SwiftUI

/// Продукт встроенной базы. Только для чтения: строка каталога лежит файлом
/// в бандле, изменить её нельзя.
///
/// Структура намеренно та же, что у редактора своего продукта: название,
/// данные на сто грамм с полоской БЖУ, витамины, порция. Один и тот же продукт
/// не должен выглядеть по-разному в зависимости от того, чей он.
struct CatalogFoodView: View {
    let food: FoodItem

    @State private var grams: Double

    init(food: FoodItem) {
        self.food = food
        _grams = State(initialValue: food.defaultGrams > 0 ? food.defaultGrams : 100)
    }

    private var portionCalories: Int {
        Int((Double(food.caloriesPer100g) * grams / 100).rounded())
    }

    private var portionMacros: Macros { food.macrosPer100g.scaled(by: grams) }

    var body: some View {
        List {
            Section {
                // Обычная строка, а не LabeledContent с Label внутри: там иконка
                // растягивалась во всю доступную ширину и выглядела как пустой
                // белый квадрат в половину экрана.
                HStack {
                    Text("Категория")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: food.foodCategory.icon)
                        .imageScale(.medium)
                        .foregroundStyle(.secondary)
                    Text(food.foodCategory.title)
                }
            }

            Section {
                row("Калории", value: "\(food.caloriesPer100g)", unit: "ккал")
                row("Белки", value: String(format: "%g", food.protein), unit: "г")
                row("Жиры", value: String(format: "%g", food.fat), unit: "г")
                row("Углеводы", value: String(format: "%g", food.carbs), unit: "г")

                MacroSplitBar(macros: food.macrosPer100g)
                    .padding(.vertical, 4)
            } header: {
                Text("Данные на 100 г")
            }

            if !food.micronutrients.isEmpty {
                Section {
                    ForEach(Micronutrient.allCases) { nutrient in
                        // Ноль означает «этого в продукте нет». Строка с нулём
                        // ничего не сообщает и только удлиняет список.
                        if let amount = food.micronutrients[nutrient], amount > 0 {
                            nutrientRow(nutrient, per100g: amount)
                        }
                    }
                } header: {
                    Text("Витамины и минералы")
                } footer: {
                    Text("Доля суточной нормы в порции. У натрия это доля потолка, а не цели.")
                }
            }

            Section {
                Stepper(value: $grams, in: 5...2000, step: 5) {
                    HStack {
                        Text(verbatim: "\(Int(grams))")
                            .font(.body.weight(.medium))
                            .monospacedDigit()
                        Text("г")
                            .foregroundStyle(.secondary)
                    }
                }
                LabeledContent("В порции") {
                    Text(verbatim: "\(portionCalories) \(String(localized: "ккал"))")
                        .font(.body.weight(.medium))
                        .monospacedDigit()
                }
                MacroTags(macros: portionMacros)
            } header: {
                Text("Порция по умолчанию")
            }
        }
        .glassRow()
        .listStyle(.insetGrouped)
        .scrollIndicators(.hidden)
        .navigationTitle(food.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ title: LocalizedStringKey, value: String, unit: LocalizedStringKey) -> some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                Text(verbatim: value)
                    .monospacedDigit()
                Text(unit)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func nutrientRow(_ nutrient: Micronutrient, per100g: Double) -> some View {
        let amount = per100g * grams / 100
        let share = amount / nutrient.dailyValue
        return LabeledContent(nutrient.title) {
            HStack(spacing: 6) {
                Text(verbatim: formatted(amount, nutrient))
                    .monospacedDigit()
                Text(verbatim: "\(Int((share * 100).rounded()))%")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(nutrient.isCeiling ? .orange : .secondary)
                    .monospacedDigit()
            }
        }
    }

    /// Микронутриенты различаются на три порядка: B12 в твороге — 0.4 мкг,
    /// калий в шпинате — 558 мг. Один формат на оба даёт либо «0 мкг», либо
    /// «558.0 мг».
    private func formatted(_ amount: Double, _ nutrient: Micronutrient) -> String {
        let digits = amount < 10 ? 1 : 0
        return String(format: "%.\(digits)f \(nutrient.unit)", amount)
    }
}
