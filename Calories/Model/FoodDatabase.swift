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
    /// Витамины и минералы на 100 г, если источник их дал. Хранится JSON-ом:
    /// набор веществ со временем меняется, а колонка на каждое превратила бы
    /// любое добавление в миграцию схемы.
    var micronutrientsData: Data?

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

    /// Пусто — значит неизвестно, а не «ноль»: на нулях день насчитал бы
    /// дефицит там, где данных просто нет.
    var micronutrients: Micronutrients {
        get {
            guard let micronutrientsData,
                  let decoded = try? JSONDecoder().decode(Micronutrients.self, from: micronutrientsData)
            else { return Micronutrients() }
            return decoded
        }
        set { micronutrientsData = try? JSONEncoder().encode(newValue) }
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
    /// Встроенная база продуктов.
    ///
    /// Раньше эти продукты были литералами прямо здесь, и это упиралось в
    /// потолок: каждое название приходилось заводить в строковый каталог и
    /// переводить на семь языков вручную, а на двух тысячах позиций это
    /// четырнадцать тысяч переводов. Поэтому данные уехали в `FoodCatalog`,
    /// который собирается скриптом и лежит в бандле файлом.
    ///
    /// `FoodItem` создаётся лениво и один раз: это модель SwiftData, и держать
    /// её объекты имеет смысл только там, где нужен именно `FoodItem` — списки
    /// и экраны деталей. Поиск идёт по `FoodCatalog` и объектов не создаёт.
    @MainActor static let items: [FoodItem] = FoodCatalog.all.map(makeItem)

    /// Продукты по идентификатору каталога. Нужен для того, чтобы поиск отдавал
    /// те же самые объекты, а не свежие копии: `FoodItem` опознаётся по `id`,
    /// и создавай мы их заново на каждое нажатие клавиши, SwiftUI перестраивал
    /// бы весь список вместо того, чтобы отфильтровать готовый.
    @MainActor private static let itemsByCatalogID: [Int: FoodItem] =
        Dictionary(uniqueKeysWithValues: zip(FoodCatalog.all.map(\.id), items))

    /// Поиск по встроенной базе. Отдельно от `items` намеренно: перебор двух
    /// тысяч названий через `localizedCaseInsensitiveContains` на каждое
    /// нажатие клавиши — это как раз те подтормаживания, которые видно пальцами.
    @MainActor static func search(_ query: String, limit: Int = 60) -> [FoodItem] {
        FoodCatalog.search(query, limit: limit).compactMap { itemsByCatalogID[$0.id] }
    }

    @MainActor private static func makeItem(_ food: CatalogFood) -> FoodItem {
        let item = FoodItem(name: food.localizedName,
                            caloriesPer100g: food.kcal,
                            protein: food.protein,
                            fat: food.fat,
                            carbs: food.carbs,
                            defaultGrams: food.grams ?? 100,
                            category: food.foodCategory)
        let micronutrients = food.micronutrients
        if !micronutrients.isEmpty { item.micronutrients = micronutrients }
        return item
    }
}
