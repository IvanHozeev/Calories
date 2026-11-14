import Testing
import Foundation
import SwiftData
@testable import Calories

/// Продукт «на штуку»: шейк с КБЖУ на всю бутылку и без веса.
@MainActor
@Suite(.serialized)
struct PerUnitFoodTests {
    private let container: ModelContainer
    private let store: CalorieStore

    init() throws {
        container = try ModelContainer(
            for: FoodEntry.self, FoodItem.self, WeightEntry.self, GoalRecord.self, Dish.self,
            BodyMeasurement.self, FastDay.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        store = CalorieStore(context: container.mainContext,
                             defaults: TestDefaults.make(), groupDefaults: nil)
    }

    private func addShake() {
        store.addCustomFood(name: "Шейк", caloriesPer100g: 320, protein: 40, fat: 6, carbs: 25,
                            isPerUnit: true)
    }

    @Test func aShakeIsSavedPerUnit() throws {
        addShake()
        let shake = try #require(store.customFoods.first { $0.name == "Шейк" })
        #expect(shake.isPerUnit)
        #expect(shake.defaultGrams == 100)
    }

    /// Запись хранит штуки, а граммы не выдумывает.
    @Test func aMealWithAShakeKeepsPiecesNotGrams() throws {
        store.add(name: "Шейк", calories: 480, macros: Macros(protein: 60, fat: 9, carbs: 37.5),
                  components: [EntryComponent(name: "Шейк", calories: 480,
                                              macros: Macros(protein: 60, fat: 9, carbs: 37.5),
                                              grams: nil, pieces: 1.5)])
        let part = try #require(store.entries.first?.components.first)
        #expect(part.pieces == 1.5)
        #expect(part.grams == nil)
    }

    @Test func piecesAreLabelledAsPieces() {
        #expect(PortionLabel.text(grams: nil, pieces: 1)?.hasPrefix("1") == true)
        #expect(PortionLabel.text(grams: nil, pieces: 1.5)?.contains("5") == true)
        #expect(PortionLabel.text(grams: 180, pieces: nil)?.hasPrefix("180") == true)
        #expect(PortionLabel.text(grams: nil, pieces: nil) == nil)
    }

    /// Признак переживает копию, и штуки в составе приёма — тоже.
    @Test func perUnitSurvivesABackup() throws {
        addShake()
        store.add(name: "Шейк", calories: 320,
                  components: [EntryComponent(name: "Шейк", calories: 320, pieces: 1)])
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(CaloriesBackup.self, from: try encoder.encode(store.makeBackup()))
        store.restore(from: backup)
        #expect(store.customFoods.first { $0.name == "Шейк" }?.isPerUnit == true)
        #expect(store.entries.first?.components.first?.pieces == 1)
    }

    /// Старая копия без признака читается, продукт — обычный, на 100 г.
    @Test func anOldProductWithoutTheFlagIsPer100g() throws {
        let json = """
        {"appVersion": "3", "dailyGoal": 2100, "exportedAt": "2026-09-01T10:00:00Z",
         "entries": [], "weights": [], "dishes": [], "goalHistory": [],
         "products": [{"name":"Сыр","caloriesPer100g":300,"protein":25,"fat":22,"carbs":1,"defaultGrams":30}]}
        """
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(CaloriesBackup.self, from: Data(json.utf8))
        store.restore(from: backup)
        #expect(store.customFoods.first?.isPerUnit == false)
    }

    /// Старый состав записи без штук читается: штук нет, граммы на месте.
    @Test func anOldComponentWithoutPiecesDecodes() throws {
        let json = #"{"name":"Творог","calories":200,"protein":30,"fat":5,"carbs":6,"grams":200}"#
        let part = try JSONDecoder().decode(EntryComponent.self, from: Data(json.utf8))
        #expect(part.pieces == nil)
        #expect(part.grams == 200)
    }
}

/// Правка штук у записанного продукта «на штуку».
struct PerUnitScalingTests {
    @Test func changingPiecesRescalesTheNumbers() {
        let shake = EntryComponent(name: "Шейк", calories: 320, macros: Macros(protein: 40, fat: 6, carbs: 25), pieces: 1)
        let half = shake.scaled(toPieces: 0.5)
        #expect(half.calories == 160)
        #expect(half.protein == 20)
        #expect(half.pieces == 0.5)
        #expect(half.grams == nil)
    }

    @Test func aComponentWithoutPiecesIsNotRescaledByPieces() {
        let cheese = EntryComponent(name: "Творог", calories: 200, grams: 200)
        #expect(cheese.scaled(toPieces: 2) == cheese)
    }
}

/// «Как мой обычный ужин, только в полтора раза больше» (5.2).
struct UsualMultiplierTests {
    @Test func aUsualMealTimesOneAndAHalf() {
        let pasta = EntryComponent(name: "Паста", calories: 600, macros: Macros(protein: 20, fat: 10, carbs: 100), grams: 300)
        let bigger = pasta.times(1.5)
        #expect(bigger.calories == 900)
        #expect(bigger.carbs == 150)
        #expect(bigger.grams == 450)
    }

    @Test func piecesAreMultipliedToo() {
        let shake = EntryComponent(name: "Шейк", calories: 320, pieces: 1)
        #expect(shake.times(2).pieces == 2)
        #expect(shake.times(2).grams == nil)
    }

    @Test func theMultipliersAreHalfOneAndAHalfAndDouble() {
        #expect(EntryComponent.usualMultipliers == [0.5, 1.5, 2])
        #expect(EntryComponent.multiplierTitle(0.5) == "×½")
        #expect(EntryComponent.multiplierTitle(1.5) == "×1½")
    }
}
