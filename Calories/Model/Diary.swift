import Foundation
import SwiftData

// Дневник: что съели и сколько это весило. Макросы, записи, блюда,
// взвешивания и дневные сводки — всё, из чего складывается день.

/// Белки, жиры, углеводы одной величиной.
///
/// `nonisolated`, потому что макросы считает и то, что живёт вне главного
/// актора: состав записи (`EntryComponent`) и разбор ответов источников.
nonisolated struct Macros: Codable, Hashable {
    var protein: Double
    var fat: Double
    var carbs: Double

    static let zero = Macros(protein: 0, fat: 0, carbs: 0)

    static func + (lhs: Macros, rhs: Macros) -> Macros {
        Macros(
            protein: lhs.protein + rhs.protein,
            fat: lhs.fat + rhs.fat,
            carbs: lhs.carbs + rhs.carbs
        )
    }

    func scaled(by grams: Double) -> Macros {
        Macros(
            protein: protein * grams / 100,
            fat: fat * grams / 100,
            carbs: carbs * grams / 100
        )
    }

    /// Макрос, которым продукт богат, — если такой есть.
    ///
    /// Считается по доле калорий, а не граммов: 31 г жира и 58 г углеводов на
    /// граммах выглядят сопоставимо, хотя жир даёт вдвое больше энергии. Порог —
    /// больше половины калорий: ниже продукт смешанный, и красить его в чей-то
    /// цвет значит соврать.
    ///
    /// И второе условие — самого макроса должно быть хотя бы пять граммов. Иначе
    /// огурец выходит «углеводным»: девять десятых его шестнадцати калорий и
    /// правда углеводы, но богатым ими его не назовёшь.
    var leadingKind: MacroKind? {
        let kcal = [
            (MacroKind.protein, protein * MacroTargets.kcalPerProteinGram, protein),
            (MacroKind.fat, fat * MacroTargets.kcalPerFatGram, fat),
            (MacroKind.carbs, carbs * MacroTargets.kcalPerCarbGram, carbs)
        ]
        let total = kcal.reduce(0) { $0 + $1.1 }
        guard total > 0, let top = kcal.max(by: { $0.1 < $1.1 }) else { return nil }
        guard top.1 / total > Self.leadingShare, top.2 >= Self.leadingMinimumGrams else { return nil }
        return top.0
    }

    static let leadingShare = 0.5
    static let leadingMinimumGrams = 5.0
}

/// Единая точка для всех констант макронутриентов — расчётов и UI.
/// Сколько калорий даёт грамм каждого макроса и где проходят их границы.
///
/// `nonisolated` по той же причине, что и `Macros`: по этим числам считают и
/// вне главного актора.
nonisolated enum MacroTargets {
    static let fatPerKg: Double = 0.8
    /// Ниже — уже не диета, а ставка на гормоны. Жёсткая граница: меньше
    /// выставить нельзя.
    static let fatFloorPerKg: Double = 0.5
    /// Выше — жир вытесняет углеводы, а на них работают тренировки. Тоже
    /// жёсткая: для этой аудитории больше полутора граммов на кило не бывает
    /// осознанным выбором.
    static let fatCeilingPerKg: Double = 1.5
    /// Рабочий коридор. Вне его число не запрещено, но о нём говорится вслух.
    static let fatComfortRange: ClosedRange<Double> = 0.6...1.2
    static let carbsMinimum: Double = 130
    static let kcalPerProteinGram: Double = 4
    static let kcalPerFatGram: Double = 9
    static let kcalPerCarbGram: Double = 4
}

/// Категория макронутриента — для поповеров и навигации в MacrosCard.
enum MacroKind: String, Identifiable {
    case protein, fat, carbs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .protein: return String(localized: "Белки")
        case .fat: return String(localized: "Жиры")
        case .carbs: return String(localized: "Углеводы")
        }
    }
}

/// Запись о приёме пищи. Модель SwiftData — хранится в настоящей базе данных на диске,
/// не сериализуется целиком при каждом изменении, в отличие от прежнего JSON+UserDefaults.
@Model
final class FoodEntry: Identifiable {
    var id: UUID
    var name: String
    var calories: Int
    var protein: Double
    var fat: Double
    var carbs: Double
    var grams: Double?
    var date: Date
    /// Из чего собран приём — по продуктам, как его собирали на экране.
    ///
    /// Приём из нескольких продуктов до этого хранился одной строкой со
    /// склеенным именем («Хала, Молоко, Whey Protein») и без веса, и
    /// восстановить по ней было нечего: ни «Недавнее» не видело протеина,
    /// съеденного двенадцать раз, ни разбор дня не знал, из каких категорий
    /// собран рацион, ни клетчатка не считалась.
    ///
    /// JSON в одном поле, а не связь SwiftData: состав — снимок на момент
    /// записи, он не должен меняться вслед за продуктом и не нужен запросам.
    /// Необязательное со значением по умолчанию — иначе уже сохранённые
    /// записи не смигрируют.
    var componentsData: Data?

    init(id: UUID = UUID(), name: String, calories: Int, macros: Macros = .zero, grams: Double? = nil,
         date: Date = Date(), components: [EntryComponent] = []) {
        self.id = id
        self.name = name
        self.calories = calories
        self.protein = macros.protein
        self.fat = macros.fat
        self.carbs = macros.carbs
        self.grams = grams
        self.date = date
        self.components = components
    }

