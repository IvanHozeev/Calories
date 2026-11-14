import Foundation

/// Что фаза сделала с силой — по истории индекса силы из GymLogger.
///
/// Дневников питания и дневников тренировок много, а оценить сушку по тому,
/// что она сделала с силой, может только пара приложений одного автора. Вес
/// и жир говорят, сколько ушло; сила — какой ценой.
nonisolated enum StrengthVerdict {
    enum Outcome: Equatable, Sendable {
        case kept, slightLoss, loss, gain

        var title: String {
            switch self {
            case .kept: return String(localized: "Сила сохранена")
            case .slightLoss: return String(localized: "Сила немного просела")
            case .loss: return String(localized: "Сила заметно просела")
            case .gain: return String(localized: "Сила выросла")
            }
        }
    }

    typealias Point = GymBridge.State.Strength.Point

    /// Насколько далеко от даты может стоять точка истории.
    static let reach: TimeInterval = 7 * 86_400

    /// Изменение индекса в процентах между датами, или nil, если рядом с
    /// началом или концом нет точки — тогда о силе ничего не говорим.
    static func change(history: [Point], from: Date, to: Date) -> Double? {
        guard let start = nearest(history, to: from), let end = nearest(history, to: to),
              start.index > 0 else { return nil }
        return (end.index - start.index) / start.index * 100
    }

    /// Пороги: −2% и −5%. Изменение округляется до десятой: иначе ровно −2,0
    /// могло бы посчитаться как −2,0000001 и уйти не в ту сторону.
    static func outcome(changePercent: Double) -> Outcome {
        let x = (changePercent * 10).rounded() / 10
        if x > 2 { return .gain }
        if x >= -2 { return .kept }
        if x >= -5 { return .slightLoss }
        return .loss
    }

    private static func nearest(_ history: [Point], to date: Date) -> Point? {
        history
            .filter { abs($0.date.timeIntervalSince(date)) <= reach }
            .min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }
}

extension CalorieStore {
    /// Изменение силы между датами по данным GymLogger — или nil.
    func strengthChange(from: Date, to: Date) -> (percent: Double, outcome: StrengthVerdict.Outcome)? {
        guard let history = gymState?.strength?.history,
              let percent = StrengthVerdict.change(history: history, from: from, to: to) else { return nil }
        return (percent, StrengthVerdict.outcome(changePercent: percent))
    }
}
