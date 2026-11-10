import SwiftUI

struct AddEntryView: View {
    var store: CalorieStore
    /// Запись, которую дополняем. Приём пищи хранится одной строкой с итогами —
    /// разобрать его обратно на продукты нельзя, поэтому он идёт первой строкой
    /// черновика, а всё добавленное досыпается к нему.
    private let appendingTo: FoodEntry?
    @Environment(\.dismiss) private var dismiss

    @State private var selectedDate: Date
    @State private var searchText = ""
    @State private var debouncedSearch = ""
    @State private var draftItems: [MealItem] = []

    /// Трогали ли время руками. Пока нет — на экране о нём ни строки: еда почти
    /// всегда записывается тогда же, когда съедена. Как только время сдвинули,
    /// про это надо сказать, иначе приём пищи молча уедет в чужой день.
    @State private var timeAdjusted = false
    /// Активна ли строка поиска — стоит ли в ней курсор. Дату убираем уже по этому,
    /// не дожидаясь первой буквы: человек начал искать продукт, и всё остальное
    /// на экране ему сейчас мешает.
    @State private var searchFocused = false
    /// Раскрыта ли строка поиска. Отдельно от `searchFocused`: то читает состояние
    /// у системы, а этим мы им управляем — возвращаем курсор после добавления.
    @State private var searchPresented = false
    /// Открыт выбор даты и времени приёма.
    @State private var showingWhen = false
    /// Продукт ушёл в приём пищи — список наверх, а курсор в поиск, если он там был.
    ///
    /// Флагом, а не действием на месте: пока экран порции закрывается, фокус
    /// принадлежит ему, и запрошенный раньше времени курсор просто теряется.
    /// Поэтому дожидаемся закрытия и делаем всё в `onDismiss`.
    @State private var resumeSearchAfterAdd = false
    /// Стоял ли курсор в поиске, когда открыли порцию. Возвращаем его только
    /// тогда: если продукт выбрали из списка, не трогая поиск, выскочившая
    /// после добавления клавиатура — чужое решение за человека.
    @State private var searchWasFocused = false
    /// Счётчик запросов «прокрутить наверх». Прокрутка живёт внутри
    /// `ScrollViewReader`, а решение о ней принимается снаружи — счётчик их
    /// связывает. Именно счётчик, а не флаг: два добавления подряд должны
    /// сработать оба, а `false → true` во второй раз уже не случится.
    @State private var scrollToTopTicket = 0
    /// Имена продуктов из разобранной фразы, уже положенные в приём.
    /// Нужно, чтобы не скроллить после каждого продукта из «молоко 300 протеин 40»:
    /// скроллим только когда последний из них добавлен.
    @State private var consumedQueryNames: Set<String> = []
    @State private var showingScanner: Bool
    @State private var showingPhoto: Bool
    @State private var editingFood: FoodItem? = nil
    @State private var editingDish: Dish? = nil
    /// «Как обычно» — предложение usualMeal, показанное при открытии экрана из подсказки «Пора есть».
    private let initialUsualMeal: UsualMeal.Suggestion?
    @State private var showingUsualMeal: Bool = false

    @State private var offResults: [FoodItem] = []
    @State private var isSearchingOFF = false
    @State private var noNetwork = false
    /// Почему внешний поиск ничего не дал. Пустой список без объяснения читается
    /// как «такого продукта нет», хотя на деле источник недоступен или не настроен.
    @State private var searchFailure: String?
    @State private var serving: ServingTarget?
    /// Запрошен ли внешний поиск для текущего запроса. Сбрасывается при его смене:
    /// сеть дёргаем только когда о ней попросили, а не на каждую букву.
    @State private var wantsOnlineSearch = false

    /// Кэш разбора запроса, чтобы не парсить строку при каждом нажатии клавиши.
    @State private var parsedQueryCache: (search: String, items: [FoodQuery.Item]) = ("", [])
    /// Результат быстрого добавления, вычисляемый в фоне.
    @State private var quickAddsResult: [QuickAdd] = []
    /// Задача пересчёта быстрых добавлений с debounce — отменяется при каждом
    //  новом символе, чтобы клавиатура не лагала.
    @State private var quickAddsTask: Task<Void, Never>? = nil
    /// Кэш топ-сопоставлений, вычисляемый с debounce — не на каждую букву,
    /// а после паузы в наборе.
    @State private var topMatches: [TopMatch] = []
    @State private var topMatchesTask: Task<Void, Never>? = nil

    /// Что показываем на экране порции.
    ///
    /// Порция — деталь этого экрана, а не отдельный лист поверх него. Пока она
    /// открывалась листом, на сохранении листы уезжали по очереди — сначала
    /// порция, потом сам экран добавления, — и запись еды выглядела медленной.
    /// Переходом внутри одного стека закрывать нечего, кроме самого экрана.
    enum ServingTarget: Identifiable, Hashable {
        case food(FoodItem, grams: Double?, savable: Bool, quickSave: Bool)
        case dish(Dish)
        /// Уже добавленный продукт — поправить вес, если ошиблись.
        case edit(itemID: UUID)

        var id: String {
            switch self {
            case .food(let food, _, _, _): return "food-\(food.id.uuidString)"
            case .dish(let dish):       return "dish-\(dish.id.uuidString)"
            case .edit(let itemID):     return "edit-\(itemID.uuidString)"
            }
        }
    }


    /// Как закрыть экран после сохранения. Передаёт тот, кто его открыл:
    /// снять лист без анимации можно только через его собственный флаг,
    /// `dismiss()` анимирует всегда.
    private let onFinish: (() -> Void)?

    init(store: CalorieStore,
         initialDate: Date = Date(),
         initialAction: QuickAction? = nil,
         initialUsualMeal: UsualMeal.Suggestion? = nil,
         appendingTo entry: FoodEntry? = nil,
         onFinish: (() -> Void)? = nil) {
        self.store = store
        self.appendingTo = entry
        self.onFinish = onFinish
        self.initialUsualMeal = initialUsualMeal
        if let entry {
            _draftItems = State(initialValue: [
                MealItem(name: entry.name, calories: entry.calories, macros: entry.macros, grams: entry.grams)
            ])
        }
        // Камера и сканер поднимаются начальным состоянием экрана, а не записью
        // после его появления: на холодном старте такая запись успевает прийти,
        // пока экран ещё выезжает, и система её молча теряет.
        _showingPhoto = State(initialValue: initialAction == .camera)
        _showingScanner = State(initialValue: initialAction == .scanner)
        _showingUsualMeal = State(initialValue: initialUsualMeal != nil)
        // Открываем на дне, который просили, но со временем «сейчас»: для сегодняшней
        // записи это привычное поведение, а для прошедшего дня — разумная отправная точка.
        let calendar = Calendar.current
        var parts = calendar.dateComponents([.year, .month, .day], from: entry?.date ?? initialDate)
        let now = calendar.dateComponents([.hour, .minute], from: Date())
        parts.hour = now.hour
        parts.minute = now.minute
        // У дополняемой записи время своё: обед не должен переехать на «сейчас»
        // только потому, что к нему добавили компот.
        _selectedDate = State(initialValue: entry?.date ?? (calendar.date(from: parts) ?? initialDate))
    }

    private var draftTotalCalories: Int {
        draftItems.reduce(0) { $0 + $1.calories }
    }

    private var draftTotalMacros: Macros {
        draftItems.reduce(Macros.zero) { $0 + $1.macros }
    }

    /// Имя итоговой записи — из названий добавленных продуктов.
    private var mealName: String {
        joinedName(draftItems)
    }

    /// Без обрезки по длине.
    ///
    /// Шестьдесят знаков резали имя в самой записи, а не на экране: в базу
    /// уезжало «…», и строка дневника показывала обрез как данность —
    /// починить его было нечем, потому что чинить нечего, так записано.
    /// Сколько имени поместится, решает строка, которая его рисует.
    ///
    /// Заодно это чинит разбор состава по имени: последний продукт
    /// обрезанного имени не совпадал ни с чем и просто терялся.
    private func joinedName(_ items: [MealItem]) -> String {
        items.map(\.name).joined(separator: ", ")
    }

