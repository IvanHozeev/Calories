import Foundation
import SwiftData

/// Модель SwiftData. Встроенные продукты (FoodDatabase.items) создаются как обычные
/// объекты в памяти и никогда не вставляются в контекст — не персистентны и не должны быть.
/// Пользовательские продукты (CalorieStore.customFoods) вставляются в контекст и хранятся в базе.
@Model
final class FoodItem: Identifiable {
    var id: UUID
    var name: String
    var caloriesPer100g: Int
    var protein: Double
    var fat: Double
    var carbs: Double
    var defaultGrams: Double = 100
    /// Значение по умолчанию обязательно: без него SwiftData не смигрирует
    /// уже сохранённые продукты, а они у пользователя есть.
    var category: String = FoodCategory.other.rawValue

    init(id: UUID = UUID(), name: String, caloriesPer100g: Int, protein: Double, fat: Double, carbs: Double, defaultGrams: Double = 100, category: FoodCategory = .other) {
        self.id = id
        self.name = name
        self.caloriesPer100g = caloriesPer100g
        self.protein = protein
        self.fat = fat
        self.carbs = carbs
        self.defaultGrams = defaultGrams
        self.category = category.rawValue
    }

    var foodCategory: FoodCategory {
        get { FoodCategory(rawValue: category) ?? .other }
        set { category = newValue.rawValue }
    }

    var macrosPer100g: Macros {
        Macros(protein: protein, fat: fat, carbs: carbs)
    }
}

