import Foundation
import SwiftData
import OSLog

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Calories", category: "SharedStore")

/// Единственное хранилище на процесс.
///
/// Раньше контейнер и стор создавались прямо в `CalorieCounterApp.init` и жили в
/// `@State` — до них нельзя было дотянуться ниоткуда, кроме дерева экранов. Команды
/// Сири выполняются в том же процессе, но без сцены, и им нужен тот же самый стор:
/// второй контейнер поверх той же базы означал бы две несогласованные картины дня.
@MainActor
final class SharedStore {
    static let shared = SharedStore()

    let container: ModelContainer?
    let store: CalorieStore?
    /// Текст ошибки, если база не открылась. Показывается вместо приложения.
    let storageError: String?

    private init() {
        do {
            let container = try ModelContainer(
                for: FoodEntry.self, FoodItem.self, WeightEntry.self, GoalRecord.self, Dish.self,
                BodyMeasurement.self, FastDay.self
            )
            self.container = container
            self.store = CalorieStore(context: container.mainContext)
            self.storageError = nil
        } catch {
            logger.error("Хранилище не открылось: \(error.localizedDescription)")
            self.container = nil
            self.store = nil
            self.storageError = error.localizedDescription
        }
    }
}