    /// Пока ищут, сегмент не участвует: искать нужно везде сразу, а не заставлять
    /// человека перебирать вкладки, чтобы наткнуться на свой же продукт.
    private var isSearching: Bool {
        !debouncedSearch.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Разобранный запрос: «творог 5% 180» — это продукт, жирность и вес.
    ///
    /// Кэшируется по строке поиска: клавиатура вызывает это свойство при
    /// каждой букве, а паттерн не меняется — нет смысла парсить заново.
    private var parsedQuery: [FoodQuery.Item] {
        if parsedQueryCache.search == debouncedSearch {
            return parsedQueryCache.items
        }
        let items = FoodQuery.parse(debouncedSearch)
        parsedQueryCache = (debouncedSearch, items)
        return items
    }

    /// По чему ищем продукты. Количество из запроса убираем: продукт
    /// называется «Творог 5%», а не «Творог 5% 180». Процент остаётся — он
    /// часть названия и различает продукты.
    private var effectiveSearchTerm: String {
        let trimmed = debouncedSearch.trimmingCharacters(in: .whitespaces)
        guard let first = parsedQuery.first,
              first.hasQuantity,
              !first.name.trimmingCharacters(in: .whitespaces).isEmpty
        else { return trimmed }
        return first.name
    }

    private var filteredCustomFoods: [FoodItem] {
        guard !effectiveSearchTerm.isEmpty else {
            return store.customFoods
        }
        return store.customFoods.filter { $0.matches(effectiveSearchTerm) }
    }

    private var filteredBuiltInFoods: [FoodItem] {
        guard !effectiveSearchTerm.isEmpty else {
            return FoodDatabase.items
        }
        return FoodDatabase.search(effectiveSearchTerm)
    }

    private var filteredDishes: [Dish] {
        guard !effectiveSearchTerm.isEmpty else {
            return store.dishes
        }
        return store.dishes.filter { $0.name.localizedCaseInsensitiveContains(effectiveSearchTerm) }
    }

    /// Недавнее тоже фильтруется запросом: раньше оно просто исчезало при вводе,
    /// хотя чаще всего искомое лежит именно там.
    private var recentFoodItems: [FoodItem] {
        let query = effectiveSearchTerm
        guard !query.isEmpty else { return store.recentFoods }
        return store.recentFoods.filter { $0.matches(query) }
    }

    private var recentDishItems: [Dish] {
        let query = effectiveSearchTerm
        guard !query.isEmpty else { return store.recentDishes }
        return store.recentDishes.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    // MARK: - Лучшие совпадения

    private enum TopMatch: Identifiable {
        case food(FoodItem, savable: Bool)
        case dish(Dish)

        var id: String {
            switch self {
            case .food(let food, _): return "food-\(food.id.uuidString)"
            case .dish(let dish):    return "dish-\(dish.id.uuidString)"
            }
        }
        var name: String {
            switch self {
            case .food(let food, _): return food.name
            case .dish(let dish):    return dish.name
            }
        }
        var isDish: Bool { if case .dish = self { return true } else { return false } }
    }

    /// Насколько название совпадает с запросом: 0 — целиком, 1 — начинается
    /// с него, 2 — с него начинается одно из слов. Остальное — не совпадение.
    private static func matchRank(_ name: String, _ query: String) -> Int? {
        let name = name.lowercased(), query = query.lowercased()
        if name == query { return 0 }
        if name.hasPrefix(query) { return 1 }
        if name.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains(where: { $0.hasPrefix(query) }) { return 2 }
        return nil
    }

    /// Совпадения по названию — поверх секций по источникам.
    ///
    /// Раньше на «Хумус» первым шло «Недавнее» с «Хумус туна тирас», потом
    /// «Мои блюда» с тем же, а сам хумус из базы — только после прокрутки:
    /// секции шли по источникам, а не по тому, насколько похоже название.
    /// Сверху теперь то, что названо ровно так или начинается с запроса;
    /// продукты раньше блюд, короткие названия раньше длинных.
    ///
    /// Вычисляется с debounce (см. .onChange(of: debouncedSearch) ниже),
    /// чтобы не пересчитывать на каждую букву.

    private func notOnTop<T>(_ items: [T], _ name: (T) -> String) -> [T] {
        guard isSearching else { return items }
        let top = topMatchNames
        return items.filter { !top.contains(name($0).lowercased()) }
    }
    private var shownRecentFoods: [FoodItem] { notOnTop(recentFoodItems) { $0.name } }
    private var shownRecentDishes: [Dish] { notOnTop(recentDishItems) { $0.name } }
    private var shownDishes: [Dish] { notOnTop(filteredDishes) { $0.name } }
    private var shownCustomFoods: [FoodItem] { notOnTop(filteredCustomFoods) { $0.name } }
    private var shownBuiltInFoods: [FoodItem] { notOnTop(filteredBuiltInFoods) { $0.name } }

    /// Имена, уже показанные сверху, — ниже в секциях источников их не повторяем.
    private var topMatchNames: Set<String> {
        Set(topMatches.map { $0.name.lowercased() })
    }

    // MARK: - Быстрое добавление

    /// Продукт и порция, найденные из фразы целиком. Один тап — и позиция в
    /// приёме, без экрана порции: количество человек уже назвал.
    private struct QuickAdd: Identifiable {
        let food: FoodItem
        let grams: Double
        /// По какому названию его искали — для идентификатора строки, когда
        /// в одной фразе несколько продуктов.
        let queryName: String
        /// Жирность из запроса — для лога выборов (ранкер на признаках).
        let percent: Double?

        var id: String { "\(food.id.uuidString)-\(queryName)" }
    }

    private var quickAdds: [QuickAdd] {
        quickAddsResult
    }

    /// Пересчитывает быстрые добавления в фоне, чтобы не блокировать клавиатуру.
    ///
    /// Вызывается после срабатывания дебаунса строки поиска. Каталоговый поиск
    /// и ранжирование уходят в `Task.detached`; свои и недавние продукты — их
    /// обычно мало — ранжируются на главном потоке уже после возвращения.
    private func recomputeQuickAdds() {
        let items = parsedQuery
        let itemsWithQuantity = items.filter {
            $0.hasQuantity && !$0.name.trimmingCharacters(in: .whitespaces).isEmpty
        }
        guard !itemsWithQuantity.isEmpty else {
            quickAddsResult = []
            return
        }

        Task.detached(priority: .userInitiated) {
            // Фон: ищем лучший каталоговый продукт для каждой позиции.
            let catalogMatches: [FoodQuery.Item: CatalogFood] = Dictionary(
                uniqueKeysWithValues: itemsWithQuantity.compactMap { item in
                    guard let catalog = Self.bestCatalogMatch(for: item) else { return nil }
                    return (item, catalog)
                }
            )

            await MainActor.run {
                // Сохраняем ссылку на自己, чтобы не удерживать view в замыкании.
                let customFoods = store.customFoods
                let recentFoods = store.recentFoods

                var adds: [QuickAdd] = []
                var seen = Set<String>()

                for item in itemsWithQuantity {
                    // Собираем всех подходящих кандидатов из всех источников,
                    // а не только одного «лучшего». Тогда при «молоко 300»
                    // покажем все три процента с граммовкой 300, а пользователь
                    // выберет нужное самим тапом.
                    var candidates: [(food: FoodItem, source: Int, rank: Int, length: Int, updatedAt: Date?)] = []

                    // Свои продукты — primero, как просит пользователь.
                    for food in customFoods {
                        if let percent = item.percent {
                            let names = [food.name, food.producer ?? ""]
                            if !FoodQuery.nameContainsPercent(names, percent: percent) {
                                continue
                            }
                        }
                        guard let rank = FoodQuery.rank(query: item.name,
                                                        name: food.name,
                                                        producer: food.producer)
                        else { continue }
                        candidates.append((food, 0, rank, food.name.count, food.updatedAt))
                    }
                    // Недавние — следующие.
                    for food in recentFoods {
                        if let percent = item.percent {
                            let names = [food.name, food.producer ?? ""]
                            if !FoodQuery.nameContainsPercent(names, percent: percent) {
                                continue
                            }
                        }
                        guard let rank = FoodQuery.rank(query: item.name,
                                                        name: food.name,
                                                        producer: food.producer)
                        else { continue }
                        candidates.append((food, 1, rank, food.name.count, food.updatedAt))
                    }
                    // Каталог — в последнюю очередь.
                    if let catalog = catalogMatches[item],
                       let food = FoodDatabase.item(for: catalog) {
                        if let percent = item.percent {
                            let names = [catalog.localizedName, catalog.en]
                                + (catalog.ru.map { [$0] } ?? [])
                                + (catalog.aliases ?? [])
                            if !FoodQuery.nameContainsPercent(names, percent: percent) {
                                // пропускаем
                            } else {
                                let rank = Self.catalogRank(item.name, catalog) ?? 0
                                candidates.append((food, 2, rank, catalog.localizedName.count, nil))
                            }
                        } else {
                            let rank = Self.catalogRank(item.name, catalog) ?? 0
                            candidates.append((food, 2, rank, catalog.localizedName.count, nil))
                        }
                    }

                    // Сортируем: свой primero, потом по точности совпадения,
                    // потом по популярности (выбирали чаще — выше), потом по свежести
                    // (недавнее выше — иначе старое блюдо с накопленнойpopularity
                    // вытесняет то, что ели вчера), потом по длине.
                    candidates.sort {
                        if $0.source != $1.source { return $0.source < $1.source }
                        if $0.rank != $1.rank { return $0.rank < $1.rank }
                        let popA = SearchEventLog.shared.popularityScore(for: $0.food.name)
                        let popB = SearchEventLog.shared.popularityScore(for: $1.food.name)
                        if popA != popB { return popA > popB }
                        switch ($0.updatedAt, $1.updatedAt) {
                        case let (dA?, dB?):
                            if dA != dB { return dA > dB }
                        case (nil, _?):
                            return false
                        case (_?, nil):
                            return true
                        default: break
                        }
                        return $0.length < $1.length
                    }

                    // Берём до трёх уникальных вариантов для выбора.
                    var added = 0
                    for cand in candidates where added < 3 {
                        guard let grams = item.grams(defaultGrams: cand.food.defaultGrams),
                              seen.insert(cand.food.name.lowercased()).inserted
                        else { continue }
                        adds.append(QuickAdd(food: cand.food, grams: grams, queryName: item.name, percent: item.percent))
                        added += 1
                    }
                }

                // Логируем показ быстрого добавления для ранкера на признаках.
                SearchEventLog.shared.log(SearchEvent(
                    id: UUID(),
                    query: effectiveSearchTerm,
                    shown: adds.map { ShownItem(name: $0.food.name, percent: $0.percent, source: "catalog", rank: nil) },
                    selected: nil,
                    selectedGrams: nil,
                    timestamp: Date()
                ))

                withAnimation(.default) { quickAddsResult = adds }
            }
        }
    }

    /// Лучший каталоговый продукт под запрос — можно считать в фоне:
    /// всё, что здесь используется, — `Sendable`.
    private nonisolated static func bestCatalogMatch(for item: FoodQuery.Item) -> CatalogFood? {
        var best: (food: CatalogFood, rank: Int)?
        for catalog in FoodCatalog.search(item.name, limit: 10) {
            // Процент — жёсткое ограничение: «молоко 3%» не должно показать
            // «молоко 1.5%».
            if let percent = item.percent {
                let names = [catalog.en, catalog.localizedName]
                    + (catalog.ru.map { [$0] } ?? [])
                    + (catalog.aliases ?? [])
                if !FoodQuery.nameContainsPercent(names, percent: percent) {
                    continue
                }
            }
            guard let rank = catalogRank(item.name, catalog) else { continue }
            if best == nil || rank < best!.rank {
                best = (catalog, rank)
            }
        }
        return best?.food
    }

    /// Лучший продукт под разобранную фразу.
    ///
    /// Сначала база: её поиск уже знает русские и английские названия и
    /// синонимы, поэтому «творог 5» находится и при английском интерфейсе.
    private nonisolated static func catalogRank(_ query: String, _ food: CatalogFood) -> Int? {
        var names = [food.en, food.localizedName]
        if let ru = food.ru { names.append(ru) }
        names.append(contentsOf: food.aliases ?? [])
        return FoodQuery.rank(query: query, names: names)
    }

    @ViewBuilder
    private var usualMealSection: some View {
        if let usual = initialUsualMeal {
            Section("Как обычно") {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(partsName(usual))
                            .font(.app(.body, weight: .semibold))
                        Text("\(usual.times) раз, в последний раз \(usual.lastEaten.formatted(date: .omitted, time: .shortened))")
                            .font(.app(.caption))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(usual.calories) ккал")
                        .font(.app(.subheadline, weight: .semibold))
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    addUsualMeal(usual)
                }
            }
        }
    }

    private func partsName(_ usual: UsualMeal.Suggestion) -> String {
        usual.parts.map(\.name).joined(separator: ", ")
    }

    /// Сохранённый приём с запрошенными граммами по частям.
    private struct UsualMatch: Identifiable {
        let usual: UsualMeal.Suggestion
        /// Запрошенные граммы по имени продукта из запроса. nil — оставить медианные из истории.
        let requestedGrams: [String: Double]?

        var id: String { usual.id }
    }

    /// Сохранённые приёмы, которые подходят под текущий запрос.
    ///
    /// «молоко 300 протеин 40» найдёт приём «Молоко 3%, Протеин шоколадный»,
    /// который человек уже собирал 17 раз, и предложит его целиком — одним тапом.
    /// Запрошенные граммы накладываются на части приёма по совпадению имён.
    private var usualMealMatches: [UsualMatch] {
        guard isSearching else { return [] }
        let terms = parsedQuery.map {
            $0.name.trimmingCharacters(in: .whitespaces).lowercased()
        }.filter { !$0.isEmpty }
        guard !terms.isEmpty else { return [] }

        // Запрошенные граммы по имени продукта из запроса.
        let requestedGrams: [String: Double] = Dictionary(
            parsedQuery.compactMap { item in
                guard let g = item.grams(defaultGrams: 100), g > 0 else { return nil }
                return (item.name.trimmingCharacters(in: .whitespaces).lowercased(), g)
            },
            uniquingKeysWith: { $1 }
        )

        let meals = store.usualMeals(period: nil, days: 180)
        return meals.filter { meal in
            meal.parts.contains { part in
                let partName = part.name.lowercased()
                return terms.contains { term in partName.contains(term) }
            }
        }
        .map { meal -> UsualMatch in
            UsualMatch(usual: meal,
                       requestedGrams: requestedGrams.isEmpty ? nil : requestedGrams)
        }
        .sorted {
            // Недавнее выше: если ели вчера/сегодня — важнее накопленного счёта.
            // Старое блюдо со 100 повторов не должно вытеснять то, что ели второй день подряд.
            if $0.usual.lastEaten != $1.usual.lastEaten {
                return $0.usual.lastEaten > $1.usual.lastEaten
            }
            return $0.usual.times > $1.usual.times
        }
        .prefix(3)
        .map { $0 }
    }

    /// Запрошенные граммы для части приёма: ищем по вхождению имени части в термин запроса
    /// или термина в имя части — иначе «молоко» из запроса не найдёт «Молоко 3%» в приёме.
    private func requestedGrams(for part: EntryComponent, in requested: [String: Double]?) -> Double? {
        guard let requested else { return nil }
        let partName = part.name.trimmingCharacters(in: .whitespaces).lowercased()
        // Сначала точное совпадение ключа.
        if let g = requested[partName] { return g }
        // Потом по вхождению в любую сторону.
        for (term, grams) in requested where partName.contains(term) || term.contains(partName) {
            return grams
        }
        return nil
    }

    /// Недавние блюда, подходящие под запрос.
    ///
    /// «Паста с туной в томатном соусе 500» — свежее блюдо, заведённое недавно.
    /// Оно ещё не набрало трёх повторов для «Как обычно», но уже есть в дневнике
    /// — показываем его в быстром добавлении.
    private var recentDishMatches: [Dish] {
        guard isSearching else { return [] }
        let terms = parsedQuery.map {
            $0.name.trimmingCharacters(in: .whitespaces).lowercased()
        }.filter { !$0.isEmpty }
        guard !terms.isEmpty else { return [] }
        return store.recentDishes.filter { dish in
            let name = dish.name.lowercased()
            return terms.contains { term in name.contains(term) }
        }
        .sorted { ($0.updatedAt ?? dishCreated($0)) > ($1.updatedAt ?? dishCreated($1)) }
        .prefix(3)
        .map { $0 }
    }

    /// Дата создания блюда — резерв, если updatedAt нет.
    private func dishCreated(_ dish: Dish) -> Date { dish.createdAt }

    /// Недавние приёмы из дневника, подходящие под запрос.
    ///
    /// Составные приёмы (несколько продуктов) — через `recentMeals`, они уже
    /// отфильтрованы и отсортированы по дате.
    private var recentMealMatches: [FoodEntry] {
        guard isSearching else { return [] }
        let terms = parsedQuery.map {
            $0.name.trimmingCharacters(in: .whitespaces).lowercased()
        }.filter { !$0.isEmpty }
        guard !terms.isEmpty else { return [] }
        return store.recentMeals(limit: 10, days: 30).filter { entry in
            let name = entry.name.lowercased()
            return terms.contains { term in name.contains(term) }
        }
        .prefix(3)
        .map { $0 }
    }

    /// Недавние записи дневника с одним продуктом, подходящие под запрос.
    ///
    /// «Паста с туной» может быть записана как один продукт (без компонентов)
    /// — тогда она не попадает ни в `recentMeals`, ни в `recentDishes`. Ищем
    /// её среди недавних записей дневника.
    private var recentEntryMatches: [FoodEntry] {
        guard isSearching else { return [] }
        let terms = parsedQuery.map {
            $0.name.trimmingCharacters(in: .whitespaces).lowercased()
        }.filter { !$0.isEmpty }
        guard !terms.isEmpty else { return [] }
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? .distantPast
        var seen = Set<String>()
        return store.entries
            .filter { $0.date >= cutoff && $0.components.isEmpty }
            .filter { entry in
                guard !seen.contains(entry.name.lowercased()) else { return false }
                seen.insert(entry.name.lowercased())
                let name = entry.name.lowercased()
                return terms.contains { term in name.contains(term) }
            }
            .prefix(3)
            .map { $0 }
    }

    /// Части приёма с наложенными запрошенными граммами.
    private func scaledParts(for match: UsualMatch) -> [MealItem] {
        match.usual.parts.map { part in
            let g = requestedGrams(for: part, in: match.requestedGrams) ?? part.grams
            let scale = (g ?? part.grams ?? 100) / (part.grams ?? 100)
            return MealItem(
                name: part.name,
                calories: Int((Double(part.calories) * scale).rounded()),
                macros: Macros(protein: part.protein * scale,
                               fat: part.fat * scale,
                               carbs: part.carbs * scale),
                grams: g ?? part.grams
            )
        }
    }

    @ViewBuilder
    private var quickAddSection: some View {
        let adds = quickAdds
        let usuals = usualMealMatches
        let dishes = recentDishMatches
        let meals = recentMealMatches
        let entries = recentEntryMatches
        let hasResults = !usuals.isEmpty || !dishes.isEmpty || !meals.isEmpty || !entries.isEmpty || !adds.isEmpty

        if isSearching && hasResults {
            Section("Быстрое добавление") {
                quickAddSectionBody(
                    usuals: usuals,
                    dishes: dishes,
                    meals: meals,
                    entries: entries,
                    adds: adds
                )
            }
        }
    }

    /// Внутри секции «Быстрое добавление» — вынесено отдельно, чтобы
    /// компилятор не ломался на сложном условии с множеством ForEach.
    @ViewBuilder
    private func quickAddSectionBody(
        usuals: [UsualMatch],
        dishes: [Dish],
        meals: [FoodEntry],
        entries: [FoodEntry],
        adds: [QuickAdd]
    ) -> some View {
        if !usuals.isEmpty {
            ForEach(Array(usuals.enumerated()), id: \.element.id) { index, match in
                quickUsualRow(match)
                    .contentShape(Rectangle())
                    .onTapGesture { addQuickUsualMeal(match) }
                    .accessibilityIdentifier("quickUsualRow\(index)")
            }
            .animation(.default, value: usuals.map { $0.id })
        }

        quickDishSection(dishes: dishes)
        quickMealSection(meals: meals)
        quickEntrySection(entries: entries)

        if !adds.isEmpty {
            ForEach(Array(adds.enumerated()), id: \.element.id) { index, add in
                quickAddRow(add)
                    .contentShape(Rectangle())
                    .onTapGesture { quickAdd(add) }
                    .accessibilityIdentifier("quickAddRow\(index)")
            }
            .animation(.default, value: adds.map { $0.id })
        }
    }

    /// Блюда из недавнего в быстром добавлении.
    private func quickDishSection(dishes: [Dish]) -> some View {
        ForEach(Array(dishes.enumerated()), id: \.element.id) { index, dish in
            quickDishRow(dish)
                .contentShape(Rectangle())
                .onTapGesture { addQuickDish(dish) }
                .accessibilityIdentifier("quickDishRow\(index)")
        }
        .animation(.default, value: dishes.map { $0.id })
    }

    /// Приёмы из недавнего в быстром добавлении.
    private func quickMealSection(meals: [FoodEntry]) -> some View {
        ForEach(Array(meals.enumerated()), id: \.element.id) { index, entry in
            quickMealRow(entry)
                .contentShape(Rectangle())
                .onTapGesture { addQuickMeal(entry) }
                .accessibilityIdentifier("quickMealRow\(index)")
        }
        .animation(.default, value: meals.map { $0.id })
    }

    /// Записи дневника с одним продуктом в быстром добавлении.
    private func quickEntrySection(entries: [FoodEntry]) -> some View {
        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
            quickMealRow(entry)
                .contentShape(Rectangle())
                .onTapGesture { addQuickMeal(entry) }
                .accessibilityIdentifier("quickEntryRow\(index)")
        }
        .animation(.default, value: entries.map { $0.id })
    }

