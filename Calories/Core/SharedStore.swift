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

    /// Где лежит база.
    ///
    /// Задаётся явно, и это не придирка к стилю. `ModelContainer(for:)` без
    /// адреса кладёт файл не в контейнер приложения, а в первую группу из
    /// энтайтлментов, если она есть, и называет его `default.store`. Группа у
    /// нас общая с соседним приложением, имя по умолчанию у обоих одно — и
    /// один физический файл открывали две разные схемы. Чья схема открыла
    /// последней, под ту файл и мигрировал, а чужие сущности лёгкая миграция
    /// вычищала. У соседа так пропала вся история тренировок; наши шестьсот
    /// записей еды уцелели только потому, что мы открыли файл последними.
    ///
    /// Остаёмся в той же папке и меняем только имя: файл никуда не едет, а
    /// переименование внутри одного каталога атомарно. В контейнер
    /// приложения переносить незачем — виджет базу не открывает, ему хватает
    /// общих настроек.
    static var storeURL: URL {
        let folder = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: CalorieStore.appGroup)?
            .appending(path: "Library/Application Support")
            ?? URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "Calories.store")
    }

    /// Одноразовый переезд со старого общего имени на своё.
    ///
    /// Без него новое имя означало бы пустую базу: записи остались бы лежать
    /// в `default.store`, который мы больше не открываем. Переносим вместе с
    /// журналом (`-wal`) и разделяемой памятью (`-shm`) — без них база
    /// открывается без последних транзакций, то есть без того, что человек
    /// записал за сегодня.
    ///
    /// Если что-то пошло не так, исходник остаётся на месте: лучше открыть
    /// пустую базу и разбираться, чем удалить единственную копию.
    private static func migrateFromSharedDefaultStore() {
        let manager = FileManager.default
        let target = storeURL
        guard !manager.fileExists(atPath: target.path) else { return }
        let legacy = target.deletingLastPathComponent().appending(path: "default.store")
        guard manager.fileExists(atPath: legacy.path) else { return }

        for suffix in ["", "-wal", "-shm"] {
            let from = URL(fileURLWithPath: legacy.path + suffix)
            let to = URL(fileURLWithPath: target.path + suffix)
            guard manager.fileExists(atPath: from.path) else { continue }
            do {
                try manager.moveItem(at: from, to: to)
            } catch {
                logger.error("Не удалось перенести \(suffix.isEmpty ? "базу" : suffix): \(error.localizedDescription)")
            }
        }
        logger.notice("База переехала с общего default.store на Calories.store")
    }

    private init() {
        Self.migrateFromSharedDefaultStore()
        do {
            let container = try ModelContainer(
                for: FoodEntry.self, FoodItem.self, WeightEntry.self, GoalRecord.self, Dish.self,
                BodyMeasurement.self, FastDay.self,
                configurations: ModelConfiguration(url: Self.storeURL)
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
