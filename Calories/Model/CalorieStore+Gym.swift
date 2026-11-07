import Foundation

/// Зал (GymLogger) и бандл с ним: снимок активности и признак покупки пары.
extension CalorieStore {

    /// Что сейчас в зале: разгрузка, тип дня, объём недели. nil — соседнего
    /// приложения нет или оно молчит.
    ///
    /// Снимок держим в памяти, а не читаем при каждом обращении: к нему
    /// ходят и вердикт недели, и подсказки дня, а меняется он несколько раз
    /// в сутки.
    private(set) var gymState: GymBridge.State?

    /// Имя сегодняшней тяжёлой тренировки — или nil, когда день лёгкий,
    /// это отдых, или о дне ничего не известно.
    var gymHeavyDayName: String? {
        guard GymBridge.isHeavyDay(gymState) == true else { return nil }
        return GymBridge.todayName(gymState)
    }

    /// Перечитать снимок из зала. Зовётся там же, где права: тренировку
    /// закрывают в соседнем приложении, пока мы в фоне.
    func refreshGymState() {
        gymState = GymBridge.read(defaults: groupDefaults)
    }

    /// Перечитать права, пришедшие от соседа.
    ///
    /// Вызывается при запуске и при каждом возвращении в приложение: покупку
    /// совершают в GymLogger, пока мы в фоне, и узнать об этом иначе неоткуда.
    func refreshSharedEntitlements() {
        let bundle = (groupDefaults?.bool(forKey: "shared_is_bundle") ?? false)
            || (groupDefaults?.bool(forKey: "gym_is_bundle") ?? false)
        guard bundle != bundleUnlocked else { return }
        bundleUnlocked = bundle
    }

    /// Куплена пара приложений — здесь или в GymLogger.
    ///
    /// Разблокировка по соседству, а не общая подписка: она живёт в общей
    /// папке и работает, пока оба приложения стоят на одном телефоне. Чек
    /// соседа мы не проверяем и проверить не можем, поэтому это подарок
    /// сверху, а не право. Сосед удалён и флага нет — приложение возвращается
    /// к собственной покупке, а не запирается и не ругается.
    ///
    /// За купленный отдельно Calories GymLogger не открывается и наоборот:
    /// открывает только бандл, иначе продаём одно, а отдаём два.
    var bundleUnlocked: Bool {
        get { _bundleUnlocked }
        set { _bundleUnlocked = newValue }
    }

    /// Хранимое свойство bundleUnlocked.
    private var _bundleUnlocked: Bool = false
}