    /// Строка недавнего блюда в быстром добавлении.
    private func quickDishRow(_ dish: Dish) -> some View {
        let grams = dish.servingGrams
        return FoodRow(
            name: dish.name,
            calories: dish.totalCalories,
            portion: String(format: "%.0f \(String(localized: "г"))", grams),
            macros: dish.totalMacros,
            icons: store.foodCategories(of: dish).map(\.icon),
            micros: store.notableMicronutrients(forFoodNamed: dish.name, grams: grams)
        )
    }

    /// Строка недавней записи дневника в быстром добавлении.
    private func quickMealRow(_ entry: FoodEntry) -> some View {
        let portions = entry.components.compactMap { part in
            part.grams.map { String(format: "%.0f \(String(localized: "г"))", $0) }
        }
        return FoodRow(
            name: entry.name,
            calories: entry.calories,
            caloriesPer100g: nil,
            portion: portions.joined(separator: " · "),
            macros: Macros(protein: entry.protein, fat: entry.fat, carbs: entry.carbs),
            detail: entry.components.isEmpty ? nil : String(format: String(localized: "%lld позиции"), entry.components.count),
            parts: entry.components.map { .init(name: $0.name, macros: Macros(protein: $0.protein, fat: $0.fat, carbs: $0.carbs)) }
        )
    }

