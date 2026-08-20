import SwiftUI
import SwiftData

@main
struct CalorieCounterApp: App {
    private let container: ModelContainer
    @StateObject private var store: CalorieStore
    @StateObject private var stepStore = StepStore()

    init() {
        do {
            let container = try ModelContainer(for: FoodEntry.self, FoodItem.self, WeightEntry.self, GoalRecord.self, Dish.self)
            self.container = container
            _store = StateObject(wrappedValue: CalorieStore(context: container.mainContext))
        } catch {
            fatalError("Не удалось создать хранилище данных: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(store: store, stepStore: stepStore)
        }
        .modelContainer(container)
    }
}
