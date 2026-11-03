import Foundation

/// Сбои и зависания, о которых система рассказала приложению.
///
/// Приложение падает не только у разработчика. У постороннего человека оно
/// может не открыться вовсе — и узнать об этом было неоткуда: своего сервера у
/// приложения нет, Xcode к чужому телефону не подключён, а в Organizer отчёты
/// приходят только из App Store, которого тоже нет.
///
/// MetricKit — единственный путь, не требующий ни того, ни другого: система
/// сама отдаёт приложению разбор его падений, один раз в сутки и при запуске
/// после сбоя. Отчёт остаётся на устройстве; человек может его отправить.
///
/// Разбор — чистая функция над JSON, потому что проверять надо именно её:
/// получить настоящий отчёт в тесте нельзя, а разобрать записанный — можно.
enum Diagnostics {
    /// Сколько отчётов держим. Пять: отчёт нужен, чтобы понять, что
    /// происходит сейчас, а не чтобы вести летопись.
    static let keepLast = 5

    struct Report: Identifiable, Codable, Equatable, Sendable {
        var id = UUID()
        /// Когда система отдала отчёт — не когда случился сбой: точного
        /// времени падения в отчёте нет.
        var date: Date
        var kind: Kind
        /// Чем система объясняет сбой: тип исключения, сигнал, причина
        /// завершения. Строкой, потому что показывать её человеку, а не
        /// разбирать дальше.
        var detail: String

        enum Kind: String, Codable, Sendable {
            case crash, hang
        }
    }

    /// Разбирает выгрузку MetricKit. Берём только падения и зависания: расход
    /// батареи и дисковые записи — это метрики, а не сбои, и в список к ним
    /// попадать не должны.
    ///
    /// Молчаливо пропускаем всё, чего не поняли: формат выгрузки принадлежит
    /// системе и меняется с версиями, а падать на разборе отчёта о падении —
    /// это уже смешно.
    static func reports(fromPayload data: Data, now: Date = Date()) -> [Report] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        var found: [Report] = []

        for crash in root["crashDiagnostics"] as? [[String: Any]] ?? [] {
            let meta = crash["diagnosticMetaData"] as? [String: Any] ?? [:]
            var parts: [String] = []
            if let reason = meta["terminationReason"] as? String, !reason.isEmpty {
                parts.append(reason)
            }
            if let type = meta["exceptionType"] {
                parts.append("exception \(type)")
            }
            if let signal = meta["signal"] {
                parts.append("signal \(signal)")
            }
            found.append(Report(date: now, kind: .crash,
                                detail: parts.isEmpty ? "—" : parts.joined(separator: " · ")))
        }

        for hang in root["hangDiagnostics"] as? [[String: Any]] ?? [] {
            let meta = hang["diagnosticMetaData"] as? [String: Any] ?? [:]
            let duration = meta["hangDuration"] as? String ?? "?"
            found.append(Report(date: now, kind: .hang, detail: duration))
        }

        return found
    }

    /// Последние отчёты: новые сверху, лишние отброшены.
    static func trimmed(_ reports: [Report], keepLast: Int = keepLast) -> [Report] {
        Array(reports.sorted { $0.date > $1.date }.prefix(keepLast))
    }
}
