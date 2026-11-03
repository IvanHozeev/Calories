import Foundation
import MetricKit
import Observation
import OSLog

/// Подписка на разбор сбоев от системы и то немногое, что с ним делают.
///
/// Отчёты живут в своём файле, а не в UserDefaults: их читают редко, а
/// занимать они могут килобайты. Настоящая выгрузка кладётся рядом целиком —
/// её человек и отправляет, если захочет: наш разбор годится, чтобы понять,
/// что сбой был, но не чтобы по нему чинить.
@Observable
@MainActor
final class DiagnosticsStore: NSObject, MXMetricManagerSubscriber {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Calories",
                                       category: "diagnostics")

    static let shared = DiagnosticsStore()

    private(set) var reports: [Diagnostics.Report] = []

    private let directory: URL
    private var listFile: URL { directory.appending(path: "reports.json") }

    init(directory: URL? = nil) {
        self.directory = directory ?? URL.applicationSupportDirectory.appending(path: "Diagnostics")
        super.init()
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        reports = (try? JSONDecoder().decode([Diagnostics.Report].self,
                                             from: Data(contentsOf: listFile))) ?? []
    }

    /// Начинает слушать. Зовётся один раз на запуске: система отдаёт разбор
    /// раз в сутки и сразу после запуска, следующего за падением.
    func start() {
        MXMetricManager.shared.add(self)
    }

    /// Выгрузки приходят не на главном потоке и не по нашему расписанию.
    nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let datas = payloads.map { $0.jsonRepresentation() }
        Task { @MainActor in self.record(datas) }
    }

    /// Метрики нам не нужны, но метод обязателен к реализации.
    nonisolated func didReceive(_ payloads: [MXMetricPayload]) {}

    func record(_ payloads: [Data], now: Date = Date()) {
        var found: [Diagnostics.Report] = []
        for data in payloads {
            found += Diagnostics.reports(fromPayload: data, now: now)
            // Выгрузку целиком кладём рядом: по нашей строке сбой не чинят,
            // а в ней есть стек.
            let file = directory.appending(path: "payload-\(Int(now.timeIntervalSince1970))-\(found.count).json")
            try? data.write(to: file)
        }
        guard !found.isEmpty else { return }
        reports = Diagnostics.trimmed(reports + found)
        save()
        Self.logger.notice("Получено отчётов о сбоях: \(found.count)")
    }

    /// Файлы выгрузок — то, что человек отправляет.
    var payloadFiles: [URL] {
        let all = (try? FileManager.default.contentsOfDirectory(at: directory,
                                                               includingPropertiesForKeys: nil)) ?? []
        return all.filter { $0.lastPathComponent.hasPrefix("payload-") }
    }

    func clear() {
        reports = []
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func save() {
        try? JSONEncoder().encode(reports).write(to: listFile)
    }
}
