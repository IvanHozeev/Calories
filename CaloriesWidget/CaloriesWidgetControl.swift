import AppIntents
import SwiftUI
import WidgetKit

/// Кнопки в Пункте управления: добавить еду, снять её, отсканировать штрихкод
/// и записать замеры.
///
/// Смысл тот же, что у длинного нажатия на иконку, но короче на один шаг:
/// контрол вешается на кнопку действия или лежит в Пункте управления, и до
/// камеры получается один жест с любого экрана. Еда — про то, чтобы не вводить
/// руками: штрихкод, когда есть упаковка, фото — когда её нет. Замеры про
/// другое: там ровно наоборот, руки заняты лентой, и лишний путь через «Тело»
/// и экран замеров стоит дороже, чем сам ввод.
///
/// Здесь замеры есть, а в меню на иконке их нет: система показывает там не
/// больше четырёх пунктов, а в Пункте управления такого потолка нет.
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
        UserDefaults(suiteName: appGroup)?.set("camera", forKey: pendingActionKey)
        return .result()
    }
}

@available(iOS 18.0, *)
struct ScanBarcodeIntent: AppIntent {
    static let title: LocalizedStringResource = "Сканировать штрихкод"
    static let description = IntentDescription("Открывает сканер штрихкода.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: appGroup)?.set("scanner", forKey: pendingActionKey)
        return .result()
    }
}

@available(iOS 18.0, *)
struct QuickAddIntent: AppIntent {
    static let title: LocalizedStringResource = "Быстрое добавление"
    static let description = IntentDescription("Открывает выбранный экран добавления.")
    static let openAppWhenRun = true

    @Parameter(title: "Что открывать", default: .meal)
    var option: QuickAddOption

    init() {}
    init(option: QuickAddOption) { self.option = option }

    func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: appGroup)?.set(option.rawValue, forKey: pendingActionKey)
        return .result()
    }
}

/// Что делает настраиваемый контрол-плюс.
///
/// Значения совпадают с `QuickAction` в приложении: расширение кладёт в общий
/// контейнер именно `rawValue`, и приложение разбирает его тем же перечислением.
/// Разъедутся — контрол будет открывать не то, и молча.
@available(iOS 18.0, *)
enum QuickAddOption: String, AppEnum {
    case meal
    case camera
    case scanner
    case measurements

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Что открывать")

    static let caseDisplayRepresentations: [QuickAddOption: DisplayRepresentation] = [
        .meal: DisplayRepresentation(title: "Добавить еду", image: DisplayRepresentation.Image(systemName: "fork.knife")),
        .camera: DisplayRepresentation(title: "Снять еду", image: DisplayRepresentation.Image(systemName: "camera.fill")),
        .scanner: DisplayRepresentation(title: "Сканировать штрихкод",
                                        image: DisplayRepresentation.Image(systemName: "barcode.viewfinder")),
        .measurements: DisplayRepresentation(title: "Снять замеры", image: DisplayRepresentation.Image(systemName: "ruler"))
    ]

    var symbol: String {
        switch self {
        case .meal:         return "fork.knife"
        case .camera:       return "camera.fill"
        case .scanner:      return "barcode.viewfinder"
        case .measurements: return "ruler"
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .meal:         return "Добавить еду"
        case .camera:       return "Снять еду"
        case .scanner:      return "Сканировать штрихкод"
        case .measurements: return "Снять замеры"
        }
    }
}

/// Настройка контрола: что он делает.
///
/// Меню по долгому нажатию сделать нельзя, и это не недоделка: в SDK есть ровно
/// два вида контрола — кнопка и переключатель, и ни один из них меню не умеет.
/// Долгое нажатие на контроле просто срабатывает как обычное.
///
/// Выбор из этих четырёх живёт в правке Пункта управления: долгое нажатие
/// по пустому месту, потом тап по самому контролу. Выбор не разовый — он
/// переключает то, что кнопка делает дальше. Для одной кнопки на все случаи
/// это и нужно, а кому нужны несколько сразу — рядом лежат отдельные контролы
/// на камеру, сканер и замеры.
@available(iOS 18.0, *)
struct QuickAddConfiguration: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Быстрое добавление"
    static let description = IntentDescription("Что открывать нажатием на контрол.")

    @Parameter(title: "Что открывать", default: .meal)
    var option: QuickAddOption

    init() {}
    init(option: QuickAddOption) { self.option = option }
}

@available(iOS 18.0, *)
struct QuickAddValueProvider: AppIntentControlValueProvider {
    func previewValue(configuration: QuickAddConfiguration) -> QuickAddOption {
        configuration.option
    }

    func currentValue(configuration: QuickAddConfiguration) async throws -> QuickAddOption {
        configuration.option
    }
}

@available(iOS 18.0, *)
struct QuickAddControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: "ivankhozeyev.team.Calories.control.meal",
                                      provider: QuickAddValueProvider()) { option in
            ControlWidgetButton(action: QuickAddIntent(option: option)) {
                Label(option.title, systemImage: option.symbol)
            }
        }
        .displayName("Быстрое добавление")
        .description("Один жест до еды, камеры, сканера или замеров. Что именно — выбирается в правке Пункта управления.")
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

@available(iOS 18.0, *)
struct TakeMeasurementsIntent: AppIntent {
    static let title: LocalizedStringResource = "Снять замеры"
    static let description = IntentDescription("Открывает ввод замеров.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: appGroup)?.set("measurements", forKey: pendingActionKey)
        return .result()
    }
}

@available(iOS 18.0, *)
struct TakeMeasurementsControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "ivankhozeyev.team.Calories.control.measurements") {
            ControlWidgetButton(action: TakeMeasurementsIntent()) {
                Label("Снять замеры", systemImage: "ruler")
            }
        }
        .displayName("Снять замеры")
        .description("Открывает ввод замеров в Calories.")
    }
}
