import Foundation
import UserNotifications
import Observation

struct ReminderItem: Identifiable {
    let id: String
    let title: String
    let notificationBody: String
    var isEnabled: Bool
    var time: Date
}

@Observable
@MainActor
final class ReminderStore {
    var reminders: [ReminderItem]
    var authStatus: UNAuthorizationStatus = .notDetermined
    var appEnabled: Bool {
        didSet { defaults.set(appEnabled, forKey: "reminders_app_enabled") }
    }

    private let center = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard

    init() {
        appEnabled = UserDefaults.standard.object(forKey: "reminders_app_enabled") as? Bool ?? false
        reminders = [
            ReminderItem(
                id: "breakfast",
                title: "Завтрак",
                notificationBody: "Не забудь записать завтрак 🌅",
                isEnabled: UserDefaults.standard.bool(forKey: "reminder_breakfast_on"),
                time: Self.loadTime(key: "reminder_breakfast_time", hour: 8, minute: 0)
            ),
            ReminderItem(
                id: "lunch",
                title: "Обед",
                notificationBody: "Время занести обед 🍽️",
                isEnabled: UserDefaults.standard.bool(forKey: "reminder_lunch_on"),
                time: Self.loadTime(key: "reminder_lunch_time", hour: 13, minute: 0)
            ),
            ReminderItem(
                id: "dinner",
                title: "Ужин",
                notificationBody: "Не забудь внести ужин и закрыть день 🌙",
                isEnabled: UserDefaults.standard.bool(forKey: "reminder_dinner_on"),
                time: Self.loadTime(key: "reminder_dinner_time", hour: 19, minute: 0)
            ),
        ]
        Task { await refreshAuthStatus() }
    }

    private static func loadTime(key: String, hour: Int, minute: Int) -> Date {
        if let interval = UserDefaults.standard.object(forKey: key) as? TimeInterval {
            return Date(timeIntervalSince1970: interval)
        }
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        return Calendar.current.date(from: comps) ?? Date()
    }

    func enableNotifications() async {
        switch authStatus {
        case .notDetermined:
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                authStatus = granted ? .authorized : .denied
                if granted {
                    appEnabled = true
                    rescheduleAll()
                }
            } catch {}
        case .authorized:
            appEnabled = true
            rescheduleAll()
        default:
            break
        }
    }

    func disableNotifications() {
        appEnabled = false
        center.removePendingNotificationRequests(withIdentifiers: reminders.map(\.id))
    }

    func refreshAuthStatus() async {
        let settings = await center.notificationSettings()
        authStatus = settings.authorizationStatus
    }

    func saveAndReschedule() {
        for reminder in reminders {
            defaults.set(reminder.isEnabled, forKey: "reminder_\(reminder.id)_on")
            defaults.set(reminder.time.timeIntervalSince1970, forKey: "reminder_\(reminder.id)_time")
        }
        rescheduleAll()
    }

    func rescheduleAll() {
        center.removePendingNotificationRequests(withIdentifiers: reminders.map(\.id))
        guard appEnabled else { return }
        for reminder in reminders where reminder.isEnabled {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.notificationBody
            content.sound = .default
            let comps = Calendar.current.dateComponents([.hour, .minute], from: reminder.time)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            center.add(UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger))
        }
    }
}
