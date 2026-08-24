import SwiftUI
import SwiftData

@main
struct CalorieCounterApp: App {
    private let container: ModelContainer
    @State private var store: CalorieStore
    @State private var stepStore = StepStore()
    @State private var purchases = PurchaseService()

    init() {
        do {
            let container = try ModelContainer(for: FoodEntry.self, FoodItem.self, WeightEntry.self, GoalRecord.self, Dish.self)
            self.container = container
            _store = State(initialValue: CalorieStore(context: container.mainContext))
        } catch {
            fatalError("Не удалось создать хранилище данных: \(error)")
        }
    }

    /// StoreKit может выдать премиум, но не отобрать.
    ///
    /// Первая версия просто присваивала `store.isPremium = purchases.isPremium`, и это
    /// отбирало доступ у всех, у кого StoreKit не ответил: нет сети, не подхватилась
    /// конфигурация, покупка ещё не восстановлена. Отзыв прав вернём, когда продукты
    /// будут приходить из App Store Connect и пустой ответ можно будет считать
    /// достоверным «не куплено».
    private func applyEntitlements() {
        if purchases.isPremium {
            store.isPremium = true
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(store: store, stepStore: stepStore, purchases: purchases)
                .task {
                    await purchases.load()
                    applyEntitlements()
                }
                .onChange(of: purchases.isPremium) { _, _ in
                    applyEntitlements()
                }
        }
        .modelContainer(container)
    }
}
