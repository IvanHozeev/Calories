import Testing
import Foundation
@testable import Calories

/// Разбор отчётов о сбоях.
///
/// Получить настоящий отчёт в тесте нельзя — его отдаёт система, и только на
/// устройстве. Зато можно разобрать записанный, а разбор и есть то место, где
/// ошибиться легче всего: формат принадлежит системе и меняется с версиями.
struct DiagnosticsTests {

    /// Выгрузка в том виде, в каком её отдаёт MetricKit, — укороченная до
    /// того, что мы читаем.
    private let payload = """
    {
      "crashDiagnostics": [
        {
          "diagnosticMetaData": {
            "exceptionType": 1,
            "signal": 5,
            "terminationReason": "Namespace SIGNAL, Code 5",
            "appVersion": "1.0"
          }
        }
      ],
      "hangDiagnostics": [
        { "diagnosticMetaData": { "hangDuration": "4.2 s" } }
      ],
      "diskWriteExceptionDiagnostics": [
        { "diagnosticMetaData": { "writesCaused": "1.2 MB" } }
      ]
    }
    """.data(using: .utf8)!

    @Test func aCrashIsReadWithItsReason() throws {
        let reports = Diagnostics.reports(fromPayload: payload)
        let crash = try #require(reports.first { $0.kind == .crash })
        #expect(crash.detail.contains("SIGNAL"))
        #expect(crash.detail.contains("exception 1"))
        #expect(crash.detail.contains("signal 5"))
    }

    @Test func aHangIsReadWithItsDuration() throws {
        let hang = try #require(Diagnostics.reports(fromPayload: payload).first { $0.kind == .hang })
        #expect(hang.detail == "4.2 s")
    }

    /// Расход диска и батареи — метрики, а не сбои: в списке сбоев им не место.
    @Test func metricsAreNotFailures() {
        #expect(Diagnostics.reports(fromPayload: payload).count == 2)
    }

    /// Формат принадлежит системе и меняется с версиями. Падать на разборе
    /// отчёта о падении — это уже смешно.
    @Test func nonsenseIsIgnoredQuietly() {
        #expect(Diagnostics.reports(fromPayload: Data("не json".utf8)).isEmpty)
        #expect(Diagnostics.reports(fromPayload: Data("{}".utf8)).isEmpty)
        #expect(Diagnostics.reports(fromPayload: Data(#"{"crashDiagnostics":[{}]}"#.utf8)).count == 1)
    }

    /// Пять последних: отчёт нужен, чтобы понять, что происходит сейчас, а не
    /// чтобы вести летопись.
    @Test func onlyTheLastFewAreKept() {
        let now = Date()
        let many = (0..<12).map {
            Diagnostics.Report(date: now.addingTimeInterval(Double(-$0) * 3600),
                               kind: .crash, detail: "\($0)")
        }
        let kept = Diagnostics.trimmed(many)
        #expect(kept.count == Diagnostics.keepLast)
        // Новые сверху: старый сбой интересен меньше свежего.
        #expect(kept.first?.detail == "0")
    }
}
