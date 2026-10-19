import Testing
import Foundation
import SwiftData
@testable import Calories

/// Бандл, купленный в GymLogger, открывает платное и здесь.
///
/// Проверять это глазами нельзя: флаг пишет соседнее приложение, и собрать
/// такую ситуацию руками можно только купив пару в магазине. Зато правило
/// простое и целиком наше — значит, его место в тестах.
@MainActor
@Suite(.serialized)
struct BundleUnlockTests {

    private let container: ModelContainer
    private let group: UserDefaults

    init() throws {
        container = try ModelContainer(
            for: FoodEntry.self, FoodItem.self, WeightEntry.self, GoalRecord.self, Dish.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        group = TestDefaults.make()
    }

    private func makeStore() -> CalorieStore {
        CalorieStore(context: container.mainContext, defaults: TestDefaults.make(), groupDefaults: group)
    }

    @Test func gymBundleOpensPremium() {
        let store = makeStore()
        #expect(!store.isPremium)

        group.set(true, forKey: "gym_is_bundle")
        store.refreshSharedEntitlements()

        #expect(store.isPremium)
        // Своей покупки при этом нет: подарок не превращается в чек.
        #expect(!store.hasPurchasedPremium)
    }

    /// Ключ может прийти и от общего слоя, а не только из GymLogger.
    @Test func sharedBundleOpensPremium() {
        let store = makeStore()
        group.set(true, forKey: "shared_is_bundle")
        store.refreshSharedEntitlements()
        #expect(store.isPremium)
    }

    /// Куплен отдельный тариф соседа — не бандл — и открывать нечего.
    @Test func ownPurchaseOfTheNeighbourDoesNotOpenUs() {
        let store = makeStore()
        group.set(true, forKey: "shared_is_premium")
        store.refreshSharedEntitlements()
        #expect(!store.isPremium)
    }

    /// Соседа снесли — возвращаемся к своим правам, а не запираемся.
    @Test func withoutTheNeighbourItFallsBackToOwnRights() {
        let store = makeStore()
        group.set(true, forKey: "gym_is_bundle")
        store.refreshSharedEntitlements()
        #expect(store.isPremium)

        group.set(false, forKey: "gym_is_bundle")
        store.refreshSharedEntitlements()
        #expect(!store.isPremium)

        store.isPremium = true
        group.set(false, forKey: "gym_is_bundle")
        store.refreshSharedEntitlements()
        #expect(store.isPremium, "Своя покупка не зависит от соседа")
    }

    /// Подаренный доступ не уходит соседу обратно как «премиум Calories»:
    /// иначе непонятно, за что человек заплатил, и бандл начинает открывать
    /// сам себя по кругу.
    @Test func theGiftDoesNotEchoBack() {
        let store = makeStore()
        group.set(true, forKey: "gym_is_bundle")
        store.refreshSharedEntitlements()
        #expect(store.isPremium)
        #expect(group.bool(forKey: "shared_is_premium") == false)

        store.isPremium = true
        #expect(group.bool(forKey: "shared_is_premium"))
    }
}
