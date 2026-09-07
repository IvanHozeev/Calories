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

@available(iOS 18.0, *)
struct AddMealIntent: AppIntent {
    static let title: LocalizedStringResource = "Добавить еду"
    static let description = IntentDescription("Открывает экран добавления приёма пищи.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        handleControlAction(.meal)
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
