import Foundation

/// Настройки расписания приёмов пищи: когда день начинается и кончается
/// и на сколько приёмов делить норму.
///
/// Живут в UserDefaults, а не в сторе: это настройка, а не данные дневника,
/// и читать её нужно из виджета-напоминаний и из самого расписания.
@Observable
final class MealScheduleSettings {
    static let enabledKey = "meal_schedule_on"
    static let wakeKey = "meal_schedule_wake"
    static let sleepKey = "meal_schedule_sleep"
    static let countKey = "meal_schedule_count"

    /// Один экземпляр на всё приложение.
    ///
    /// Значения читаются из UserDefaults один раз, при создании, — поэтому
    /// два экземпляра расходятся навсегда: тумблер в «Напоминаниях» писал в
    /// свой, а «Сегодня» смотрело в своё, прочитанное на запуске, и строка
    /// приёма не появлялась до перезапуска приложения.
    @MainActor static let shared = MealScheduleSettings()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: Self.enabledKey)
        wake = Self.time(defaults.object(forKey: Self.wakeKey) as? Date, hour: 7)
        sleep = Self.time(defaults.object(forKey: Self.sleepKey) as? Date, hour: 23)
        let stored = defaults.integer(forKey: Self.countKey)
        count = MealSchedule.allowedCounts.contains(stored) ? stored : 4
    }

    var isEnabled: Bool { didSet { defaults.set(isEnabled, forKey: Self.enabledKey) } }
    var wake: Date { didSet { defaults.set(wake, forKey: Self.wakeKey) } }
    var sleep: Date { didSet { defaults.set(sleep, forKey: Self.sleepKey) } }
    var count: Int { didSet { defaults.set(count, forKey: Self.countKey) } }

    /// Время сегодняшнего дня по сохранённым часам и минутам: в настройках
    /// хранится момент, а нужен он каждый день заново.
    func today(_ date: Date, now: Date = Date()) -> Date {
        let calendar = Calendar.current
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return calendar.date(bySettingHour: parts.hour ?? 7, minute: parts.minute ?? 0,
                             second: 0, of: now) ?? now
    }

    private static func time(_ stored: Date?, hour: Int) -> Date {
        if let stored { return stored }
        let calendar = Calendar.current
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
    }
}
