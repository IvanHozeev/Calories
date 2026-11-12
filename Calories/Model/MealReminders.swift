import Foundation
// Центр уведомлений — тип из старого мира без пометок о пересылке между
// нитями, а его колбэки приходят не на главном акторе. Пометка на импорте
// говорит компилятору ровно это, вместо того чтобы глушить предупреждения
// поштучно в каждом замыкании.
@preconcurrency import UserNotifications
import OSLog

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Calories", category: "meal-reminders")

/// Напоминания об окнах приёмов пищи.
///
/// Обычное напоминание «запиши обед» приходит в одно и то же время и ничего не
/// знает о дне. Это — знает: оно приходит к началу своего окна и говорит,
/// сколько на него отведено сейчас, с учётом съеденного и пропущенного.
///
/// Ответить на него можно прямо из шторки: отложить на полчаса, пропустить или
/// открыть запись еды. Пропуск ничего не ломает — калории окна разойдутся по
/// оставшимся сами, — поэтому «пропустить» просто снимает напоминание, а не
/// заводит где-то отдельное состояние.
enum MealReminders {
    static let category = "MEAL_WINDOW"
    /// Тот же приём, но с кнопкой «Съел как обычно»: её показываем только когда
    /// у этого окна есть привычный приём. Кнопка, которая в половине случаев
    /// отвечает «записывать нечего», хуже, чем её отсутствие.
    static let categoryWithUsual = "MEAL_WINDOW_USUAL"
    static let snoozeAction = "MEAL_SNOOZE"
    static let skipAction = "MEAL_SKIP"
    static let usualAction = "MEAL_USUAL"
    /// Ключ в `userInfo` уведомления: какое окно оно открывает.
    static let periodKey = "period"
    static let snooze: TimeInterval = 30 * 60
    /// Префикс идентификаторов: по нему снимаются старые напоминания,
    /// не трогая обычные (завтрак, обед, ужин) из настроек.
    static let prefix = "meal-window-"

    static var notificationCategory: UNNotificationCategory {
        UNNotificationCategory(
            identifier: category,
            actions: [snoozeButton, skipButton],
            intentIdentifiers: [],
            options: []
        )
    }

    /// С третьей кнопкой: записать привычный приём этого окна, не открывая
    /// приложение. Идёт первой, потому что это единственное действие, которое
    /// закрывает дело; отложить и пропустить — способы его не делать.
    static var notificationCategoryWithUsual: UNNotificationCategory {
        UNNotificationCategory(
            identifier: categoryWithUsual,
            actions: [
                UNNotificationAction(identifier: usualAction,
                                     title: String(localized: "Съел как обычно"),
                                     options: []),
                snoozeButton, skipButton,
            ],
            intentIdentifiers: [],
            options: []
        )
    }

    static var notificationCategories: Set<UNNotificationCategory> {
        [notificationCategory, notificationCategoryWithUsual]
    }

    private static var snoozeButton: UNNotificationAction {
        UNNotificationAction(identifier: snoozeAction,
                             title: String(localized: "Отложить на 30 минут"),
                             options: [])
    }

    private static var skipButton: UNNotificationAction {
        UNNotificationAction(identifier: skipAction,
                             title: String(localized: "Пропустить"),
                             options: [])
    }

