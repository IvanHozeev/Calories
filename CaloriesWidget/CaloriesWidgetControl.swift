import AppIntents
import OSLog
import SwiftUI
import WidgetKit

private let controlLogger = Logger(subsystem: "ivankhozeyev.team.Calories", category: "control")

/// Кнопки в Пункте управления: снять еду и отсканировать штрихкод.
///
/// Смысл тот же, что у длинного нажатия на иконку, но короче на один шаг:
/// контрол вешается на кнопку действия или лежит в Пункте управления, и до
/// камеры получается один жест с любого экрана. Оба способа — про то, чтобы
/// не вводить руками: штрихкод, когда есть упаковка, фото — когда её нет.
///
/// Контролы появились в iOS 18, а приложение живёт с 17.6, поэтому всё здесь
/// под проверкой доступности.

private let appGroup = "group.calories.shared"

/// Через этот ключ контрол просит приложение открыть нужный экран.
///
/// Расширение и приложение — разные процессы, и напрямую позвать экран нельзя.
/// Намерение кладётся в общий контейнер, приложение забирает его на старте и
/// сразу стирает: иначе один нажатый контрол открывал бы камеру при каждом
/// следующем запуске.
private let pendingActionKey = "pending_quick_action"

@available(iOS 18.0, *)
struct PhotographFoodIntent: AppIntent {
    static let title: LocalizedStringResource = "Снять еду"
    static let description = IntentDescription("Открывает камеру, чтобы разобрать блюдо по фотографии.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        let defaults = UserDefaults(suiteName: appGroup)
        defaults?.set("camera", forKey: pendingActionKey)
        controlLogger.notice("контрол камеры: контейнер \(defaults != nil ? "есть" : "НЕДОСТУПЕН")")
        return .result()
    }
}

@available(iOS 18.0, *)
struct ScanBarcodeIntent: AppIntent {
    static let title: LocalizedStringResource = "Сканировать штрихкод"
    static let description = IntentDescription("Открывает сканер штрихкода.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        let defaults = UserDefaults(suiteName: appGroup)
        defaults?.set("scanner", forKey: pendingActionKey)
        controlLogger.notice("контрол сканера: контейнер \(defaults != nil ? "есть" : "НЕДОСТУПЕН")")
        return .result()
    }
}

@available(iOS 18.0, *)
struct AddMealIntent: AppIntent {
    static let title: LocalizedStringResource = "Добавить еду"
    static let description = IntentDescription("Открывает экран добавления приёма пищи.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        let defaults = UserDefaults(suiteName: appGroup)
        defaults?.set("meal", forKey: pendingActionKey)
        controlLogger.notice("контрол приёма пищи: контейнер \(defaults != nil ? "есть" : "НЕДОСТУПЕН")")
        return .result()
    }
}

@available(iOS 18.0, *)
struct AddMealControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "ivankhozeyev.team.Calories.control.meal") {
            ControlWidgetButton(action: AddMealIntent()) {
                Label("Добавить еду", systemImage: "plus")
            }
        }
        .displayName("Добавить еду")
        .description("Открывает добавление приёма пищи в Calories.")
    }
}

@available(iOS 18.0, *)
struct PhotographFoodControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "ivankhozeyev.team.Calories.control.photo") {
            ControlWidgetButton(action: PhotographFoodIntent()) {
                Label("Снять еду", systemImage: "camera")
            }
        }
        .displayName("Снять еду")
        .description("Открывает камеру в Calories.")
    }
}

@available(iOS 18.0, *)
struct ScanBarcodeControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "ivankhozeyev.team.Calories.control.scanner") {
            ControlWidgetButton(action: ScanBarcodeIntent()) {
                Label("Сканировать штрихкод", systemImage: "barcode.viewfinder")
            }
        }
        .displayName("Сканировать штрихкод")
        .description("Открывает сканер штрихкода в Calories.")
    }
}
