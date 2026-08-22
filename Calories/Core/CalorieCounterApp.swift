import SwiftUI
import SwiftData

@main
struct CalorieCounterApp: App {
    private let container: ModelContainer
    @State private var store: CalorieStore
    @State private var stepStore = StepStore()

    init() {
        do {
            let container = try ModelContainer(for: FoodEntry.self, FoodItem.self, WeightEntry.self, GoalRecord.self, Dish.self)
            self.container = container
            _store = State(initialValue: CalorieStore(context: container.mainContext))
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
