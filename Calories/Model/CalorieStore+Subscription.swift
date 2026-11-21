import Foundation

/// Подписка, бандл с GymLogger и план, отложенный до подписки.
///
/// Своего пробного периода у приложения больше нет. Был: две недели плана без
/// карты, а у подписки в App Store — ещё неделя сверху. Два пробных периода
/// подряд читались как «бесплатно, а потом посмотрим», и ни один не просил
/// решения. Теперь он один — месяц в App Store, с картой: его предлагают на
/// финише онбординга, и App Store сам следит, чтобы он был один раз.
extension CalorieStore {

    /// Доступ к платному: подписка (в том числе пробный месяц) или купленная пара.
    /// Запись меняет только покупку.
    var isPremium: Bool {
        get { hasPurchasedPremium || bundleUnlocked }
        set { hasPurchasedPremium = newValue }
    }

    // MARK: - План до подписки

    /// План из онбординга, который ждёт подписки.
    ///
    /// Человек ответил на вопросы, увидел свой маршрут и нажал «Не сейчас».
    /// Выбрасывать маршрут нельзя: оформит подписку через неделю из профиля —
    /// и должен получить тот же план, а не проходить опрос заново.
    var pendingPlan: Plan? {
        defaults.data(forKey: Keys.pendingPlan).flatMap { try? JSONDecoder().decode(Plan.self, from: $0) }
    }

    func keepPendingPlan(_ plan: Plan) {
        guard let data = try? JSONEncoder().encode(plan) else { return }
        defaults.set(data, forKey: Keys.pendingPlan)
    }

    /// Запустить отложенный план, когда появился доступ.
    ///
    /// Старт — сегодня и с сегодняшним весом: маршрут, начатый задним числом,
    /// с первого же дня показывал бы отставание, которого не было.
    func adoptPendingPlanIfNeeded(now: Date = Date()) {
        guard isPremium, let pending = pendingPlan else { return }
        defaults.removeObject(forKey: Keys.pendingPlan)
        guard plan == nil else { return }
        var rebased = pending
        rebased.startDate = Calendar.current.startOfDay(for: now)
        rebased.startWeightKg = weightKg ?? pending.startWeightKg
        startPlan(rebased)
    }
}
