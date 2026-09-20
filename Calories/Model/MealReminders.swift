import Foundation
import UserNotifications
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
    static let snoozeAction = "MEAL_SNOOZE"
    static let skipAction = "MEAL_SKIP"
    static let snooze: TimeInterval = 30 * 60
    /// Префикс идентификаторов: по нему снимаются старые напоминания,
    /// не трогая обычные (завтрак, обед, ужин) из настроек.
    static let prefix = "meal-window-"

    static var notificationCategory: UNNotificationCategory {
        UNNotificationCategory(
            identifier: category,
            actions: [
                UNNotificationAction(identifier: snoozeAction,
                                     title: String(localized: "Отложить на 30 минут"),
                                     options: []),
                UNNotificationAction(identifier: skipAction,
                                     title: String(localized: "Пропустить"),
                                     options: []),
            ],
            intentIdentifiers: [],
            options: []
        )
    }

    /// Переставить напоминания под текущее расписание.
    ///
    /// Триггеры повторяются каждый день: времена окон заданы подъёмом и отбоем,
    /// а не тем, что съедено, поэтому пересчитывать их ежедневно незачем.
    /// Сколько калорий на окно, известно только в момент показа — поэтому
    /// текст говорит про приём, а число человек видит в приложении.
    static func reschedule(settings: MealScheduleSettings, center: UNUserNotificationCenter = .current()) {
        center.getPendingNotificationRequests { pending in
            let ours = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: ours)

            guard settings.isEnabled else { return }
            let times = MealSchedule.times(wake: settings.today(settings.wake),
                                           sleep: settings.today(settings.sleep),
                                           count: settings.count)
            let calendar = Calendar.current
            for (index, time) in times.enumerated() {
                let content = UNMutableNotificationContent()
                content.title = String(format: String(localized: "Приём %1$lld из %2$lld"),
                                       index + 1, times.count)
                content.body = String(localized: "Окно открылось — запиши, что ешь.")
                content.sound = .default
                content.categoryIdentifier = category
                let parts = calendar.dateComponents([.hour, .minute], from: time)
                let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: true)
                center.add(UNNotificationRequest(identifier: "\(prefix)\(index)",
                                                 content: content, trigger: trigger))
            }
            logger.info("расписание приёмов: \(times.count) напоминаний")
        }
    }

    /// Отложить окно: то же напоминание через полчаса, один раз.
    static func snooze(_ content: UNNotificationContent, center: UNUserNotificationCenter = .current()) {
        let copy = content.mutableCopy() as? UNMutableNotificationContent ?? UNMutableNotificationContent()
        copy.categoryIdentifier = category
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: snooze, repeats: false)
        center.add(UNNotificationRequest(identifier: "\(prefix)snoozed-\(UUID().uuidString)",
                                         content: copy, trigger: trigger))
    }
}
