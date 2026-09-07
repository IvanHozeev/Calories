import Foundation
import Observation
import OSLog

/// Автоматическая копия дневника в папку, выбранную человеком один раз.
///
/// Почему не просто писать в свои документы: контейнер приложения удаляется
/// вместе с приложением. Копия внутри него защищает от порчи данных, но не от
/// того сценария, который случается чаще всего, — «удалил и поставил заново».
/// Папка в «Файлах» или iCloud Drive лежит снаружи контейнера и переживает это.
///
/// Синхронизации у приложения нет и не будет, пока нет платного аккаунта: iCloud
/// как хранилище приложению недоступен. Но выбрать папку в iCloud Drive через
/// системный диалог может кто угодно, без единого разрешения, — и дальше
/// приложение пишет туда само. Это и есть та самая копия, которую нельзя
/// потерять вместе с телефоном.
@Observable
@MainActor
final class BackupService {
    private static let logger = Logger(subsystem: "team.ivankhozeyev.Calories", category: "backup")

    private enum Keys {
        static let bookmark = "backup_folder_bookmark"
        static let lastDate = "backup_last_date"
    }

    /// Раз в сутки. Чаще незачем: дневник за день меняется на несколько записей,
    /// и потерять их не так страшно, как потерять годы истории.
    nonisolated static let interval: TimeInterval = 24 * 60 * 60

    /// Сколько копий держать. Смысл не в объёме — файл занимает килобайты, —
    /// а в том, чтобы можно было отойти назад, если испортил данные и заметил
    /// это не сразу.
    nonisolated static let keepLast = 14

    /// Общий экземпляр: копию делают и экран настроек, и запуск приложения,
    /// а состояние у неё одно — когда была последняя и куда пишем.
    static let shared = BackupService()

    private let defaults: UserDefaults
    private(set) var folderName: String?
    private(set) var lastBackupDate: Date?
    private(set) var lastError: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        lastBackupDate = defaults.object(forKey: Keys.lastDate) as? Date
        folderName = Self.resolveFolder(from: defaults.data(forKey: Keys.bookmark))?.lastPathComponent
    }

    var isConfigured: Bool { defaults.data(forKey: Keys.bookmark) != nil }

    /// Запоминает выбранную папку закладкой, а не путём: путь к файлу в iCloud
    /// Drive меняется, а закладка переживает переезд и переустановку приложения.
    func useFolder(_ url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let bookmark = try url.bookmarkData()
            defaults.set(bookmark, forKey: Keys.bookmark)
            folderName = url.lastPathComponent
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            Self.logger.error("не удалось запомнить папку: \(error)")
        }
    }

    func forgetFolder() {
        defaults.removeObject(forKey: Keys.bookmark)
        folderName = nil
    }

    /// Пора ли делать копию. Отдельной функцией без побочных эффектов, чтобы
    /// расписание можно было проверить тестом, не трогая файловую систему.
    nonisolated static func shouldBackup(last: Date?, now: Date, interval: TimeInterval = interval) -> Bool {
        guard let last else { return true }
        return now.timeIntervalSince(last) >= interval
    }

    /// Какие файлы лишние. Имена содержат дату, поэтому лексикографический
    /// порядок совпадает с хронологическим — отдельного разбора дат не нужно.
    nonisolated static func obsoleteBackups(among names: [String], keepLast: Int = keepLast) -> [String] {
        let ours = names.filter { $0.hasPrefix("calories-backup-") && $0.hasSuffix(".json") }.sorted()
        guard ours.count > keepLast else { return [] }
        return Array(ours.dropLast(keepLast))
    }

    nonisolated static func filename(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return "calories-backup-\(formatter.string(from: date)).json"
    }

    @discardableResult
    func backupIfNeeded(_ store: CalorieStore, now: Date = Date()) -> Bool {
        guard isConfigured, Self.shouldBackup(last: lastBackupDate, now: now) else { return false }
        return backupNow(store, now: now)
    }

    @discardableResult
    func backupNow(_ store: CalorieStore, now: Date = Date()) -> Bool {
        guard let folder = Self.resolveFolder(from: defaults.data(forKey: Keys.bookmark)) else {
            lastError = String(localized: "Папка для копий недоступна — выбери её заново.")
            return false
        }
        let accessed = folder.startAccessingSecurityScopedResource()
        defer { if accessed { folder.stopAccessingSecurityScopedResource() } }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(store.makeBackup())
            try data.write(to: folder.appendingPathComponent(Self.filename(for: now)), options: .atomic)
            prune(in: folder)
            lastBackupDate = now
            defaults.set(now, forKey: Keys.lastDate)
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            Self.logger.error("копия не записалась: \(error)")
            return false
        }
    }

    private func prune(in folder: URL) {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return }
        for name in Self.obsoleteBackups(among: names) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
    }

    private static func resolveFolder(from bookmark: Data?) -> URL? {
        guard let bookmark else { return nil }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark,
                                 options: [],
                                 relativeTo: nil,
                                 bookmarkDataIsStale: &isStale) else { return nil }
        return url
    }
}
