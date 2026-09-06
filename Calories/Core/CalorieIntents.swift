import AppIntents
import Foundation

/// Команды Сири и Быстрых команд.
///
/// Живут в основном таргете, а не в расширении, намеренно: так они выполняются в
/// процессе приложения и работают с тем же `SharedStore`, что и экраны. Расширению
/// пришлось бы открывать вторую копию базы, и дневник разошёлся бы сам с собой.
///
/// Смысл в том, чтобы записать съеденное, не доставая приложение: за столом в
/// гостях, за рулём, с руками в тесте.
struct LogCaloriesIntent: AppIntent {
    static let title: LocalizedStringResource = "Записать калории"
    static let description = IntentDescription("Добавляет в дневник приём пищи, у которого известны только калории.")
    static let openAppWhenRun = false

    @Parameter(title: "Калории", requestValueDialog: "Сколько калорий?")
    var calories: Int

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let store = SharedStore.shared.store else {
            return .result(dialog: "Не удалось открыть дневник.")
        }
        guard calories > 0 else {
            return .result(dialog: "Калории должны быть больше нуля.")
        }
        store.add(name: String(localized: "Приём пищи"), calories: calories)
        let left = store.remaining
        return .result(dialog: left > 0
                       ? "Записал \(calories) ккал. Осталось \(left)."
                       : "Записал \(calories) ккал. Норма на сегодня уже перебрана.")
    }
}

/// Спросить остаток, не открывая приложение, — самый частый вопрос к трекеру.
struct RemainingCaloriesIntent: AppIntent {
    static let title: LocalizedStringResource = "Сколько осталось калорий"
    static let description = IntentDescription("Говорит, сколько калорий осталось до дневной нормы.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let store = SharedStore.shared.store else {
            return .result(dialog: "Не удалось открыть дневник.")
        }
        let left = store.remaining
        return .result(dialog: left > 0
                       ? "Осталось \(left) ккал из \(store.adaptedTodayGoal)."
                       : "Норма на сегодня перебрана на \(-left) ккал.")
    }
}

/// Взвешивание — ежедневный ритуал сразу после пробуждения, и достать телефон
/// в этот момент проще голосом, чем руками.
struct LogWeightIntent: AppIntent {
    static let title: LocalizedStringResource = "Записать вес"
    static let description = IntentDescription("Добавляет взвешивание за сегодня.")
    static let openAppWhenRun = false

    @Parameter(title: "Вес, кг", requestValueDialog: "Какой вес?")
    var weightKg: Double

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let store = SharedStore.shared.store else {
            return .result(dialog: "Не удалось открыть дневник.")
        }
        guard weightKg > 0 else {
            return .result(dialog: "Вес должен быть больше нуля.")
        }
        store.addWeight(weightKg)
        return .result(dialog: "Записал \(String(format: "%.1f", weightKg)) кг.")
    }
}

struct CaloriesAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RemainingCaloriesIntent(),
            phrases: [
                "Сколько осталось в \(.applicationName)",
                "How many calories are left in \(.applicationName)"
            ],
            shortTitle: "Остаток калорий",
            systemImageName: "flame.fill"
        )
        AppShortcut(
            intent: LogCaloriesIntent(),
            phrases: [
                "Записать калории в \(.applicationName)",
                "Log calories in \(.applicationName)"
            ],
            shortTitle: "Записать калории",
            systemImageName: "plus.circle.fill"
        )
        AppShortcut(
            intent: LogWeightIntent(),
            phrases: [
                "Записать вес в \(.applicationName)",
                "Log weight in \(.applicationName)"
            ],
            shortTitle: "Записать вес",
            systemImageName: "scalemass"
        )
    }
}
