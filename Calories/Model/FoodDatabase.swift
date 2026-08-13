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

    init(id: UUID = UUID(), name: String, caloriesPer100g: Int, protein: Double, fat: Double, carbs: Double) {
        self.id = id
        self.name = name
        self.caloriesPer100g = caloriesPer100g
        self.protein = protein
        self.fat = fat
        self.carbs = carbs
    }

    var macrosPer100g: Macros {
        Macros(protein: protein, fat: fat, carbs: carbs)
    }
}

enum FoodDatabase {
    static let items: [FoodItem] = [
        // Фрукты
        FoodItem(name: "Яблоко", caloriesPer100g: 52, protein: 0.3, fat: 0.2, carbs: 14),
        FoodItem(name: "Банан", caloriesPer100g: 89, protein: 1.1, fat: 0.3, carbs: 23),
        FoodItem(name: "Апельсин", caloriesPer100g: 47, protein: 0.9, fat: 0.1, carbs: 12),
        FoodItem(name: "Груша", caloriesPer100g: 57, protein: 0.4, fat: 0.1, carbs: 15),
        FoodItem(name: "Виноград", caloriesPer100g: 69, protein: 0.6, fat: 0.2, carbs: 18),
        FoodItem(name: "Клубника", caloriesPer100g: 32, protein: 0.7, fat: 0.3, carbs: 8),
        FoodItem(name: "Арбуз", caloriesPer100g: 30, protein: 0.6, fat: 0.2, carbs: 8),
        FoodItem(name: "Персик", caloriesPer100g: 39, protein: 0.9, fat: 0.3, carbs: 10),
        FoodItem(name: "Абрикос", caloriesPer100g: 48, protein: 1.4, fat: 0.4, carbs: 11),
        FoodItem(name: "Манго", caloriesPer100g: 60, protein: 0.8, fat: 0.4, carbs: 15),
        FoodItem(name: "Киви", caloriesPer100g: 61, protein: 1.1, fat: 0.5, carbs: 15),
        FoodItem(name: "Авокадо", caloriesPer100g: 160, protein: 2.0, fat: 15.0, carbs: 9),

        // Овощи
        FoodItem(name: "Огурец", caloriesPer100g: 16, protein: 0.7, fat: 0.1, carbs: 3.6),
        FoodItem(name: "Помидор", caloriesPer100g: 18, protein: 0.9, fat: 0.2, carbs: 3.9),
        FoodItem(name: "Морковь", caloriesPer100g: 41, protein: 0.9, fat: 0.2, carbs: 10),
        FoodItem(name: "Картофель варёный", caloriesPer100g: 87, protein: 2.0, fat: 0.1, carbs: 20),
        FoodItem(name: "Брокколи", caloriesPer100g: 34, protein: 2.8, fat: 0.4, carbs: 7),
        FoodItem(name: "Капуста белокочанная", caloriesPer100g: 25, protein: 1.3, fat: 0.1, carbs: 6),
        FoodItem(name: "Лук репчатый", caloriesPer100g: 40, protein: 1.1, fat: 0.1, carbs: 9),
        FoodItem(name: "Болгарский перец", caloriesPer100g: 27, protein: 1.0, fat: 0.3, carbs: 6),
        FoodItem(name: "Шпинат", caloriesPer100g: 23, protein: 2.9, fat: 0.4, carbs: 3.6),

        // Крупы и хлеб
        FoodItem(name: "Рис варёный", caloriesPer100g: 130, protein: 2.7, fat: 0.3, carbs: 28),
        FoodItem(name: "Гречка варёная", caloriesPer100g: 110, protein: 4.2, fat: 1.1, carbs: 21),
        FoodItem(name: "Овсянка на воде", caloriesPer100g: 68, protein: 2.5, fat: 1.5, carbs: 12),
        FoodItem(name: "Хлеб белый", caloriesPer100g: 265, protein: 9.0, fat: 3.2, carbs: 49),
        FoodItem(name: "Хлеб ржаной", caloriesPer100g: 210, protein: 6.6, fat: 1.2, carbs: 40),
        FoodItem(name: "Макароны варёные", caloriesPer100g: 131, protein: 5.0, fat: 1.1, carbs: 25),
        FoodItem(name: "Киноа варёная", caloriesPer100g: 120, protein: 4.4, fat: 1.9, carbs: 21),

        // Белковые продукты
        FoodItem(name: "Куриная грудка варёная", caloriesPer100g: 165, protein: 31.0, fat: 3.6, carbs: 0),
        FoodItem(name: "Куриное бедро", caloriesPer100g: 209, protein: 26.0, fat: 10.9, carbs: 0),
        FoodItem(name: "Говядина", caloriesPer100g: 250, protein: 26.0, fat: 15.0, carbs: 0),
        FoodItem(name: "Свинина", caloriesPer100g: 242, protein: 27.0, fat: 14.0, carbs: 0),
        FoodItem(name: "Лосось", caloriesPer100g: 208, protein: 20.0, fat: 13.0, carbs: 0),
        FoodItem(name: "Тунец консервированный", caloriesPer100g: 116, protein: 26.0, fat: 0.8, carbs: 0),
        FoodItem(name: "Яйцо куриное", caloriesPer100g: 155, protein: 13.0, fat: 11.0, carbs: 1.1),
        FoodItem(name: "Творог 5%", caloriesPer100g: 121, protein: 18.0, fat: 5.0, carbs: 3.4),
        FoodItem(name: "Творог обезжиренный", caloriesPer100g: 71, protein: 18.0, fat: 0.6, carbs: 3.0),
        FoodItem(name: "Йогурт натуральный", caloriesPer100g: 60, protein: 3.5, fat: 3.2, carbs: 4.7),
        FoodItem(name: "Молоко 3.2%", caloriesPer100g: 60, protein: 2.9, fat: 3.2, carbs: 4.7),
        FoodItem(name: "Сыр твёрдый", caloriesPer100g: 350, protein: 25.0, fat: 29.0, carbs: 0),
        FoodItem(name: "Тофу", caloriesPer100g: 76, protein: 8.0, fat: 4.8, carbs: 1.9),

        // Бобовые
        FoodItem(name: "Чечевица варёная", caloriesPer100g: 116, protein: 9.0, fat: 0.4, carbs: 20),
        FoodItem(name: "Фасоль варёная", caloriesPer100g: 127, protein: 8.7, fat: 0.5, carbs: 23),
        FoodItem(name: "Нут варёный", caloriesPer100g: 164, protein: 8.9, fat: 2.6, carbs: 27),

        // Орехи и жиры
        FoodItem(name: "Миндаль", caloriesPer100g: 579, protein: 21.0, fat: 50.0, carbs: 22),
        FoodItem(name: "Грецкий орех", caloriesPer100g: 654, protein: 15.0, fat: 65.0, carbs: 14),
        FoodItem(name: "Арахис", caloriesPer100g: 567, protein: 26.0, fat: 49.0, carbs: 16),
        FoodItem(name: "Оливковое масло", caloriesPer100g: 884, protein: 0, fat: 100.0, carbs: 0),
        FoodItem(name: "Масло сливочное", caloriesPer100g: 717, protein: 0.9, fat: 81.0, carbs: 0.1),

        // Разное
        FoodItem(name: "Мёд", caloriesPer100g: 304, protein: 0.3, fat: 0, carbs: 82),
        FoodItem(name: "Сахар", caloriesPer100g: 387, protein: 0, fat: 0, carbs: 100),
        FoodItem(name: "Шоколад молочный", caloriesPer100g: 535, protein: 7.7, fat: 30.0, carbs: 59),
        FoodItem(name: "Кофе чёрный", caloriesPer100g: 2, protein: 0.1, fat: 0, carbs: 0),
        FoodItem(name: "Кофе с молоком", caloriesPer100g: 40, protein: 1.0, fat: 1.5, carbs: 3),
        FoodItem(name: "Апельсиновый сок", caloriesPer100g: 45, protein: 0.7, fat: 0.2, carbs: 10.4),
        FoodItem(name: "Кола", caloriesPer100g: 42, protein: 0, fat: 0, carbs: 10.6),
        FoodItem(name: "Пиво", caloriesPer100g: 43, protein: 0.5, fat: 0, carbs: 3.6)
    ]
    .sorted { $0.name < $1.name }
}
