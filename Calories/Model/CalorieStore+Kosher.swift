import Foundation

/// Кашрут по дневнику: что было съедено и чего после этого ждут.
///
/// Запись дневника хранит имя, калории и состав — но не категорию и не
/// статус: состав снимается на момент записи, а продукт потом правят. Поэтому
/// статус, как и категорию, приходится собирать обратно по именам, и делается
/// это тем же способом, что в `categoryBreakdown`: продукт — собой, блюдо —
/// своими ингредиентами, склеенный приём — своими частями.
extension CalorieStore {

    /// Статус и признак твёрдого сыра для одного названия.
    ///
    /// Разложение, а не одно значение: у блюда из курицы со сливками мясное и
    /// молочное лежат в одной тарелке, и свести их к общему ответу — значит
    /// потерять ровно то, о чём надо сказать.
    func kosherParts(named name: String) -> [(status: KosherStatus, hardCheese: Bool)] {
        if let status = kosherByFoodName[name] {
            return [(status, hardCheeseFoodNames.contains(name))]
        }
        if let dish = dishes.first(where: { $0.name == name }) {
            return dish.ingredients.flatMap { kosherParts(named: $0.foodName) }
        }
        // Склеенное имя приёма: «Хала, Молоко, Whey Protein». Разбираем на
        // части только если их больше одной, иначе разбор вернёт то же имя и
        // мы пойдём по кругу.
        let parts = CalorieStore.joinedNameParts(name)
        if parts.count > 1 {
            return parts.flatMap { kosherParts(named: $0) }
        }
        return [(.unknown, false)]
    }

    /// Из чего состоит запись — с точки зрения кашрута.
    func kosherParts(of entry: FoodEntry) -> [(status: KosherStatus, hardCheese: Bool)] {
        entry.composition.flatMap { kosherParts(named: $0.name) }
    }

    /// Мясная запись, молочная или парве.
    func kosherStatus(of entry: FoodEntry) -> KosherStatus {
        KosherStatus.of(kosherParts(of: entry).map(\.status))
    }

    /// Мясное и молочное в одной записи.
    func isKosherMixed(_ entry: FoodEntry) -> Bool {
        KosherStatus.isMixed(kosherParts(of: entry).map(\.status))
    }

    /// Мясное и молочное в собираемом приёме — до того, как он записан.
    ///
    /// Черновик проверяется отдельно от записи, потому что сказать об этом
    /// надо раньше: после записи остаётся только согласиться, а до — ещё
    /// можно разложить по двум приёмам.
    func isKosherMixed(draft items: [MealItem]) -> Bool {
        KosherStatus.isMixed(items.flatMap { kosherParts(named: $0.name) }.map(\.status))
    }

    /// Есть ли в записи запрещённое видом.
    func hasForbidden(_ entry: FoodEntry) -> Bool {
        entry.composition.contains { forbiddenFoodNames.contains($0.name) }
    }

    /// Действующие ожидания: чего нельзя и до какого времени.
    ///
    /// Смотрим не весь дневник, а последние сутки: самое долгое ожидание —
    /// шесть часов, и перебирать ради него годы записей незачем.
    func kosherWaits(now: Date = Date(), custom: KosherCustom = KosherCustom()) -> [KosherWait] {
        let since = now.addingTimeInterval(-24 * 3600)
        let meals = entries
            .filter { $0.date > since && $0.date <= now }
            .flatMap { entry in
                kosherParts(of: entry).map { (status: $0.status, date: entry.date, hardCheese: $0.hardCheese) }
            }
        return KosherClock.waits(from: meals, now: now, custom: custom)
    }
}