enum FoodDatabase {
    static let items: [FoodItem] = [
        // Фрукты
        FoodItem(name: String(localized: "Яблоко"), caloriesPer100g: 52, protein: 0.3, fat: 0.2, carbs: 14, category: .produce),
        FoodItem(name: String(localized: "Банан"), caloriesPer100g: 89, protein: 1.1, fat: 0.3, carbs: 23, category: .produce),
        FoodItem(name: String(localized: "Апельсин"), caloriesPer100g: 47, protein: 0.9, fat: 0.1, carbs: 12, category: .produce),
        FoodItem(name: String(localized: "Груша"), caloriesPer100g: 57, protein: 0.4, fat: 0.1, carbs: 15, category: .produce),
        FoodItem(name: String(localized: "Виноград"), caloriesPer100g: 69, protein: 0.6, fat: 0.2, carbs: 18, category: .produce),
        FoodItem(name: String(localized: "Клубника"), caloriesPer100g: 32, protein: 0.7, fat: 0.3, carbs: 8, category: .produce),
        FoodItem(name: String(localized: "Арбуз"), caloriesPer100g: 30, protein: 0.6, fat: 0.2, carbs: 8, category: .produce),
        FoodItem(name: String(localized: "Персик"), caloriesPer100g: 39, protein: 0.9, fat: 0.3, carbs: 10, category: .produce),
        FoodItem(name: String(localized: "Абрикос"), caloriesPer100g: 48, protein: 1.4, fat: 0.4, carbs: 11, category: .produce),
        FoodItem(name: String(localized: "Манго"), caloriesPer100g: 60, protein: 0.8, fat: 0.4, carbs: 15, category: .produce),
        FoodItem(name: String(localized: "Киви"), caloriesPer100g: 61, protein: 1.1, fat: 0.5, carbs: 15, category: .produce),
        FoodItem(name: String(localized: "Авокадо"), caloriesPer100g: 160, protein: 2.0, fat: 15.0, carbs: 9, category: .produce),

        // Овощи
        FoodItem(name: String(localized: "Огурец"), caloriesPer100g: 16, protein: 0.7, fat: 0.1, carbs: 3.6, category: .produce),
        FoodItem(name: String(localized: "Помидор"), caloriesPer100g: 18, protein: 0.9, fat: 0.2, carbs: 3.9, category: .produce),
        FoodItem(name: String(localized: "Морковь"), caloriesPer100g: 41, protein: 0.9, fat: 0.2, carbs: 10, category: .produce),
        FoodItem(name: String(localized: "Картофель варёный"), caloriesPer100g: 87, protein: 2.0, fat: 0.1, carbs: 20, category: .produce),
        FoodItem(name: String(localized: "Брокколи"), caloriesPer100g: 34, protein: 2.8, fat: 0.4, carbs: 7, category: .produce),
        FoodItem(name: String(localized: "Капуста белокочанная"), caloriesPer100g: 25, protein: 1.3, fat: 0.1, carbs: 6, category: .produce),
        FoodItem(name: String(localized: "Лук репчатый"), caloriesPer100g: 40, protein: 1.1, fat: 0.1, carbs: 9, category: .produce),
        FoodItem(name: String(localized: "Болгарский перец"), caloriesPer100g: 27, protein: 1.0, fat: 0.3, carbs: 6, category: .produce),
        FoodItem(name: String(localized: "Шпинат"), caloriesPer100g: 23, protein: 2.9, fat: 0.4, carbs: 3.6, category: .produce),

        // Грибы. Значения для сырых: при жарке масло меняет калорийность в разы,
        // поэтому жареные — это уже свой продукт, а не поправка к этому.
        FoodItem(name: String(localized: "Шампиньоны"), caloriesPer100g: 22, protein: 3.1, fat: 0.3, carbs: 3.3, category: .mushrooms),
        FoodItem(name: String(localized: "Вешенки"), caloriesPer100g: 33, protein: 3.3, fat: 0.4, carbs: 6.1, category: .mushrooms),
        FoodItem(name: String(localized: "Белый гриб"), caloriesPer100g: 34, protein: 3.7, fat: 1.7, carbs: 3.3, category: .mushrooms),
        FoodItem(name: String(localized: "Лисички"), caloriesPer100g: 38, protein: 1.5, fat: 0.5, carbs: 6.9, category: .mushrooms),

        // Крупы и хлеб
        FoodItem(name: String(localized: "Рис варёный"), caloriesPer100g: 130, protein: 2.7, fat: 0.3, carbs: 28, category: .grains),
        FoodItem(name: String(localized: "Гречка варёная"), caloriesPer100g: 110, protein: 4.2, fat: 1.1, carbs: 21, category: .grains),
        FoodItem(name: String(localized: "Овсянка на воде"), caloriesPer100g: 68, protein: 2.5, fat: 1.5, carbs: 12, category: .grains),
        FoodItem(name: String(localized: "Хлеб белый"), caloriesPer100g: 265, protein: 9.0, fat: 3.2, carbs: 49, category: .grains),
        FoodItem(name: String(localized: "Хлеб ржаной"), caloriesPer100g: 210, protein: 6.6, fat: 1.2, carbs: 40, category: .grains),
        FoodItem(name: String(localized: "Макароны варёные"), caloriesPer100g: 131, protein: 5.0, fat: 1.1, carbs: 25, category: .grains),
        FoodItem(name: String(localized: "Киноа варёная"), caloriesPer100g: 120, protein: 4.4, fat: 1.9, carbs: 21, category: .grains),

        // Белковые продукты
        FoodItem(name: String(localized: "Куриная грудка варёная"), caloriesPer100g: 165, protein: 31.0, fat: 3.6, carbs: 0, category: .meat),
        FoodItem(name: String(localized: "Куриное бедро"), caloriesPer100g: 209, protein: 26.0, fat: 10.9, carbs: 0, category: .meat),
        FoodItem(name: String(localized: "Говядина"), caloriesPer100g: 250, protein: 26.0, fat: 15.0, carbs: 0, category: .meat),
        FoodItem(name: String(localized: "Свинина"), caloriesPer100g: 242, protein: 27.0, fat: 14.0, carbs: 0, category: .meat),
        FoodItem(name: String(localized: "Лосось"), caloriesPer100g: 208, protein: 20.0, fat: 13.0, carbs: 0, category: .fish),
        FoodItem(name: String(localized: "Тунец консервированный"), caloriesPer100g: 116, protein: 26.0, fat: 0.8, carbs: 0, category: .fish),
        FoodItem(name: String(localized: "Яйцо куриное"), caloriesPer100g: 155, protein: 13.0, fat: 11.0, carbs: 1.1, category: .dairy),
        FoodItem(name: String(localized: "Творог 5%"), caloriesPer100g: 121, protein: 18.0, fat: 5.0, carbs: 3.4, category: .dairy),
        FoodItem(name: String(localized: "Творог обезжиренный"), caloriesPer100g: 71, protein: 18.0, fat: 0.6, carbs: 3.0, category: .dairy),
        FoodItem(name: String(localized: "Йогурт натуральный"), caloriesPer100g: 60, protein: 3.5, fat: 3.2, carbs: 4.7, category: .dairy),
        FoodItem(name: String(localized: "Молоко 3.2%"), caloriesPer100g: 60, protein: 2.9, fat: 3.2, carbs: 4.7, category: .dairy),
        FoodItem(name: String(localized: "Сыр твёрдый"), caloriesPer100g: 350, protein: 25.0, fat: 29.0, carbs: 0, category: .dairy),
        FoodItem(name: String(localized: "Тофу"), caloriesPer100g: 76, protein: 8.0, fat: 4.8, carbs: 1.9, category: .legumes),

        // Бобовые
        FoodItem(name: String(localized: "Чечевица варёная"), caloriesPer100g: 116, protein: 9.0, fat: 0.4, carbs: 20, category: .legumes),
        FoodItem(name: String(localized: "Фасоль варёная"), caloriesPer100g: 127, protein: 8.7, fat: 0.5, carbs: 23, category: .legumes),
        FoodItem(name: String(localized: "Нут варёный"), caloriesPer100g: 164, protein: 8.9, fat: 2.6, carbs: 27, category: .legumes),

        // Орехи и жиры
        FoodItem(name: String(localized: "Миндаль"), caloriesPer100g: 579, protein: 21.0, fat: 50.0, carbs: 22, category: .fats),
        FoodItem(name: String(localized: "Грецкий орех"), caloriesPer100g: 654, protein: 15.0, fat: 65.0, carbs: 14, category: .fats),
        FoodItem(name: String(localized: "Арахис"), caloriesPer100g: 567, protein: 26.0, fat: 49.0, carbs: 16, category: .fats),
        FoodItem(name: String(localized: "Оливковое масло"), caloriesPer100g: 884, protein: 0, fat: 100.0, carbs: 0, category: .fats),
        FoodItem(name: String(localized: "Масло сливочное"), caloriesPer100g: 717, protein: 0.9, fat: 81.0, carbs: 0.1, category: .fats),

        // Разное
        FoodItem(name: String(localized: "Мёд"), caloriesPer100g: 304, protein: 0.3, fat: 0, carbs: 82, category: .sweets),
        FoodItem(name: String(localized: "Сахар"), caloriesPer100g: 387, protein: 0, fat: 0, carbs: 100, category: .sweets),
        FoodItem(name: String(localized: "Шоколад молочный"), caloriesPer100g: 535, protein: 7.7, fat: 30.0, carbs: 59, category: .sweets),
        FoodItem(name: String(localized: "Кофе чёрный"), caloriesPer100g: 2, protein: 0.1, fat: 0, carbs: 0, category: .drinks),
        FoodItem(name: String(localized: "Кофе с молоком"), caloriesPer100g: 40, protein: 1.0, fat: 1.5, carbs: 3, category: .drinks),
        FoodItem(name: String(localized: "Апельсиновый сок"), caloriesPer100g: 45, protein: 0.7, fat: 0.2, carbs: 10.4, category: .drinks),
        FoodItem(name: String(localized: "Кола"), caloriesPer100g: 42, protein: 0, fat: 0, carbs: 10.6, category: .drinks),
        FoodItem(name: String(localized: "Пиво"), caloriesPer100g: 43, protein: 0.5, fat: 0, carbs: 3.6, category: .drinks)
    ]
    .sorted { $0.name < $1.name }
}
