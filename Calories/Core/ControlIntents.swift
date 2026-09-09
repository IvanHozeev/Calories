import AppIntents
import Foundation

/// Те же намерения, что объявлены в расширении виджетов.
///
/// Дублирование здесь не небрежность, а требование системы: чтобы контрол из
/// Пункта управления открыл приложение, его намерение должно принадлежать
/// **обоим** таргетам — и расширению, где объявлен сам контрол, и приложению,
/// которое он открывает. Пока тип жил только в расширении, нажатие не делало
/// ничего: приложение не поднималось.
///
/// Один файл на два таргета положить нельзя — папки проекта синхронизированы с
/// файловой системой, и членство задаётся папкой. Копия типов с теми же именами
/// даёт системе ровно то же, что и общее членство: одинаковые идентификаторы
/// намерений в обоих бандлах.
///
/// Отличие копии только в теле: здесь мы уже внутри приложения, поэтому кроме
/// записи в общий контейнер сразу говорим маршрутизатору, что открывать. Иначе
/// на уже запущенном приложении переход в активное состояние не наступает и
/// намерение пролежало бы до следующего запуска.

@available(iOS 18.0, *)
private func handleControlAction(_ action: QuickAction) {
    UserDefaults(suiteName: CalorieStore.appGroup)?
        .set(action.rawValue, forKey: QuickActionRouter.controlActionKey)
    QuickActionRouter.shared.pending = action
}

/// Копия перечисления из расширения: параметр намерения — часть его подписи,
/// и без одинакового типа в обоих бандлах идентификаторы не совпадут.
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

    /// В действие приложения. Оба перечисления держатся на одних и тех же
    /// строках, но переводим явно: молчаливое совпадение `rawValue` — не то,
    /// на что стоит опираться, когда одно из них живёт в другом таргете.
    var action: QuickAction {
        switch self {
        case .meal:         return .meal
        case .camera:       return .camera
        case .scanner:      return .scanner
        case .measurements: return .measurements
        }
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

    @MainActor
    func perform() async throws -> some IntentResult {
        handleControlAction(option.action)
        return .result()
    }
}

@available(iOS 18.0, *)
struct PhotographFoodIntent: AppIntent {
    static let title: LocalizedStringResource = "Снять еду"
    static let description = IntentDescription("Открывает камеру, чтобы разобрать блюдо по фотографии.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        handleControlAction(.camera)
        return .result()
    }
}

@available(iOS 18.0, *)
struct ScanBarcodeIntent: AppIntent {
    static let title: LocalizedStringResource = "Сканировать штрихкод"
    static let description = IntentDescription("Открывает сканер штрихкода.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        handleControlAction(.scanner)
        return .result()
    }
}

@available(iOS 18.0, *)
struct TakeMeasurementsIntent: AppIntent {
    static let title: LocalizedStringResource = "Снять замеры"
    static let description = IntentDescription("Открывает ввод замеров.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        handleControlAction(.measurements)
        return .result()
    }
}