    /// Добавить недавнее блюдо в черновик — один тап.
    private func addQuickDish(_ dish: Dish) {
        let grams = dish.servingGrams
        let item = MealItem(
            name: dish.name,
            calories: dish.totalCalories,
            macros: dish.totalMacros,
            grams: grams
        )
        withAnimation(.snappy) { draftItems.append(item) }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        scrollToTopTicket += 1
        Task { @MainActor in
            searchText = ""
            debouncedSearch = ""
            consumedQueryNames.removeAll()
        }
    }

    /// Добавить недавнюю запись дневника в черновик — один тап.
    private func addQuickMeal(_ entry: FoodEntry) {
        withAnimation(.snappy) {
            draftItems.append(contentsOf: entry.components.map {
                MealItem(name: $0.name, calories: $0.calories,
                         macros: Macros(protein: $0.protein, fat: $0.fat, carbs: $0.carbs),
                         grams: $0.grams)
            })
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        scrollToTopTicket += 1
        Task { @MainActor in
            searchText = ""
            debouncedSearch = ""
            consumedQueryNames.removeAll()
        }
    }

    /// Строка сохранённого приёма в быстром добавлении.
    ///
    /// Каждая часть приёма — «Молоко», «Протеин шоколадный» — красится в цвет
    /// своего доминирующего макроса, а не вся строка одним цветом.
    private func quickUsualRow(_ match: UsualMatch) -> some View {
        let items = scaledParts(for: match)
        let totalCalories = items.reduce(0) { $0 + $1.calories }

        return Button {
            addQuickUsualMeal(match)
        } label: {
            FoodRow(
                name: match.usual.parts.map(\.name).joined(separator: ", "),
                calories: totalCalories,
                portion: String(format: String(localized: "%lld позиции"), match.usual.parts.count),
                macros: items.reduce(Macros.zero) { $0 + $1.macros },
                detail: String(format: String(localized: "%lld раз"), match.usual.times),
                parts: items.map { .init(name: $0.name, macros: $0.macros) }
            )
        }
        .buttonStyle(.plain)
    }

    /// Положить весь сохранённый приём в черновик — один тап, без экрана порции.
    /// Запрошенные граммы применяются к частям приёма по совпадению имён.
    private func addQuickUsualMeal(_ match: UsualMatch) {
        withAnimation(.snappy) {
            draftItems.append(contentsOf: scaledParts(for: match))
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        // Весь приём добавлен разом — фраза закончена, чистим поиск и скроллим к черновику.
        scrollToTopTicket += 1
        Task { @MainActor in
            searchText = ""
            debouncedSearch = ""
            consumedQueryNames.removeAll()
        }
    }

    private func quickAddRow(_ add: QuickAdd) -> some View {
        let factor = add.grams / 100
        let calories = Int((Double(add.food.caloriesPer100g) * factor).rounded())
        return FoodRow(
            name: add.food.name,
            calories: calories,
            caloriesPer100g: add.food.caloriesPer100g,
            portion: String(format: "%.0f \(String(localized: "г"))", add.grams),
            macros: add.food.macrosPer100g.portion(grams: add.grams),
            icons: [add.food.foodCategory.icon],
            micros: store.notableMicronutrients(forFoodNamed: add.food.name,
                                                grams: add.grams),
            offersVitamins: store.foodsOfferedVitamins.contains(add.food.id),
            traits: add.food.traits
        )
    }

    /// Тап по быстрой строке. В черновик, а не в дневник: приём ещё собирают,
    /// и сохранение остаётся тем же одним движением, что и раньше.
    private func quickAdd(_ add: QuickAdd) {
        let item = MealItem(
            name: add.food.name,
            calories: Int((Double(add.food.caloriesPer100g) * add.grams / 100).rounded()),
            macros: add.food.macrosPer100g.portion(grams: add.grams),
            grams: add.grams
        )
        withAnimation(.snappy) { draftItems.append(item) }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        // Логируем выбор для ранкера на признаках.
        SearchEventLog.shared.log(SearchEvent(
            id: UUID(),
            query: effectiveSearchTerm,
            shown: [],
            selected: ShownItem(name: add.food.name, percent: add.percent, source: "catalog", rank: nil),
            selectedGrams: add.grams,
            timestamp: Date()
        ))

        consumedQueryNames.insert(add.queryName)
        // Продукты из разобранной фразы, которые ещё предстоит добавить.
        let pending = parsedQuery.filter {
            $0.hasQuantity && !$0.name.trimmingCharacters(in: .whitespaces).isEmpty
                && !consumedQueryNames.contains($0.name)
        }
        if pending.isEmpty {
            // Все продукты фразы добавлены — скроллим кверху, показываем приём,
            // чистим поиск.
            scrollToTopTicket += 1
            Task { @MainActor in
                searchText = ""
                debouncedSearch = ""
                consumedQueryNames.removeAll()
            }
        }
        // Иначе не скроллим: человек ещё добавляет остальные продукты фразы,
        // и черновик — над результатами, он их видит без листования.
    }

    /// Добавить всё из «Как обычно» в черновик.
    private func addUsualMeal(_ usual: UsualMeal.Suggestion) {
        for part in usual.parts {
            draftItems.append(MealItem(
                name: part.name,
                calories: part.calories,
                macros: part.macros,
                grams: part.grams
            ))
        }
        showingUsualMeal = false
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        scrollToTopTicket += 1
    }

    @ViewBuilder
    private var topMatchesSection: some View {
        let matches = topMatches
        if !matches.isEmpty {
            Section("Совпадения") {
                ForEach(matches) { match in
                    switch match {
                    case .food(let food, let savable):
                        foodRow(food)
                            .contentShape(Rectangle())
                            .onTapGesture { openServing(.food(food, grams: nil, savable: savable, quickSave: true)) }
                    case .dish(let dish):
                        dishRow(dish)
                            .contentShape(Rectangle())
                            .onTapGesture { openServing(.dish(dish)) }
                    }
                }
                .animation(.default, value: topMatches.map { $0.id })
            }
            .animation(.default, value: topMatches.map { $0.id })
        }
    }

    @ViewBuilder private var offSearchSection: some View {
        Section("Глобальный поиск") {
            if isSearchingOFF {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Ищем в базе данных...")
                        .foregroundStyle(.secondary)
                        .font(.app(.subheadline))
                }
                .padding(.vertical, 2)
            } else if noNetwork {
                Label("Нет подключения к интернету", systemImage: "wifi.slash")
                    .font(.app(.subheadline))
                    .foregroundStyle(.secondary)
            } else if let searchFailure {
                Label(searchFailure, systemImage: "exclamationmark.triangle")
                    .font(.app(.subheadline))
                    .foregroundStyle(.secondary)
            } else if offResults.isEmpty {
                Text("Ничего не найдено")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(offResults) { food in
                    // Тап ловим по всей строке: у .plain-кнопки в списке
                    // «живыми» остаются только сами буквы, и первый тап
                    // по пустому месту строки пропадает впустую.
                    foodRow(food)
                        .contentShape(Rectangle())
                        .onTapGesture { openServing(.food(food, grams: nil, savable: true, quickSave: false)) }
                }
                .animation(.default, value: offResults.map { $0.id })
            }
        }
    }

    /// Якорь для прокрутки: секция набранного приёма пищи. После добавления она
    /// заведомо непустая и стоит первой — секция со сдвинутым временем в это
    /// время спрятана раскрытым поиском.
    private static let draftAnchor = "draft"

    var body: some View {
        NavigationStack {
            // Список внутри не сдвинут на уровень вложенности намеренно: обёртка
            // добавлена ради одной прокрутки, и переливать из-за неё сто семьдесят
            // строк в диф — хуже, чем этот отступ.
            ScrollViewReader { scroll in
            List {
                // Время приёма — на самом экране, а не за переходом.
                //
                // Оно жило в отдельном листе, потому что «меняют это редко»:
                // еда обычно записывается тогда же, когда съедена. Но редко —
                // не значит никогда, а за переходом его не видно вовсе, и
                // человек замечал ошибку уже в дневнике. Строка занимает одну
                // высоту и молчит, пока время сегодняшнее; сдвинутое время
                // подсвечивается оранжевым — это уже предупреждение.

                // Набранные продукты всегда сверху — и при пустом поиске, и при
                // активном. Тогда после «молоко 300» не нужно листать вниз за
                // следующим продуктом: он остаётся на экране над результатами.
                draftSection
                browseSections
            }
            .onChange(of: scrollToTopTicket) { _, _ in
                withAnimation { scroll.scrollTo(Self.draftAnchor, anchor: .top) }
            }
            .glassRow()
            // Своя подложка вместо системной: при раскрытии строки поиска система
            // подкладывает под список контейнер результатов со своим фоном, и он
            // на светлой теме просвечивает белым сквозь матовые строки.
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            // Про курсор в системной строке поиска можно узнать только изнутри
            // самого searchable-контейнера, поэтому состояние забирает отсюда
            // невидимая подложка.
            .background(SearchActivityReader(isActive: $searchFocused))
            // Размещение выбирает система: на iOS 26 она сама кладёт строку
            // вниз, к большому пальцу, — туда, где к ней и возвращаются после
            // каждого добавленного продукта.
            .searchable(text: $searchText,
                        isPresented: $searchPresented,
                        prompt: "Поиск еды")
            // Сетевой поиск ходит в сеть только на своей вкладке. Раньше он уходил
            // на каждое нажатие клавиши, даже когда искали в своих продуктах.
            .onChange(of: searchText) { _, newValue in
                wantsOnlineSearch = false
                // Новый запрос — новый контекст: сбрасываем отслеживание
                // продуктов из разобранной фразы.
                if newValue.trimmingCharacters(in: .whitespaces).isEmpty {
                    consumedQueryNames.removeAll()
                }
            }
            // Быстрые добавления считаем в фоне с задержкой после окончания
            // ввода — не на каждый символ, иначе клавиатура лагает. Каждый новый
            // символ отменяет предыдущую задачу.
            .onChange(of: debouncedSearch) { _, _ in
                quickAddsTask?.cancel()
                quickAddsTask = Task {
                    try? await Task.sleep(for: .milliseconds(150))
                    guard !Task.isCancelled else { return }
                    recomputeQuickAdds()
                }
                // Топ-сопоставления считаем с таким же дебаунсом — не на каждую
                // букву, а после паузы в наборе.
                topMatchesTask?.cancel()
                topMatchesTask = Task {
                    try? await Task.sleep(for: .milliseconds(150))
                    guard !Task.isCancelled else { return }
                    let query = effectiveSearchTerm
                    guard !query.isEmpty else {
                        await MainActor.run { topMatches = [] }
                        return
                    }
                    var seen = Set<String>()
                    var candidates: [(TopMatch, Int)] = []
                    func consider(_ match: TopMatch) {
                        guard let rank = Self.matchRank(match.name, query), rank <= 1 else { return }
                        guard seen.insert(match.name.lowercased()).inserted else { return }
                        candidates.append((match, rank))
                    }
                    filteredBuiltInFoods.forEach { consider(.food($0, savable: true)) }
                    filteredCustomFoods.forEach { consider(.food($0, savable: false)) }
                    recentFoodItems.forEach { consider(.food($0, savable: false)) }
                    filteredDishes.forEach { consider(.dish($0)) }
                    recentDishItems.forEach { consider(.dish($0)) }
                    let result = candidates
                        .sorted {
                            if $0.1 != $1.1 { return $0.1 < $1.1 }
                            if $0.0.isDish != $1.0.isDish { return !$0.0.isDish }
                            return $0.0.name.count < $1.0.name.count
                        }
                        .prefix(6)
                        .map(\.0)
                    await MainActor.run {
                        withAnimation(.default) { topMatches = result }
                        // Логируем показ топ-сопоставлений для ранкера на признаках.
                        SearchEventLog.shared.log(SearchEvent(
                            id: UUID(),
                            query: query,
                            shown: result.map { match in
                                ShownItem(name: match.name, percent: nil,
                                          source: match.isDish ? "dish" : "food", rank: nil)
                            },
                            selected: nil,
                            selectedGrams: nil,
                            timestamp: Date()
                        ))
                    }
                }
            }
            .task(id: "\(wantsOnlineSearch)|\(searchText)") {
                await searchOnlineIfNeeded()
            }
            .scrollDismissesKeyboard(.interactively)
            // Строка поиска внизу, у большого пальца: собирая приём, к ней
            // возвращаются после каждого добавленного продукта.
            .toolbar { whenToolbar }
            .topBarTitle(String(localized: "Приём пищи"), trailingButtons: 1)
            // При разворачивании строки поиска iOS скрывает заголовок шапки и
            // не возвращает его при закрытии поиска. Привязка к состоянию
            // поиска заставляет заголовок пересоздаваться при каждом
            // открытии/закрытии строки — тогда он появляется обратно.
            .id(searchPresented)
            .toolbar { draftToolbar }
            .safeAreaBar(edge: .bottom) { draftBar }
            .navigationDestination(item: $serving) { target in
                servingScreen(target)
            }
            // Возврат из порции — это и есть момент «ищем следующий продукт».
            .onChange(of: serving) { old, new in
                if old != nil, new == nil { resumeSearchIfNeeded() }
            }
            .sheet(isPresented: $showingPhoto) {
                PhotoMealSheet { items in
                    // Распознанное становится обычным черновиком: дальше его
                    // правят теми же движениями, что и введённое руками.
                    draftItems.append(contentsOf: items)
                }
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $showingScanner) {
                BarcodeScannerSheet(store: store) { item in
                    draftItems.append(item)
                }
                .presentationDetents([.medium])
            }
            .onChange(of: selectedDate) { _, _ in timeAdjusted = true }
            .sheet(item: $editingFood) { food in
                NewFoodSheet(store: store, editingFood: food)
                    .presentationDetents([.medium])
            }
            .sheet(item: $editingDish) { dish in
                NewDishSheet(store: store, editingDish: dish)
            }
            } // ScrollViewReader
        }
    }

    /// После добавления продукта возвращаем экран в то состояние, из которого
    /// ищут следующий: курсор в строке поиска, список наверху.
    ///
    /// Иначе после каждого продукта приходится тянуться к строке пальцем, а
    /// список остаётся там, где его пролистали, — то есть на чужой категории.
    private func resumeSearchIfNeeded() {
        guard resumeSearchAfterAdd else { return }
        resumeSearchAfterAdd = false
        if searchWasFocused {
            // Строка поиска за время порции могла остаться «раскрытой» и без
            // курсора — тогда повторное true ничего не меняет. Сбрасываем и
            // раскрываем заново, чтобы клавиатура действительно поднялась.
            searchPresented = false
            Task { @MainActor in searchPresented = true }
        }
        scrollToTopTicket += 1
    }

    /// Набранный приём пищи.

    /// Источник еды — меню, а не полоса сегментов над списком: четыре подписи в
    /// сегментах обрезались, а строку экрана занимали всегда, хотя источник
    /// переключают редко.
    /// Когда ел — в тулбаре, на месте прежнего выбора источника.
    ///
    /// Выбор источника убран: поиск и так идёт сразу по недавнему, своим
    /// продуктам, блюдам и базе, а внешняя база открывается кнопкой в
    /// результатах. Кнопка, которая ничего не меняет, занимала верх экрана, а
    /// время приёма — то, что правят по-настоящему, — лежало строкой в списке.
    @ToolbarContentBuilder
    private var whenToolbar: some ToolbarContent {
        // Строка поиска и «когда» — одной нижней полосой. Место поиска среди
        // пунктов тулбара приходится назвать явно: иначе система показывает
        // либо поиск, либо пункты, и один из них пропадает.
        DefaultToolbarItem(kind: .search, placement: .bottomBar)
        // Отдельной кнопкой, а не полем внутри той же капсулы: дата, вшитая
        // в строку поиска, читалась как часть поиска.
        ToolbarSpacer(.fixed, placement: .bottomBar)
        ToolbarItem(placement: .bottomBar) {
            Button {
                showingWhen = true
            } label: {
                Label("Когда", systemImage: "clock")
            }
            .accessibilityIdentifier("mealTimePicker")
            .popover(isPresented: $showingWhen) {
                DatePicker("Когда", selection: $selectedDate, in: ...Date(),
                           displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .frame(width: 320)
                    .padding(.vertical, 8)
                    // Поповером, а не листом: лист поверх листа — это второй
                    // этаж модальности, и выход из него человек ищет заново.
                    .presentationCompactAdaptation(.popover)
            }
        }
    }

    /// Отмена и сохранение.
    ///
    /// С набранным приёмом «Отмена» уезжает вниз, к «Сохранить»: наверху её
    /// прячет раскрытая строка поиска, а решают «сохранить или бросить» в одном
    /// месте. Пока сохранять нечего, плавающей кнопки нет — она перекрывает
    /// список.
    ///
    /// Ни плюса, ни часов здесь нет: «новый продукт» и «только калории» живут в
    /// плюсе на «Сегодня», а время приёма — строкой на этом экране.
    @ToolbarContentBuilder
    private var draftToolbar: some ToolbarContent {
        // Кнопки «Отмена» в тулбаре нет: лист закрывается смахиванием вниз.
        EmptyView()
    }

    /// Отмена и сохранение — полосой над строкой поиска.
    ///
    /// Не пунктами нижнего тулбара: там уже стоит системная строка поиска, и
    /// система показывает что-то одно — при первом же добавленном продукте
    /// поиск подменялся кнопками, а искать дальше было нечем. Полоса в
    /// безопасной области — штатное для этого место: она встаёт над строкой
    /// поиска, со своим стеклом, и обе остаются на экране.
    ///
    /// Отмена здесь — отмена набранного, а не выход с экрана: человек собирает
    /// приём и передумал про то, что набрал. Выход остаётся наверху слева и
    /// возвращается туда сам, как только приём опустел.
    @ViewBuilder
    private var draftBar: some View {
        if !draftItems.isEmpty {
            HStack(spacing: 12) {
                Button("Отмена") {
                    draftItems.removeAll()
                }
                .buttonStyle(.glass)
                .accessibilityIdentifier("cancelMeal")

                Button {
                    saveDraft()
                } label: {
                    Text(verbatim: "\(String(localized: "Сохранить")) · \(draftTotalCalories) \(String(localized: "ккал"))")
                        .frame(maxWidth: .infinity)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.glassProminent)
                .accessibilityIdentifier("saveMeal")
            }
            // Стекло и крупный размер — те же, что у кнопок в тулбаре: полоса
            // переехала из тулбара, и выглядеть она должна так же, а не
            // плоскими кнопками вполовину ниже.
            .controlSize(.large)
            // По краям строки поиска под ней, а не по краям экрана: иначе
            // кнопки вылезают за неё и строка смотрится вставленной криво.
            .padding(.horizontal, 28)
        }
    }

    /// Поиск в сети — только на своей вкладке и только после паузы в наборе.
    ///
    /// В сеть ходим не на каждое нажатие клавиши: раньше запрос уходил даже
    /// когда искали в своих продуктах. Отмену задачи новым вводом ошибкой не
    /// считаем — это обычный ход событий, а не сбой, и показывать по ней
    /// «нет сети» нельзя.
    private func searchOnlineIfNeeded() async {
        debouncedSearch = searchText
        guard wantsOnlineSearch else {
            isSearchingOFF = false
            return
        }
        guard !searchText.isEmpty else {
            debouncedSearch = ""
            offResults = []
            noNetwork = false
            isSearchingOFF = false
            return
        }
        try? await Task.sleep(for: .milliseconds(200))
        guard !Task.isCancelled else { return }
        isSearchingOFF = true
        offResults = []
        do {
            let results = try await FoodSearch.search(query: searchText)
            guard !Task.isCancelled else { isSearchingOFF = false; return }
            offResults = results
            noNetwork = false
            searchFailure = nil
        } catch let urlError as URLError where
            urlError.code == .notConnectedToInternet ||
            urlError.code == .networkConnectionLost ||
            urlError.code == .timedOut ||
            urlError.code == .cannotFindHost ||
            urlError.code == .cannotConnectToHost {
            noNetwork = true
        } catch is CancellationError {
            // Запрос отменили новым вводом
        } catch {
            searchFailure = error.localizedDescription
        }
        isSearchingOFF = false
    }

    /// Рецепт, на который похоже собранное. Считается от имён черновика:
    /// пока в нём меньше двух позиций одного рецепта, здесь пусто.
    private var recipeHint: RecipeHint.Match? {
        store.recipeHint(for: draftItems.map(\.name))
    }

    @ViewBuilder
    private var draftSection: some View {
        if !draftItems.isEmpty {
            Section {
                // Догадка — над составом, а не под ним: она про то, что
                // человек собирает прямо сейчас, и увидеть её он должен,
                // пока собирает, а не дособрав.
                if let hint = recipeHint {
                    RecipeHintRow(match: hint) {
                        for part in RecipeHint.missing(from: hint.dish, draft: draftItems.map(\.name)) {
                            draftItems.append(MealItem(name: part.foodName,
                                                       calories: part.calories,
                                                       macros: part.macros,
                                                       grams: part.grams))
                        }
                    }
                }
                ForEach(draftItems) { item in
                    FoodRow(
                        name: item.name,
                        calories: item.calories,
                        portion: item.grams.map { String(format: "%.0f \(String(localized: "г"))", $0) }
                            ?? String(localized: "порция"),
                        macros: item.macros
                    )
                    // Правка — по нажатию на строку, как везде в приложении.
                    // За свайпом её не искали: человек видит неверный вес и
                    // тыкает в него, а не пробует жесты.
                    //
                    // Вес без граммов не поправить: у распознанного по фото
                    // или записанного порцией менять нечего — такая строка
                    // просто не отзывается.
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard item.grams != nil else { return }
                        openServing(.edit(itemID: item.id))
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            draftItems.removeAll { $0.id == item.id }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("Удалить")
                    }
                }

                // Мясное с молочным — до того, как приём записан.
                //
                // Здесь, в черновике, а не строкой в дневнике: после записи
                // остаётся только согласиться, а сейчас набранное ещё можно
                // разложить по двум приёмам. Не запрет и не блокировка
                // сохранения: приложение говорит, что видит, а решает человек.
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Итого")
                            .font(.app(.subheadline, weight: .semibold))
                        Spacer()
                        Text(verbatim: "\(draftTotalCalories) \(String(localized: "ккал"))")
                            .font(.app(.title3, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(.green)
                            .contentTransition(.numericText())
                    }
                    MacroTags(macros: draftItems.reduce(Macros.zero) { $0 + $1.macros })
                }
                .padding(.vertical, 4)
                .animation(.easeInOut(duration: 0.2), value: draftTotalCalories)
            }
            .id(Self.draftAnchor)
        }
    }





    /// Недавние приёмы пищи целиком — из нескольких продуктов.
    private var recentMeals: [FoodEntry] {
        store.recentMeals()
    }

    /// Всё, из чего выбирают продукт: переключатель источника и секции с ними.
    @ViewBuilder
    private var browseSections: some View {
        if isSearching {
            quickAddSection
            topMatchesSection
        }

        // «Как обычно» — обычное блюдо для этого приёма, предложенное при
        // открытии экрана из строки «Пора есть».
        usualMealSection

        // Подсказки еды: «как обычно», «обычно вместе» и подбор к остатку.
        // При поиске их не показываем: человек ищет конкретный продукт, а не
        // выбирает из привычек — и лишний пересчёт истории только лагает.
        if !isSearching {
            MealSuggestionsView(store: store,
                                draftItems: $draftItems,
                                onAdd: { items in
                                    withAnimation(.snappy) {
                                        draftItems.append(contentsOf: items)
                                    }
                                    scrollToTopTicket += 1
                                },
                                onOpenPair: { pair in
                                    let grams = pair.grams ?? 100
                                    let food = store.foodNamed(pair.name)
                                        ?? per100g(MealItem(name: pair.name, calories: pair.calories,
                                                            macros: pair.macros, grams: grams), grams: grams)
                                    openServing(.food(food, grams: grams, savable: false, quickSave: true))
                                },
                                onScrollToTop: {
                                    scrollToTopTicket += 1
                                })
        }

        if !shownRecentFoods.isEmpty || !shownRecentDishes.isEmpty {
            Section("Недавнее") {
                ForEach(shownRecentFoods) { food in
                    foodRow(food)
                        .contentShape(Rectangle())
                        .onTapGesture { openServing(.food(food, grams: nil, savable: false, quickSave: true)) }
                }
                ForEach(shownRecentDishes) { dish in
                    dishRow(dish)
                        .contentShape(Rectangle())
                        .onTapGesture { openServing(.dish(dish)) }
                }
            }
        }

        if isSearching, !shownDishes.isEmpty {
            Section("Рецепты") {
                ForEach(shownDishes) { dish in
                    dishRow(dish)
                        .contentShape(Rectangle())
                        .onTapGesture { openServing(.dish(dish)) }
                        // Как у своих продуктов. Отдельной вкладки «Еда», где
                        // блюда правили и удаляли, больше нет — всё здесь.
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                store.deleteDish(dish)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .accessibilityLabel("Удалить")
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                editingDish = dish
                            } label: {
                                Image(systemName: "pencil")
                            }
                            .tint(.blue)
                            .accessibilityLabel("Изменить")
                        }
                }
            }
        }