    /// Состав приёма. Пусто — значит запись из одного продукта либо сделана
    /// до того, как состав начали хранить.
    var components: [EntryComponent] {
        get {
            guard let componentsData else { return [] }
            return (try? JSONDecoder().decode([EntryComponent].self, from: componentsData)) ?? []
        }
        set {
            componentsData = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue)
        }
    }

    /// Состав приёма, даже если он не записан: запись из одного продукта —
    /// это он сам. Так считающему коду не приходится каждый раз разбирать
    /// два случая.
    var composition: [EntryComponent] {
        if !components.isEmpty { return components }
        return [EntryComponent(name: name, calories: calories, macros: macros, grams: grams)]
    }

    var macros: Macros {
        get { Macros(protein: protein, fat: fat, carbs: carbs) }
        set {
            protein = newValue.protein
            fat = newValue.fat
            carbs = newValue.carbs
        }
    }
}

/// Ингредиент блюда — снапшот БЖУ на момент добавления, чтобы при правке продукта блюдо не ломалось.
struct DishIngredient: Codable, Identifiable {
    var id: UUID = UUID()
    var foodName: String
    var caloriesPer100g: Int
    var macrosPer100g: Macros
    var grams: Double

    var calories: Int { Int((Double(caloriesPer100g) * grams / 100).rounded()) }
    var macros: Macros { macrosPer100g.scaled(by: grams) }
}

/// Пользовательское блюдо — собирается из нескольких продуктов. Модель SwiftData.
@Model
final class Dish: Identifiable {
    var id: UUID
    var name: String
    var ingredientsData: Data
    var createdAt: Date
    /// Когда блюдо последний раз правили. Необязательное: у блюд, заведённых
    /// до появления «Недавнего», его нет, и там сойдёт дата создания.
    var updatedAt: Date?

    init(id: UUID = UUID(), name: String, ingredients: [DishIngredient] = [], createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.ingredientsData = (try? JSONEncoder().encode(ingredients)) ?? Data()
        self.createdAt = createdAt
    }

    var ingredients: [DishIngredient] {
        get { (try? JSONDecoder().decode([DishIngredient].self, from: ingredientsData)) ?? [] }
        set { ingredientsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var totalCalories: Int { ingredients.reduce(0) { $0 + $1.calories } }
    var totalMacros: Macros { ingredients.reduce(Macros.zero) { $0 + $1.macros } }
    var totalGrams: Double { ingredients.reduce(0) { $0 + $1.grams } }

    /// Порция по умолчанию. Ноль означает «вся кастрюля»: столько блюдо весит
    /// целиком. Своя порция нужна потому, что готовят обычно на несколько раз,
    /// и каждый раз отматывать от общего веса — лишняя работа.
    var defaultServingGrams: Double = 0

    /// Сколько подставлять в поле массы при добавлении.
    var servingGrams: Double {
        if defaultServingGrams > 0 { return defaultServingGrams }
        return totalGrams > 0 ? totalGrams : 100
    }

    var caloriesPer100g: Int {
        guard totalGrams > 0 else { return 0 }
        return Int((Double(totalCalories) / totalGrams * 100).rounded())
    }

    var macrosPer100g: Macros {
        guard totalGrams > 0 else { return .zero }
        return Macros(
            protein: totalMacros.protein / totalGrams * 100,
            fat: totalMacros.fat / totalGrams * 100,
            carbs: totalMacros.carbs / totalGrams * 100
        )
    }
}

/// Один продукт внутри записи дневника: снимок на момент записи.
nonisolated struct EntryComponent: Codable, Equatable, Hashable {
    var name: String
    var calories: Int
    var protein: Double
    var fat: Double
    var carbs: Double
    var grams: Double?

    init(name: String, calories: Int, macros: Macros = .zero, grams: Double? = nil) {
        self.name = name
        self.calories = calories
        self.protein = macros.protein
        self.fat = macros.fat
        self.carbs = macros.carbs
        self.grams = grams
    }

    var macros: Macros { Macros(protein: protein, fat: fat, carbs: carbs) }
}

/// Одна позиция в черновике приёма пищи — до нажатия «Сохранить» нигде не хранится.
struct MealItem: Identifiable {
    let id = UUID()
    var name: String
    var calories: Int
    var macros: Macros
    var grams: Double? = nil
}

/// Запись взвешивания. Модель SwiftData.
@Model
final class WeightEntry: Identifiable {
    var id: UUID
    var weightKg: Double
    var date: Date

    init(id: UUID = UUID(), weightKg: Double, date: Date = Date()) {
        self.id = id
        self.weightKg = weightKg
        self.date = date
    }
}

/// Зафиксированная цель по калориям на конкретный (уже прошедший) день. Как только день
/// перестаёт быть сегодняшним, для него один раз записывается снапшот — дальше правки
/// профиля/плана/цикла на него уже не влияют. Модель SwiftData.
@Model
final class GoalRecord: Identifiable {
    var id: UUID
    var date: Date
    var goal: Int

    init(id: UUID = UUID(), date: Date, goal: Int) {
        self.id = id
        self.date = date
        self.goal = goal
    }
}

/// Сводка по одному дню — вычисляется на лету из записей, не хранится отдельно.
/// Один день недели глазами макросов: что съедено против того, что было целью.
struct MacroDay: Identifiable {
    let date: Date
    let macros: Macros
    let proteinTarget: Double
    let fatTarget: Double
    let carbsTarget: Double
    let hasEntries: Bool

    var id: Date { date }

    /// Белок засчитан только когда набран целиком: недобор белка на дефиците —
    /// это съеденные мышцы, и «почти» здесь не считается.
    var hitProtein: Bool { hasEntries && macros.protein >= proteinTarget }
}

struct DaySummary: Identifiable {
    let date: Date
    let entries: [FoodEntry]
    let goal: Int

    var id: Date { date }

    var totalCalories: Int {
        entries.reduce(0) { $0 + $1.calories }
    }

    var totalMacros: Macros {
        entries.reduce(Macros.zero) { $0 + $1.macros }
    }

    var difference: Int {
        totalCalories - goal
    }
}
