import Foundation
import Observation

/// Настройки кашрута: включён ли счёт и по какому обычаю считать.
///
/// Живут в UserDefaults, а не в дневнике: это настройка человека, а не его
/// данные, и спрашивать её будут и «Сегодня», и Живая активность, и строка
/// продукта — то есть отовсюду, где дневника под рукой может не быть.
///
/// Один экземпляр на приложение, как у расписания приёмов: значения читаются
/// при создании, и два экземпляра разошлись бы навсегда — тумблер писал бы в
/// свой, а экран смотрел бы в своё, прочитанное на запуске.
@Observable
final class KosherSettings {
    static let enabledKey = "kosher_on"
    static let afterMeatKey = "kosher_after_meat"
    static let afterDairyKey = "kosher_after_dairy"
    static let hardCheeseKey = "kosher_hard_cheese_like_meat"
    static let warnsMixingKey = "kosher_warns_mixing"

    @MainActor static let shared = KosherSettings()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: Self.enabledKey)
        // Шесть часов по умолчанию — обычай большинства общин. Но именно
        // по умолчанию: обычай у человека может быть другой, и приложение
        // его не выбирает.
        let meat = defaults.integer(forKey: Self.afterMeatKey)
        afterMeat = KosherCustom.afterMeatOptions.contains(meat) ? meat : 360
        // Ноль — настоящее значение, а не «не задано»: по букве закона после
        // молочного ждать не нужно вовсе. Поэтому отсутствие ключа и ноль
        // здесь означают одно и то же, и различать их незачем.
        let dairy = defaults.integer(forKey: Self.afterDairyKey)
        afterDairy = KosherCustom.afterDairyOptions.contains(dairy) ? dairy : 0
        // Умолчания — истина: твёрдый сыр ждут как мясо, и о смешении
        // предупреждают. Выключить можно, но тот, кто включил кашрут, вряд ли
        // хочет, чтобы приложение промолчало о курице со сливками.
        hardCheeseLikeMeat = defaults.object(forKey: Self.hardCheeseKey) as? Bool ?? true
        warnsMixing = defaults.object(forKey: Self.warnsMixingKey) as? Bool ?? true
    }

    var isEnabled: Bool { didSet { defaults.set(isEnabled, forKey: Self.enabledKey) } }
    var afterMeat: Int { didSet { defaults.set(afterMeat, forKey: Self.afterMeatKey) } }
    var afterDairy: Int { didSet { defaults.set(afterDairy, forKey: Self.afterDairyKey) } }
    var hardCheeseLikeMeat: Bool { didSet { defaults.set(hardCheeseLikeMeat, forKey: Self.hardCheeseKey) } }
    /// Говорить ли о мясном с молочным в одной тарелке.
    var warnsMixing: Bool { didSet { defaults.set(warnsMixing, forKey: Self.warnsMixingKey) } }

    /// То же самое в виде, в котором это нужно счётчику.
    var custom: KosherCustom {
        KosherCustom(afterMeat: afterMeat, afterDairy: afterDairy,
                     hardCheeseLikeMeat: hardCheeseLikeMeat)
    }
}

// MARK: - Названия

extension KosherStatus {
    var title: String {
        switch self {
        case .meat:    return String(localized: "Мясное")
        case .dairy:   return String(localized: "Молочное")
        case .parve:   return String(localized: "Парве")
        case .unknown: return String(localized: "Неизвестно")
        }
    }

    /// Значок строки: мясное вилкой, молочное каплей, парве листом.
    var symbol: String {
        switch self {
        case .meat:    return "fork.knife"
        case .dairy:   return "drop"
        case .parve:   return "leaf"
        case .unknown: return "questionmark"
        }
    }
}

enum KosherWaitText {
    /// Обычай словами: «6 часов», «5 ч 30 мин», «30 минут», «Не ждать».
    ///
    /// Часы и минуты порознь, а не «330 минут»: обычай человек знает в часах,
    /// и узнать свой он должен с первого взгляда.
    static func title(minutes: Int) -> String {
        if minutes == 0 { return String(localized: "Не ждать") }
        if minutes % 60 == 0 {
            return String(format: String(localized: "%lld ч"), minutes / 60)
        }
        if minutes < 60 {
            return String(format: String(localized: "%lld мин"), minutes)
        }
        return String(format: String(localized: "%1$lld ч %2$lld мин"), minutes / 60, minutes % 60)
    }
}
