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

    /// Пробный период был и кончился, а покупки нет — пэйвол говорит об этом прямо.
    var trialEnded: Bool {
        trialStartedAt != nil && !isTrialActive && !hasPurchasedPremium
    }

    /// Что человек успел за пробный период: дни с записями и сдвиг веса по тренду.
    var trialSummary: (loggedDays: Int, weightChangeKg: Double?)? {
        guard let start = trialStartedAt, let end = trialEndsAt else { return nil }
        // Обе границы — в сутках. Записи сложены по дням, и сравнивать день с
        // мгновением нельзя: пробный период кончается в тот же час, в который
        // начался, а день, в который он кончился, начался до этого часа — и
        // попадал в итог целиком, вместе с ужином, съеденным уже после конца.
        let calendar = Calendar.current
        let from = calendar.startOfDay(for: start)
        let until = calendar.startOfDay(for: end)
        let days = entriesByDay.keys.filter { $0 >= from && $0 < until }.count
        var change: Double?
        if let plan, let trend = weightKg { change = trend - plan.startWeightKg }
        return (days, change)
    }

    /// Начать пробный период, если его ещё не было.
    func startTrialIfNeeded(now: Date = Date()) {
        guard trialStartedAt == nil else { return }
        trialStartedAt = now
        defaults.set(now, forKey: Keys.trialStarted)
    }
}
