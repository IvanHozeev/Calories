import Testing
import Foundation
import SwiftData
@testable import Calories

/// Открывается ли нынешней схемой база, записанная прежней.
///
/// Самый дорогой риск этого приложения — не падение и не потерянный телефон, а
/// собственная правка модели: новое свойство без значения по умолчанию не
/// мигрирует, и человек с годом дневника узнаёт об этом сам. Остальные тесты
/// поднимают контейнер в памяти, то есть ровно тот случай, где мигрировать
/// нечего, — и потому эту ошибку не ловят в принципе.
///
/// Образец в `Fixtures` записан прежней сборкой (коммит `03e3658`, до
/// кашрута): настоящий файл настоящей схемы, а не собранный руками. Когда
/// схема снова поменяется заметно, рядом ляжет следующий такой же, а этот
/// останется — старую базу человек может принести и через год.
@MainActor
@Suite(.serialized)
struct StoreMigrationTests {

    /// Копия образца во временной папке: открытие базы её меняет, а файл в
    /// репозитории должен оставаться таким, каким его записали.
    private func openedFixture() throws -> (ModelContainer, URL) {
        let fixture = try #require(Bundle(for: BundleToken.self)
            .url(forResource: "legacy-before-kosher", withExtension: "store"))
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "migration-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: "legacy.store")
        try FileManager.default.copyItem(at: fixture, to: url)

        let container = try ModelContainer(
            for: FoodEntry.self, FoodItem.self, WeightEntry.self, GoalRecord.self, Dish.self,
            BodyMeasurement.self, FastDay.self,
            configurations: ModelConfiguration(url: url)
        )
        return (container, dir)
    }

    /// Главное: база прошлой схемы вообще открывается. Если этот тест упал,
    /// значит выпущенная сборка встретит человека пустым экраном с ошибкой
    /// хранилища вместо его дневника.
    @Test func aStoreFromThePreviousSchemaStillOpens() throws {
        let (container, dir) = try openedFixture()
        defer { try? FileManager.default.removeItem(at: dir) }

        let context = container.mainContext
        #expect(try context.fetch(FetchDescriptor<FoodItem>()).count == 2)
        #expect(try context.fetch(FetchDescriptor<FoodEntry>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<Dish>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<WeightEntry>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<GoalRecord>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<FastDay>()).count == 1)
    }

    /// Ничего не потерялось по дороге: имена, числа, состав, коэффициент
    /// уварки и состав блюда — всё то, что человек вводил руками.
    @Test func nothingIsLostOnTheWay() throws {
        let (container, dir) = try openedFixture()
        defer { try? FileManager.default.removeItem(at: dir) }

        let foods = try container.mainContext.fetch(FetchDescriptor<FoodItem>())
        let curd = try #require(foods.first { $0.name == "Творог мой" })
        #expect(curd.caloriesPer100g == 90)
        #expect(curd.protein == 17)
        #expect(curd.defaultGrams == 180)
        #expect(curd.cookingYield == 1.2)
        #expect(curd.micronutrients[.calcium] == 120)

        let dish = try #require(container.mainContext.fetch(FetchDescriptor<Dish>()).first)
        #expect(dish.name == "Сырники")
        #expect(dish.ingredients.first?.foodName == "Творог мой")
        #expect(dish.ingredients.first?.grams == 200)

        let entry = try #require(container.mainContext.fetch(FetchDescriptor<FoodEntry>()).first)
        #expect(entry.calories == 162)
        #expect(entry.grams == 180)
    }

    /// Новые свойства достаются старым записям со значением по умолчанию —
    /// иначе их не было бы вовсе, и миграция упала бы.
    @Test func newPropertiesArriveWithTheirDefaults() throws {
        let (container, dir) = try openedFixture()
        defer { try? FileManager.default.removeItem(at: dir) }

        for food in try container.mainContext.fetch(FetchDescriptor<FoodItem>()) {
            #expect(food.kosherOverride == nil)
            #expect(!food.isHardCheese)
            #expect(!food.kosherForbidden)
        }
    }

    /// Категория хранится строкой, и разделение «Молочного и яиц» старую
    /// запись не трогает: яйцо, заведённое молочным, молочным и остаётся,
    /// пока человек сам его не переложит. Это правильное поведение — чужую
    /// категорию приложение не переписывает, — но и статус у него тогда
    /// молочный, о чём и говорит строка кашрута в карточке продукта.
    @Test func anOldCategorySurvivesTheSplit() throws {
        let (container, dir) = try openedFixture()
        defer { try? FileManager.default.removeItem(at: dir) }

        let foods = try container.mainContext.fetch(FetchDescriptor<FoodItem>())
        let egg = try #require(foods.first { $0.name == "Яйцо моё" })
        #expect(egg.foodCategory == .dairy)
        #expect(egg.kosherStatus == .dairy)
    }

    /// Открыли, записали, закрыли, открыли снова — мигрированная база живёт
    /// как обычная.
    @Test func theMigratedStoreCanBeWrittenTo() throws {
        let (container, dir) = try openedFixture()
        defer { try? FileManager.default.removeItem(at: dir) }

        let context = container.mainContext
        let added = FoodItem(name: "Новый", caloriesPer100g: 100, protein: 1, fat: 1, carbs: 1,
                             category: .eggs)
        added.kosherStatus = .parve
        context.insert(added)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<FoodItem>()).count == 3)
        let saved = try #require(try context.fetch(FetchDescriptor<FoodItem>())
            .first { $0.name == "Новый" })
        #expect(saved.foodCategory == .eggs)
    }
}

/// Нужен только чтобы найти бандл с образцом: `Bundle(for:)` просит класс.
private final class BundleToken {}
