import Foundation

/// Перестройка кэшей: словари, дневные сводки, «Недавнее», витамины своим.
extension CalorieStore {

    /// Пересобирает кэши, если с момента последнего пересчёта сменились сутки.
    /// Дёшево, когда день тот же, поэтому вызывать можно на каждую активацию приложения.
    func rebuildCaches() {
        let calendar = Calendar.current

        rebuildLookups(calendar)
        rebuildToday(calendar)
        rebuildDays(calendar)

        hasWeighedToday = weightEntries.contains { calendar.isDateInToday($0.date) }
        adherence = computePlanAdherence()

        rebuildStreaks(calendar)
        rebuildExpenditure(calendar)

        // После словарей: «Недавнее» берёт из них категорию продукта.
        rebuildRecent()
        rebuildVitaminOffers()

        cachesBuiltForDay = calendar.startOfDay(for: Date())
        publishToWidget(calendar)
        BodyBridge.publish(profile: profile, measurement: latestMeasurement)
    }

#if DEBUG
    /// Сколько стоит каждый шаг перестройки — в миллисекундах.
    ///
    /// Перестройка идёт на каждую запись еды и на каждое потягивание списка
    /// вниз, то есть внутри жеста, и лишние сто миллисекунд здесь человек
    /// чувствует как подлагивание. Вопрос «что именно из этого дорого»
    /// возникает не первый раз, и отвечать на него догадками дороже, чем
    /// держать эти двадцать строк.
    func rebuildTimings() -> [(step: String, ms: Double)] {
        let calendar = Calendar.current
        func measure(_ name: String, _ block: () -> Void) -> (String, Double) {
            let start = Date()
            block()
            return (name, Date().timeIntervalSince(start) * 1000)
        }
        return [
            measure("словари") { rebuildLookups(calendar) },
            measure("сегодня") { rebuildToday(calendar) },
            measure("дни") { rebuildDays(calendar) },
            measure("серии") { rebuildStreaks(calendar) },
            measure("расход") { rebuildExpenditure(calendar) },
            measure("недавнее") { rebuildRecent() },
            measure("витамины своим") { rebuildVitaminOffers() },
            measure("виджет") { publishToWidget(calendar) },
        ]
    }
#endif