        // Свои продукты тоже разложены по категориям: их накапливается
        // не меньше, чем в базе. «Недавнее» намеренно оставлено плоским —
        // там порядок и есть смысл: сверху последнее съеденное, и
        // группировка сломала бы именно то, ради чего туда заходят.
        if isSearching {
            ForEach(FoodCategory.grouped(shownCustomFoods), id: \.0) { category, foods in
                Section {
                    ForEach(foods) { food in
                        foodRow(food)
                            .contentShape(Rectangle())
                            .onTapGesture { openServing(.food(food, grams: nil, savable: false, quickSave: true)) }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                store.deleteCustomFood(food)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .accessibilityLabel("Удалить")
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                editingFood = food
                            } label: {
                                Image(systemName: "pencil")
                            }
                            .tint(.blue)
                            .accessibilityLabel("Изменить")
                        }
                    }
                } header: {
                    Label(category.title, systemImage: category.icon)
                }
            }
            .animation(.default, value: shownCustomFoods.map { $0.id })
        }

        if isSearching, wantsOnlineSearch {
            offSearchSection
        }

        // Пока сегменты спрятаны поиском, до внешней базы иначе не добраться,
        // а ради неё всё и затевалось: только там есть микронутриенты.
        if isSearching, !wantsOnlineSearch {
            Section {
                Button {
                    wantsOnlineSearch = true
                } label: {
                    Label("Искать в базе USDA", systemImage: "globe")
                }
            } footer: {
                Text("Внешняя база больше и знает витамины с минералами. Запрос уходит только по этой кнопке.")
            }
        }

        if isSearching {
            if filteredBuiltInFoods.isEmpty {
                Section("База продуктов") {
                    Text("Ничего не найдено")
                        .foregroundStyle(.secondary)
                }
                .animation(.default, value: shownBuiltInFoods.isEmpty)
            } else {
                // База разложена по категориям, а не идёт одним списком из
                // шести десятков строк. Отдельного контрола для этого не нужно:
                // заголовки секций сами работают навигацией.
                ForEach(FoodCategory.grouped(shownBuiltInFoods), id: \.0) { category, foods in
                    Section {
                        ForEach(foods) { food in
                            foodRow(food)
                                .contentShape(Rectangle())
                                .onTapGesture { openServing(.food(food, grams: nil, savable: true, quickSave: true)) }
                        }
                    } header: {
                        Label(category.title, systemImage: category.icon)
                    }
                }
                .animation(.default, value: shownBuiltInFoods.map { $0.id })
            }
        }
    }

    /// Пикер теперь хранит и время, поэтому подменять его текущим больше не нужно.
    private var entryDate: Date { selectedDate }

    /// Вынесено из модификатора: со switch внутри ViewBuilder компилятор
    /// не укладывается в разумное время на проверке типов.
    @ViewBuilder
    private func servingScreen(_ target: ServingTarget) -> some View {
        switch target {
        case .food(let food, let grams, let savable, let quickSave):
            FoodQuantityView(
                food: food,
                grams: grams,
                onSave: saveAction(for: food, enabled: savable),
                onAddAndSave: quickAction(enabled: quickSave),
                isPushed: true,
            ) { item in
                addToDraft(item)
            }
        case .dish(let dish):
            DishQuantityView(dish: dish, onAddAndSave: addAndSave,
                             remainingGrams: store.batchState(of: dish)?.remainingGrams,
                             isPushed: true) { item in
                addToDraft(item)
            }
        case .edit(let itemID):
            if let item = draftItems.first(where: { $0.id == itemID }), let grams = item.grams, grams > 0 {
                FoodQuantityView(food: per100g(item, grams: grams), grams: grams,
                                 addTitle: "Готово", isPushed: true) { edited in
                    // Правим поля на месте, а не подменяем элемент целиком: у
                    // нового `MealItem` новый идентификатор, экран порции
                    // открыт по старому — и после «Готово» он оставался
                    // показанным, но уже ничего не находил. Получался чёрный
                    // экран с одной стрелкой назад.
                    if let index = draftItems.firstIndex(where: { $0.id == itemID }) {
                        draftItems[index].name = edited.name
                        draftItems[index].calories = edited.calories
                        draftItems[index].macros = edited.macros
                        draftItems[index].grams = edited.grams
                    }
                    // И закрываем сами: экран показан из этого состояния,
                    // убрать его надо тем же, чем открыли.
                    serving = nil
                }
            }
        }
    }


    /// Добавленный продукт обратно в «на 100 г», чтобы править вес тем же экраном
    /// порции. Сам продукт в приёме пищи не хранится — там уже посчитанное.
    private func per100g(_ item: MealItem, grams: Double) -> FoodItem {
        let factor = 100 / grams
        return FoodItem(name: item.name,
                        caloriesPer100g: Int((Double(item.calories) * factor).rounded()),
                        protein: item.macros.protein * factor,
                        fat: item.macros.fat * factor,
                        carbs: item.macros.carbs * factor)
    }

    /// Типы у опциональных замыканий выписаны явно: в тернарнике прямо в списке
    /// аргументов компилятор на них захлёбывается.
    private func saveAction(for food: FoodItem, enabled: Bool) -> (() -> Void)? {
        guard enabled, !isSaved(food) else { return nil }
        return { saveToMyFoods(food) }
    }

    private func quickAction(enabled: Bool) -> ((MealItem) -> Void)? {
        guard enabled else { return nil }
        return { item in addAndSave(item) }
    }

    private func openServing(_ target: ServingTarget) {
        searchWasFocused = searchFocused
        serving = target
    }

    /// Запрос живёт ровно до попадания продукта в приём пищи: найденное уже
    /// добавлено, и следующий продукт ищут с чистого листа, а не стирают чужие
    /// буквы. Сбрасываем и debounced-копию, чтобы список вернулся сразу.
    private func addToDraft(_ item: MealItem) {
        // Сначала закрываем экран порции: он показан из этого же состояния,
        // и убрать его надо тем же, чем открыли.
        serving = nil
        draftItems.append(item)
        // Очистку запроса откладываем на следующий тик. Со строкой поиска,
        // живущей в нижнем тулбаре, сброс текста прямо в момент закрытия
        // экрана порции схлопывал весь лист приёма: SwiftUI пересобирал
        // иерархию поиска под уезжающим экраном.
        Task { @MainActor in
            searchText = ""
            debouncedSearch = ""
        }
        resumeSearchAfterAdd = true
    }

    /// Экран порции закрываем первым: иначе лист уезжает из-под открытого поверх
    /// него экрана, и анимация схлопывается в рывок.
    private func addAndSave(_ item: MealItem) {
        draftItems.append(item)
        saveDraft()
    }

    /// Кладём черновик в дневник: новой записью или поверх дополняемой.
    private func saveDraft() {
        guard !draftItems.isEmpty else { return }
        let grams = draftItems.count == 1 ? draftItems[0].grams : nil
        // Состав кладём всегда: по склеенному имени приём потом не разобрать,
        // и всё, что считается по продуктам — «Недавнее», категории рациона,
        // клетчатка, — теряет из виду половину съеденного.
        let components = draftItems.map {
            EntryComponent(name: $0.name, calories: $0.calories, macros: $0.macros, grams: $0.grams)
        }
        if let entry = appendingTo {
            store.updateEntry(entry, name: mealName, calories: draftTotalCalories,
                              macros: draftTotalMacros, grams: grams, date: entryDate,
                              components: components)
        } else {
            store.add(name: mealName, calories: draftTotalCalories,
                      macros: draftTotalMacros, grams: grams, date: entryDate,
                      components: components)
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        finish()
    }

    /// Раскладывает продукты по категориям в порядке самого перечисления —
    /// он осмысленный (мясо, рыба, молочное...), в отличие от алфавитного.
    /// Пусто ли на экране при текущем запросе.
    private var currentSourceIsEmpty: Bool {
        if isSearching {
            return recentFoodItems.isEmpty && recentDishItems.isEmpty
                && filteredCustomFoods.isEmpty && filteredDishes.isEmpty
                && filteredBuiltInFoods.isEmpty
        }
        // Без поиска на экране недавнее и подсказки: пусто, когда пусто и то
        // и другое.
        return recentFoodItems.isEmpty && recentDishItems.isEmpty
    }

    private func isSaved(_ food: FoodItem) -> Bool {
        store.isInMyFoods(food)
    }

    private func saveToMyFoods(_ food: FoodItem) {
        store.saveToMyFoods(food)
    }

    /// Закрывает экран после сохранения — одним движением.
    ///
    /// Экран добавления открыт поверх «Сегодня», а порция и «только калории» —
    /// внутри него. Раньше на сохранении они уезжали по очереди: сначала порция,
    /// потом сам экран, две анимации подряд, и запись еды выглядела медленной.
    /// Потом снимали всё без анимации — быстро, но «Сегодня» появлялось рывком.
    ///
    /// Теперь уезжает только сам экран, одной системной анимацией, а порцию
    /// и лист калорий не трогаем: они уходят вместе с ним, как есть. Закрой их
    /// отдельно — и снова получатся две анимации, одна за другой.
    private func finish() {
        if let onFinish {
            onFinish()
        } else {
            dismiss()
        }
    }

    private func foodRow(_ food: FoodItem) -> some View {
        let grams = food.defaultGrams > 0 ? food.defaultGrams : 100
        let kcal = Int((Double(food.caloriesPer100g) * grams / 100).rounded())
        return FoodRow(
            name: food.name,
            calories: kcal,
            caloriesPer100g: food.caloriesPer100g,
            portion: "\(Int(grams)) \(String(localized: "г"))",
            macros: food.macrosPer100g.portion(grams: grams),
            icons: [food.foodCategory.icon],
            micros: store.notableMicronutrients(forFoodNamed: food.name, grams: grams),
            offersVitamins: store.foodsOfferedVitamins.contains(food.id),
            traits: food.traits
        )
    }

    private func dishRow(_ dish: Dish) -> some View {
        FoodRow(
            name: dish.name,
            calories: dish.servingCalories,
            caloriesPer100g: dish.caloriesPer100g,
            portion: String(format: "%.0f \(String(localized: "г"))", dish.servingGrams),
            macros: dish.servingMacros,
            detail: "\(dish.ingredients.count) \(String(localized: "ингр."))",
            icons: store.foodCategories(of: dish).map(\.icon),
            micros: store.notableMicronutrients(forFoodNamed: dish.name, grams: dish.servingGrams),
            traits: dish.traits
        )
    }
}

/// Пробрасывает наружу `\.isSearching`: снаружи `.searchable` это окружение
/// уже недоступно, а внутри списка — доступно.
private struct SearchActivityReader: View {
    @Environment(\.isSearching) private var isSearching
    @Binding var isActive: Bool

    var body: some View {
        Color.clear
            .onChange(of: isSearching) { _, newValue in
                // Без анимации: список перестраивается вместе с раскрытием строки
                // поиска, и на анимированном исчезновении секций сквозь них
                // просвечивала светлая подложка.
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { isActive = newValue }
            }
    }
}
