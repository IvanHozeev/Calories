import Foundation

/// Подписка, пробный период и бандл с GymLogger.
extension CalorieStore {

    /// Две недели, а не одна: первый вердикт «как идёт план» появляется примерно
    /// через две недели взвешиваний. Неделя кончалась бы раньше, чем человек
    /// увидит, за что платит.
    static let trialDays = 14

    /// Когда пробный период заканчивается.
    var trialEndsAt: Date? {
        trialStartedAt.flatMap { Calendar.current.date(byAdding: .day, value: Self.trialDays, to: $0) }
    }

    /// Пробный период ещё идёт.
    var isTrialActive: Bool {
        guard let end = trialEndsAt else { return false }
        return Date() < end
    }

    /// Сколько полных дней пробного периода осталось. nil — его нет или он кончился.
    var trialDaysLeft: Int? {
        guard isTrialActive, let end = trialEndsAt else { return nil }
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()),
                                                   to: Calendar.current.startOfDay(for: end)).day ?? 0
        return max(days, 0)
    }

    /// Доступ к платному: куплено, идёт пробный период или куплена пара.
    /// Запись меняет только покупку.
    var isPremium: Bool {
        get { hasPurchasedPremium || isTrialActive || bundleUnlocked }
        set { hasPurchasedPremium = newValue }
    }
}