    /// Переставить напоминания под текущее расписание.
    ///
    /// Триггеры повторяются каждый день: времена окон заданы подъёмом и отбоем,
    /// а не тем, что съедено, поэтому пересчитывать их ежедневно незачем.
    /// Сколько калорий на окно, известно только в момент показа — поэтому
    /// текст говорит про приём, а число человек видит в приложении.
    @MainActor
    static func reschedule(settings: MealScheduleSettings,
                           store: CalorieStore? = nil,
                           center: UNUserNotificationCenter = .current()) {
        // Всё, что зависит от дневника, считаем здесь и сейчас: внутрь
        // замыкания центра уведомлений главный актор не заходит.
        let plan = store.map { plannedMeals(settings: settings, store: $0) } ?? []

        let weighInTime = settings.remindsWeighIn ? settings.today(settings.weighIn) : nil

        center.getPendingNotificationRequests { pending in
            let ours = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: ours)

            if let weighInTime {
                let content = UNMutableNotificationContent()
                content.title = String(localized: "Взвешивание")
                content.body = String(localized: "Натощак, до еды и питья — так утро сравнимо с утром.")
                content.sound = .default
                let parts = Calendar.current.dateComponents([.hour, .minute], from: weighInTime)
                center.add(UNNotificationRequest(identifier: "\(prefix)weighIn",
                                                 content: content,
                                                 trigger: UNCalendarNotificationTrigger(dateMatching: parts,
                                                                                        repeats: true)))
            }

            guard settings.isEnabled else { return }
            let times = MealSchedule.times(wake: settings.today(settings.wake),
                                           sleep: settings.today(settings.sleep),
                                           count: settings.count,
                                           settings: settings)
            let calendar = Calendar.current
            for (index, time) in times.enumerated() {
                let content = UNMutableNotificationContent()
                let meal = index < plan.count ? plan[index] : nil
                // Имя приёма, а не «приём 3 из 5»: человек знает, что такое
                // полдник, и не считает приёмы по номерам.
                content.title = meal?.title ?? String(format: String(localized: "Приём %1$lld из %2$lld"),
                                                      index + 1, times.count)
                // Тело — только когда ему есть что добавить к заголовку:
                // сколько калорий на приём и чем его обычно закрывают.
                // «Окно открылось — запиши, что ешь» не добавляло ничего:
                // уведомление и так пришло, и так названо.
                content.body = meal.map(body(for:)) ?? ""

                content.sound = .default
                content.categoryIdentifier = meal?.hasUsualMeal == true ? categoryWithUsual : category
                if let period = meal?.period {
                    content.userInfo = [periodKey: period.rawValue]
                }
                let parts = calendar.dateComponents([.hour, .minute], from: time)
                let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: true)
                center.add(UNNotificationRequest(identifier: "\(prefix)\(index)",
                                                 content: content, trigger: trigger))
            }
            // Взвешивание — своим напоминанием и без оглядки на тумблер
            // приёмов: весы нужны и тому, кто день на приёмы не делит.
            logger.info("расписание приёмов: \(times.count) напоминаний")
        }
    }

    /// Что известно о приёме заранее: как он называется, сколько на него
    /// отведено по плану и что человек обычно ест на такие калории.
    struct PlannedMeal {
        let title: String
        let calories: Int
        let suggestion: String?
        /// Окно дня, которому соответствует приём: по нему кнопка «Съел как
        /// обычно» находит, что записывать.
        var period: MealPeriod? = nil
        /// Есть ли у этого окна привычный приём — то есть что записывать.
        var hasUsualMeal = false
    }

    /// Текст напоминания: число и пример.
    ///
    /// Число берём плановое, а не остаток на момент показа: остаток зависит от
    /// того, что уже съедено, а содержимое уведомления фиксируется при
    /// постановке — и назавтра показывало бы вчерашнюю арифметику. Доля приёма
    /// от дневной нормы такой беды не знает: она одна и та же изо дня в день.
    /// Текст собирается в колбэке центра уведомлений, то есть вне главного
    /// актора: состояния тут нет, только подстановка чисел в строку.
    nonisolated static func body(for meal: PlannedMeal) -> String {
        guard let suggestion = meal.suggestion else {
            return String(format: String(localized: "%lld ккал по плану"), meal.calories)
        }
        return String(format: String(localized: "%1$lld ккал по плану. Например: %2$@"),
                      meal.calories, suggestion)
    }

    /// Плановые приёмы дня: сколько отведено каждому и чем его обычно закрывают.
    @MainActor
    static func plannedMeals(settings: MealScheduleSettings, store: CalorieStore) -> [PlannedMeal] {
        let periods = MealSchedule.periods(count: settings.count)
        let totalWeight = periods.reduce(0.0) { $0 + MealSchedule.weight(of: $1) }
        guard totalWeight > 0, store.adaptedTodayGoal > 0 else { return [] }

        return periods.map { period in
            let calories = Int((Double(store.adaptedTodayGoal) * MealSchedule.weight(of: period) / totalWeight).rounded())
            return PlannedMeal(
                title: String(localized: String.LocalizationValue(period.rawValue)),
                calories: calories,
                suggestion: store.mealSuggestions(remaining: calories).first?.name,
                period: period,
                hasUsualMeal: !store.usualMeals(period: period).isEmpty)
        }
    }

    /// Отложить окно: то же напоминание через полчаса, один раз.
    static func snooze(_ content: UNNotificationContent, center: UNUserNotificationCenter = .current()) {
        let copy = content.mutableCopy() as? UNMutableNotificationContent ?? UNMutableNotificationContent()
        if copy.categoryIdentifier.isEmpty { copy.categoryIdentifier = category }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: snooze, repeats: false)
        center.add(UNNotificationRequest(identifier: "\(prefix)snoozed-\(UUID().uuidString)",
                                         content: copy, trigger: trigger))
    }

    /// Записать привычный приём окна: то, что человек чаще всего собирал в это
    /// время за последние полгода, — тем же составом, что и «Как обычно» на
    /// экране добавления. Возвращает записанное, nil — привычного приёма нет
    /// и ничего не записано.
    @MainActor
    @discardableResult
    static func logUsualMeal(period: MealPeriod?, store: CalorieStore, at date: Date = Date()) -> UsualMeal.Suggestion? {
        guard let usual = store.usualMeals(period: period).first else { return nil }
        store.add(name: usual.parts.map(\.name).joined(separator: ", "),
                  calories: usual.calories,
                  macros: usual.macros,
                  grams: nil,
                  date: date,
                  components: usual.parts)
        return usual
    }

    /// Ответ на кнопку «Съел как обычно»: записать и сказать, что записано.
    /// Приложение при этом не открывается, поэтому подтверждение — отдельное
    /// уведомление: без него человек не узнал бы, сработала ли кнопка.
    @MainActor
    static func handleUsualAction(period: MealPeriod?, store: CalorieStore?,
                                  center: UNUserNotificationCenter = .current()) {
        let content = UNMutableNotificationContent()
        if let store, let usual = logUsualMeal(period: period, store: store) {
            content.title = String(localized: "Записано")
            content.body = String(format: String(localized: "%1$@: %2$lld ккал"),
                                  usual.parts.map(\.name).joined(separator: ", "), usual.calories)
        } else {
            content.title = String(localized: "Ничего не записано")
            content.body = String(localized: "Привычного приёма для этого окна пока нет. Запиши его в приложении.")
        }
        center.add(UNNotificationRequest(identifier: "\(prefix)logged-\(UUID().uuidString)",
                                         content: content, trigger: nil))
    }
}
