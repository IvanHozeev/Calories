import Testing
import Foundation
@testable import Calories

/// Приёмка ТЗ-6: вердикт фазы по силе.
struct StrengthVerdictTests {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)
    private var end: Date { start.addingTimeInterval(70 * 86_400) }

    private func point(_ date: Date, _ index: Double) -> StrengthVerdict.Point { .init(date: date, index: index) }

    private func decode(_ json: String) throws -> GymBridge.State {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(GymBridge.State.self, from: Data(json.utf8))
    }

    // 1
    @Test func aStateWithoutStrengthDecodes() throws {
        let state = try decode(#"{"date":"2026-11-13T10:00:00Z"}"#)
        #expect(state.strength == nil)
    }

    // 2
    @Test func aStateWithTenPointsDecodes() throws {
        let points = (0..<10).map { #"{"date":"2026-09-\#(String(format: "%02d", $0 + 1))T10:00:00Z","index":\#(400 + $0)}"# }
        let json = #"{"date":"2026-11-13T10:00:00Z","strength":{"index":409,"history":[\#(points.joined(separator: ","))]}}"#
        let state = try decode(json)
        #expect(state.strength?.history?.count == 10)
    }

    private func verdict(_ from: Double, _ to: Double) -> (Double?, StrengthVerdict.Outcome?) {
        let change = StrengthVerdict.change(history: [point(start, from), point(end, to)], from: start, to: end)
        return (change, change.map(StrengthVerdict.outcome))
    }

    // 3
    @Test func aThreePercentDropIsASlightLoss() {
        let (change, outcome) = verdict(400, 388)
        #expect(change.map { abs($0 + 3) < 0.0001 } == true)
        #expect(outcome == .slightLoss)
    }

    // 4
    @Test func onePercentUpIsKept() {
        let (change, outcome) = verdict(400, 404)
        #expect(change.map { abs($0 - 1) < 0.0001 } == true)
        #expect(outcome == .kept)
    }

    // 5
    @Test func sixPercentDownIsALoss() {
        let (change, outcome) = verdict(400, 376)
        #expect(change.map { abs($0 + 6) < 0.0001 } == true)
        #expect(outcome == .loss)
    }

    // 6
    @Test func threePercentUpIsAGain() {
        let (change, outcome) = verdict(400, 412)
        #expect(change.map { abs($0 - 3) < 0.0001 } == true)
        #expect(outcome == .gain)
    }

    // 7
    @Test func aPointNineDaysAwayIsTooFar() {
        let history = [point(start.addingTimeInterval(-9 * 86_400), 400), point(end, 390)]
        #expect(StrengthVerdict.change(history: history, from: start, to: end) == nil)
    }

    // 8
    @Test func exactlyTwoAndFivePercentFallOnTheMildSide() {
        #expect(StrengthVerdict.outcome(changePercent: -2.0) == .kept)
        #expect(StrengthVerdict.outcome(changePercent: -5.0) == .slightLoss)
        #expect(StrengthVerdict.outcome(changePercent: -2.0000001) == .kept)
    }

    // 9
    @Test func theNearestPointWins() {
        let history = [point(start, 400),
                       point(end.addingTimeInterval(-6 * 86_400), 380),
                       point(end.addingTimeInterval(-2 * 86_400), 396)]
        let change = StrengthVerdict.change(history: history, from: start, to: end)
        #expect(change.map { abs($0 + 1) < 0.0001 } == true)
    }
}