    /// Словари для O(1)-обращений: день → записи, имя → категория и состав,
    /// день → зафиксированная цель.
    func rebuildLookups(_ calendar: Calendar) {
        // Строим O(1)-словари один раз
        entriesByDay = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.date) }
        // Свой продукт идёт последним и перекрывает одноимённый встроенный:
        // так же, как в прежнем поиске, где сначала смотрели свои.
        // Пост может идти через полночь: в наборе все сутки, которых он касается.
        fastDates = Set(fastDays.flatMap(\.coveredDays))
        categoryByFoodName = Dictionary(
            (FoodDatabase.items + customFoods).map { ($0.name, $0.foodCategory) },
            uniquingKeysWith: { _, own in own }
        )
        let allFoods = FoodDatabase.items + customFoods
        kosherByFoodName = Dictionary(
            allFoods.map { ($0.name, $0.kosherStatus) },
            uniquingKeysWith: { _, own in own }
        )
        hardCheeseFoodNames = Set(allFoods.filter(\.isHardCheese).map(\.name))
        forbiddenFoodNames = Set(allFoods.filter(\.kosherForbidden).map(\.name))
        // Каталог отдаёт состав уже разобранным и не меняется, поэтому его
        // словарь строится один раз; поверх кладём свои продукты — они как раз
        // меняются, но их немного.
        var profiles = FoodCatalog.nutrientProfilesByName
        for food in customFoods where !food.micronutrients.isEmpty {
            // Оценка по классу идёт в день с половинным весом: вещества у
            // похожей еды расходятся примерно в полтора раза, и объявлять такой
            // день изученным наравне с измеренным нельзя.
            profiles[food.name] = NutrientProfile(
                per100g: food.micronutrients,
                coverage: food.micronutrientsAreEstimated ? NutrientProfile.estimateCoverage : 1)
        }
        // Блюда после продуктов: их состав считается по ингредиентам, а значит
        // словарь продуктов к этому моменту должен быть уже собран.
        for dish in dishes {
            guard let profile = DishNutrients.profile(of: dish.ingredients,
                                                      composition: { profiles[$0]?.per100g })
            else { continue }
            profiles[dish.name] = profile
        }
        nutrientProfilesByName = profiles
        // uniquingKeysWith, а не uniqueKeysWithValues: последняя форма падает на повторном
        // ключе. Две записи могут схлопнуться в один локальный день после смены часового пояса,
        // и это был бы краш на каждом запуске без возможности выбраться.
        goalsByDay = Dictionary(
            goalRecords.map { (calendar.startOfDay(for: $0.date), $0.goal) },
            uniquingKeysWith: { _, newer in newer }
        )
    }

    /// Сегодняшний день: записи, съеденное, макросы и приёмы пищи по времени.
    func rebuildToday(_ calendar: Calendar) {
        // Агрегаты за сегодня — один проход по entries
        todayEntries = entries.filter { calendar.isDateInToday($0.date) }
        consumedToday = todayEntries.reduce(0) { $0 + $1.calories }
        macrosToday = todayEntries.reduce(Macros.zero) { $0 + $1.macros }

        groupedTodayEntries = MealPeriod.group(todayEntries)
    }

    /// Дневные сводки: все дни, последняя неделя и история.
    func rebuildDays(_ calendar: Calendar) {
        // Сводки по дням — один проход по сгруппированному словарю
        // entries уже отсортированы по дате desc, порядок внутри группы сохраняется
        let allDays = entriesByDay.map { day, dayEntries in
            DaySummary(date: day, entries: dayEntries, goal: goal(for: day))
        }.sorted { $0.date > $1.date }
        days = allDays
        let pastDays = allDays.filter { !calendar.isDateInToday($0.date) }

        // Последние 7 дней включая пустые — O(7) через словарь
        lastSevenDays = (0..<7).reversed().map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: Date()) ?? Date()
            let day = calendar.startOfDay(for: date)
            return DaySummary(date: day, entries: entriesByDay[day] ?? [], goal: goal(for: day))
        }

        // История: последние 6 дней (не сегодня) всегда + старые дни с записями
        // Set из 6 дат для O(1) исключения из pastDays
        let last6 = lastSevenDays.filter { !calendar.isDateInToday($0.date) }
        let last6Dates = Set(last6.map { $0.date })
        let olderDays = pastDays.filter { !last6Dates.contains($0.date) }
        historyDays = (last6 + olderDays).sorted { $0.date > $1.date }
    }

    /// «Недавнее» — съеденное и заведённое вперемешку, по давности.
    func rebuildRecent() {
        let dishNames = Set(dishes.map(\.name))
        // Продукт по имени: свой перекрывает встроенный — его правили руками,
        // значит он ближе к тому, что человек действительно ест.
        var foodByName: [String: FoodItem] = [:]
        for food in FoodDatabase.items { foodByName[food.name] = food }
        for food in customFoods { foodByName[food.name] = food }

        var seen = Set<String>()
        // Сперва только даты и имена: объекты дорого создавать, а нужны они
        // лишь для верхушки списка.
        var candidates: [(date: Date, food: FoodItem)] = []

        // Записи уже отсортированы по убыванию даты, поэтому первое попавшееся
        // имя — это последний раз, когда продукт ели.
        for entry in entries where !dishNames.contains(entry.name) {
            for component in entry.composition where !seen.contains(component.name) {
                guard let food = recentFood(named: component.name, from: component, in: foodByName)
                else { continue }
                seen.insert(component.name)
                candidates.append((entry.date, food))
            }
            // Записи, сделанные до того, как состав начали хранить: имя у них
            // склеено из названий через запятую, и это всё, что от состава
            // осталось. Разбираем — иначе продукт, который человек ест каждый
            // день внутри приёма, в «Недавнем» не появится никогда.
            guard entry.components.isEmpty else { continue }
            for part in Self.joinedNameParts(entry.name) where !seen.contains(part) {
                guard let food = foodByName[part] else { continue }
                seen.insert(part)
                candidates.append((entry.date, food))
            }
        }

        // Недавнее — это и съеденное, и заведённое: продукт заводят ровно
        // тогда, когда собираются им пользоваться.
        for food in customFoods {
            guard let updatedAt = food.updatedAt, !seen.contains(food.name) else { continue }
            seen.insert(food.name)
            candidates.append((updatedAt, food))
        }

        recentFoods = candidates
            .sorted { $0.date > $1.date }
            .prefix(Self.recentLimit)
            .map(\.food)

        var seenDishes = Set<String>()
        var dishCandidates: [(date: Date, dish: Dish)] = []
        for entry in entries {
            guard !seenDishes.contains(entry.name) else { continue }
            guard let dish = dishes.first(where: { $0.name == entry.name }) else { continue }
            seenDishes.insert(entry.name)
            dishCandidates.append((entry.date, dish))
        }
        for dish in dishes where !seenDishes.contains(dish.name) {
            seenDishes.insert(dish.name)
            dishCandidates.append((dish.updatedAt ?? dish.createdAt, dish))
        }
        recentDishes = dishCandidates
            .sorted { $0.date > $1.date }
            .prefix(Self.recentLimit)
            .map(\.dish)
    }

    /// Чем показать продукт в «Недавнем».
    ///
    /// Сначала настоящий продукт: у него есть категория, состав и порция по
    /// умолчанию. Если такого нет (еду записали разово, руками), собираем
    /// продукт из самой записи — для этого нужен вес, иначе пересчитать на
    /// сто грамм не из чего.
    func recentFood(named name: String, from component: EntryComponent,
                    in foodByName: [String: FoodItem]) -> FoodItem? {
        if let food = foodByName[name] { return food }
        guard let grams = component.grams, grams > 0 else { return nil }
        let factor = 100 / grams
        return FoodItem(
            name: name,
            caloriesPer100g: Int((Double(component.calories) * factor).rounded()),
            protein: component.protein * factor,
            fat: component.fat * factor,
            carbs: component.carbs * factor,
            defaultGrams: grams,
            // Записи дневника категорию не хранят: без этой строки весь
            // список показывал «Другое».
            category: categoryByFoodName[name] ?? .other
        )
    }

    /// Кому из своих продуктов каталог может одолжить витамины.
    ///
    /// Точное совпадение по названию не считаем: там состав и так подтягивается
    /// сам, и предлагать нечего. Смысл только в непохожих названиях — «Творог
    /// мой» против «Творог 5%», — где связь может найти только поиск.
    ///
    /// Считается заново только когда изменились сами продукты, а не при каждой
    /// перестройке кэшей. Перебор каталога стоит несколько миллисекунд на
    /// продукт, а перестройка идёт на каждую запись еды и на каждое обновление
    /// «Сегодня»: на семидесяти своих продуктах это давало полторы десятых
    /// секунды на жест — ровно то подлагивание, которое видно при потягивании
    /// списка вниз. Сами продукты меняются от силы раз в день.
    func rebuildVitaminOffers() {
        // В отпечаток идёт всё, от чего зависит ответ: имя и категория решают,
        // кого искать, калории и макросы — подойдёт ли донор по цифрам, состав
        // и связь с каталогом — нужно ли вообще предлагать. Блюда тоже: их имена
        // попадают в словарь составов, по которому мы отсеиваем тех, у кого
        // состав и так есть.
        var hasher = Hasher()
        for food in customFoods {
            hasher.combine(food.id)