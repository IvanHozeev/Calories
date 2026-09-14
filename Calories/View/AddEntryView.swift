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

    @State private var showingMealTime = false
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
    @State private var showingScanner: Bool
    @State private var showingPhoto: Bool
    @State private var editingFood: FoodItem? = nil

    @State private var offResults: [FoodItem] = []
    @State private var isSearchingOFF = false
    @State private var noNetwork = false
    /// Почему внешний поиск ничего не дал. Пустой список без объяснения читается
    /// как «такого продукта нет», хотя на деле источник недоступен или не настроен.
    @State private var searchFailure: String?
    @State private var source: FoodSource = .recent
    @State private var serving: ServingTarget?
    /// Запрошен ли внешний поиск для текущего запроса. Сбрасывается при его смене:
    /// сеть дёргаем только когда о ней попросили, а не на каждую букву.
    @State private var wantsOnlineSearch = false

    /// Что показываем на экране порции.
    ///
    /// Порция — деталь этого экрана, а не отдельный лист поверх него. Пока она
    /// открывалась листом, на сохранении листы уезжали по очереди — сначала
    /// порция, потом сам экран добавления, — и запись еды выглядела медленной.
    /// Переходом внутри одного стека закрывать нечего, кроме самого экрана.
    enum ServingTarget: Identifiable, Hashable {
        case food(FoodItem, savable: Bool, quickSave: Bool)
        case dish(Dish)
        /// Уже добавленный продукт — поправить вес, если ошиблись.
        case edit(itemID: UUID)

        var id: String {
            switch self {
            case .food(let food, _, _): return "food-\(food.id.uuidString)"
            case .dish(let dish):       return "dish-\(dish.id.uuidString)"
            case .edit(let itemID):     return "edit-\(itemID.uuidString)"
            }
        }
    }

    /// Откуда берём продукты. Разделение не косметическое: пока источники шли
    /// сплошным списком, поиск по своим продуктам приходилось выискивать глазами
    /// среди сотен строк базы, а сетевой запрос уходил на каждое нажатие клавиши.
    enum FoodSource: String, CaseIterable, Identifiable {
        case recent, mine, database, online
        var id: String { rawValue }
        var title: String {
            switch self {
            case .recent:   return String(localized: "Недавнее")
            case .mine:     return String(localized: "Мои")
            case .database: return String(localized: "База")
            case .online:   return String(localized: "Онлайн")
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
         appendingTo entry: FoodEntry? = nil,
         onFinish: (() -> Void)? = nil) {
        self.store = store
        self.appendingTo = entry
        self.onFinish = onFinish
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

    /// Имя итоговой записи — из названий добавленных продуктов, с ограничением длины.
    private var mealName: String {
        joinedName(draftItems)
    }

    private func joinedName(_ items: [MealItem]) -> String {
        let joined = items.map(\.name).joined(separator: ", ")
        guard joined.count > 60 else { return joined }
        return String(joined.prefix(60)) + "…"
    }

    /// Пока ищут, сегмент не участвует: искать нужно везде сразу, а не заставлять
    /// человека перебирать вкладки, чтобы наткнуться на свой же продукт.
    private var isSearching: Bool {
        !debouncedSearch.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var filteredCustomFoods: [FoodItem] {
        guard !debouncedSearch.trimmingCharacters(in: .whitespaces).isEmpty else {
            return store.customFoods
        }
        return store.customFoods.filter { $0.name.localizedCaseInsensitiveContains(debouncedSearch) }
    }

    private var filteredBuiltInFoods: [FoodItem] {
        guard !debouncedSearch.trimmingCharacters(in: .whitespaces).isEmpty else {
            return FoodDatabase.items
        }
        return FoodDatabase.search(debouncedSearch)
    }

    private var filteredDishes: [Dish] {
        guard !debouncedSearch.trimmingCharacters(in: .whitespaces).isEmpty else {
            return store.dishes
        }
        return store.dishes.filter { $0.name.localizedCaseInsensitiveContains(debouncedSearch) }
    }

    /// Недавнее тоже фильтруется запросом: раньше оно просто исчезало при вводе,
    /// хотя чаще всего искомое лежит именно там.
    private var recentFoodItems: [FoodItem] {
        let query = debouncedSearch.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return store.recentFoods }
        return store.recentFoods.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var recentDishItems: [Dish] {
        let query = debouncedSearch.trimmingCharacters(in: .whitespaces)
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
    private var topMatches: [TopMatch] {
        let query = debouncedSearch.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }
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
        return candidates
            .sorted {
                if $0.1 != $1.1 { return $0.1 < $1.1 }
                if $0.0.isDish != $1.0.isDish { return !$0.0.isDish }
                return $0.0.name.count < $1.0.name.count
            }
            .prefix(6)
            .map(\.0)
    }

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
                            .onTapGesture { openServing(.food(food, savable: savable, quickSave: true)) }
                    case .dish(let dish):
                        dishRow(dish)
                            .contentShape(Rectangle())
                            .onTapGesture { openServing(.dish(dish)) }
                    }
                }
            }
        }
    }

    @ViewBuilder private var offSearchSection: some View {
        Section("Глобальный поиск") {
            if isSearchingOFF {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Ищем в базе данных...")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
                .padding(.vertical, 2)
            } else if noNetwork {
                Label("Нет подключения к интернету", systemImage: "wifi.slash")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if let searchFailure {
                Label(searchFailure, systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
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
                        .onTapGesture { openServing(.food(food, savable: true, quickSave: false)) }
                }
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
                // Появляется, только когда время сдвинули руками, и оранжевым:
                // это не поле для заполнения, а предупреждение, что запись уйдёт
                // не в текущий момент.
                if timeAdjusted, !isSearching, !searchFocused {
                    Section {
                        Button {
                            showingMealTime = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "clock")
                                Text(selectedDate.formatted(date: .abbreviated, time: .shortened))
                                Spacer()
                            }
                            .font(.footnote)
                            .foregroundStyle(.orange)
                        }
                        .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
                        .listRowBackground(Color.clear)
                    }
                }

                // Пока в строке поиска что-то есть, найденное идёт выше набранного:
                // смотрят сейчас на результаты, а список уже положенного только
                // отодвигал бы их вниз. Пустой поиск возвращает приём пищи наверх —
                // тогда главное на экране он.
                if searchText.isEmpty {
                    draftSection
                    browseSections
                } else {
                    browseSections
                    draftSection
                }
            }
            .onChange(of: scrollToTopTicket) { _, _ in
                withAnimation { scroll.scrollTo(Self.draftAnchor, anchor: .top) }
            }
            // Про курсор в системной строке поиска можно узнать только изнутри
            // самого searchable-контейнера, поэтому состояние забирает отсюда
            // невидимая подложка. searchFocused($:) решил бы это одной строкой,
            // но он с iOS 18, а мы держим 17.6.
            .background(SearchActivityReader(isActive: $searchFocused))
            .glassRow()
            // Своя подложка вместо системной: при раскрытии строки поиска система
            // подкладывает под список контейнер результатов со своим фоном, и он
            // на светлой теме просвечивает белым сквозь матовые строки.
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            // Строка живёт под тулбаром и вытягивается скроллом вниз — так она не
            // занимает место постоянно. Держать её всегда видимой пришлось раньше
            // из-за того, что при другом размещении она уезжала вниз экрана, где её
            // накрывала панель «Сохранить»; в навбаре этого не происходит.
            .searchable(text: $searchText,
                        isPresented: $searchPresented,
                        placement: .navigationBarDrawer(displayMode: .automatic),
                        prompt: "Поиск продукта")
            // Сетевой поиск ходит в сеть только на своей вкладке. Раньше он уходил
            // на каждое нажатие клавиши, даже когда искали в своих продуктах.
            .onChange(of: searchText) { _, _ in wantsOnlineSearch = false }
            .task(id: "\(source.rawValue)|\(wantsOnlineSearch)|\(searchText)") {
                debouncedSearch = searchText
                guard source == .online || wantsOnlineSearch else {
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
                    // Запрос отменили новым вводом — это не ошибка
                } catch {
                    searchFailure = error.localizedDescription
                }
                isSearchingOFF = false
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Приём пищи")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // С набранным приёмом пищи «Отмена» уезжает вниз, к «Сохранить»:
                // наверху её прячет раскрытая строка поиска, а решают «сохранить
                // или бросить» в одном месте.
                if draftItems.isEmpty {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Отмена") { dismiss() }
                    }
                }
                // Ни плюса, ни часов в тулбаре: «новый продукт» и «только калории»
                // живут в плюсе на «Сегодня», а время приёма — на экране продукта,
                // где его решают, уже выбрав, что съели.
                // Плавающая кнопка нижней панели перекрывает список. Пока сохранять нечего,
                // она не нужна — показываем её только при непустом черновике.
                if !draftItems.isEmpty {
                    ToolbarItem(placement: .bottomBar) {
                        Button("Отмена") { dismiss() }
                            .accessibilityIdentifier("cancelMeal")
                    }
                    ToolbarItem(placement: .bottomBar) {
                        Button {
                            saveDraft()
                        } label: {
                            Text(verbatim: "\(String(localized: "Сохранить")) · \(draftTotalCalories) \(String(localized: "ккал"))")
                                .frame(maxWidth: .infinity)
                                .fontWeight(.semibold)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("saveMeal")
                    }
                }
            }
            // Чтобы последняя строка не оставалась навсегда под кнопкой.
            .contentMargins(.bottom, draftItems.isEmpty ? 0 : 64, for: .scrollContent)
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
            }
            .sheet(isPresented: $showingScanner) {
                BarcodeScannerSheet(store: store) { item in
                    draftItems.append(item)
                }
            }
            .sheet(isPresented: $showingMealTime) {
                MealTimeSheet(date: $selectedDate)
            }
            .onChange(of: selectedDate) { _, _ in timeAdjusted = true }
            .sheet(item: $editingFood) { food in
                NewFoodSheet(store: store, editingFood: food)
                    .presentationDetents([.medium])
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
    @ViewBuilder
    private var draftSection: some View {
        if !draftItems.isEmpty {
            Section("Приём пищи") {
                ForEach(draftItems) { item in
                    FoodRow(
                        name: item.name,
                        calories: item.calories,
                        portion: item.grams.map { String(format: "%.0f \(String(localized: "г"))", $0) }
                            ?? String(localized: "порция"),
                        macros: item.macros
                    )
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            draftItems.removeAll { $0.id == item.id }
                        } label: {
                            Image(systemName: "trash")
                        }
                        // Вес без граммов не поправить: у распознанного по фото
                        // или записанного порцией менять нечего.
                        if item.grams != nil {
                            Button {
                                serving = .edit(itemID: item.id)
                            } label: {
                                Image(systemName: "pencil")
                            }
                            .tint(.blue)
                            .accessibilityLabel("Изменить")
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Итого")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(verbatim: "\(draftTotalCalories) \(String(localized: "ккал"))")
                            .font(.title3.weight(.bold))
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

    /// Всё, из чего выбирают продукт: переключатель источника и секции с ними.
    @ViewBuilder
    private var browseSections: some View {
        if !isSearching, !searchFocused {
        Section {
            Picker("Источник", selection: $source) {
                ForEach(FoodSource.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
            .listRowBackground(Color.clear)
        }
        }

        if isSearching {
            topMatchesSection
        }

        if isSearching || source == .recent, !shownRecentFoods.isEmpty || !shownRecentDishes.isEmpty {
            Section("Недавнее") {
                ForEach(shownRecentFoods) { food in
                    foodRow(food)
                        .contentShape(Rectangle())
                        .onTapGesture { openServing(.food(food, savable: false, quickSave: true)) }
                }
                ForEach(shownRecentDishes) { dish in
                    dishRow(dish)
                        .contentShape(Rectangle())
                        .onTapGesture { openServing(.dish(dish)) }
                }
            }
        }

        if isSearching || source == .mine, !shownDishes.isEmpty {
            Section("Мои блюда") {
                ForEach(shownDishes) { dish in
                    dishRow(dish)
                        .contentShape(Rectangle())
                        .onTapGesture { openServing(.dish(dish)) }
                }
            }
        }

        // Свои продукты тоже разложены по категориям: их накапливается
        // не меньше, чем в базе. «Недавнее» намеренно оставлено плоским —
        // там порядок и есть смысл: сверху последнее съеденное, и
        // группировка сломала бы именно то, ради чего туда заходят.
        if isSearching || source == .mine {
            ForEach(grouped(shownCustomFoods), id: \.0) { category, foods in
                Section {
                    ForEach(foods) { food in
                        foodRow(food)
                            .contentShape(Rectangle())
                            .onTapGesture { openServing(.food(food, savable: false, quickSave: true)) }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                store.deleteCustomFood(food)
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                editingFood = food
                            } label: {
                                Image(systemName: "pencil")
                            }
                            .tint(.blue)
                        }
                    }
                } header: {
                    Label(category.title, systemImage: category.icon)
                }
            }
        }

        if source == .online || (isSearching && wantsOnlineSearch) {
            offSearchSection
        }

        // Пока сегменты спрятаны поиском, до внешней базы иначе не добраться,
        // а ради неё всё и затевалось: только там есть микронутриенты.
        if isSearching, !wantsOnlineSearch, source != .online {
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

        if isSearching || source == .database {
            if filteredBuiltInFoods.isEmpty {
                Section("База продуктов") {
                    Text("Ничего не найдено")
                        .foregroundStyle(.secondary)
                }
            } else {
                // База разложена по категориям, а не идёт одним списком из
                // шести десятков строк. Отдельного контрола для этого не нужно:
                // заголовки секций сами работают навигацией.
                ForEach(grouped(shownBuiltInFoods), id: \.0) { category, foods in
                    Section {
                        ForEach(foods) { food in
                            foodRow(food)
                                .contentShape(Rectangle())
                                .onTapGesture { openServing(.food(food, savable: true, quickSave: true)) }
                        }
                    } header: {
                        Label(category.title, systemImage: category.icon)
                    }
                }
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
        case .food(let food, let savable, let quickSave):
            FoodQuantityView(
                food: food,
                onSave: saveAction(for: food, enabled: savable),
                onAddAndSave: quickAction(enabled: quickSave),
                isPushed: true,
                mealDate: $selectedDate
            ) { item in
                addToDraft(item)
            }
        case .dish(let dish):
            DishQuantityView(dish: dish, onAddAndSave: addAndSave, isPushed: true, mealDate: $selectedDate) { item in
                addToDraft(item)
            }
        case .edit(let itemID):
            if let item = draftItems.first(where: { $0.id == itemID }), let grams = item.grams, grams > 0 {
                FoodQuantityView(food: per100g(item, grams: grams), grams: grams,
                                 addTitle: "Готово", isPushed: true, mealDate: $selectedDate) { edited in
                    if let index = draftItems.firstIndex(where: { $0.id == itemID }) {
                        draftItems[index] = edited
                    }
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
        draftItems.append(item)
        searchText = ""
        debouncedSearch = ""
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
        if let entry = appendingTo {
            store.updateEntry(entry, name: mealName, calories: draftTotalCalories,
                              macros: draftTotalMacros, grams: grams, date: entryDate)
        } else {
            store.add(name: mealName, calories: draftTotalCalories,
                      macros: draftTotalMacros, grams: grams, date: entryDate)
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        finish()
    }

    /// Раскладывает продукты по категориям в порядке самого перечисления —
    /// он осмысленный (мясо, рыба, молочное...), в отличие от алфавитного.
    private func grouped(_ foods: [FoodItem]) -> [(FoodCategory, [FoodItem])] {
        let buckets = Dictionary(grouping: foods, by: \.foodCategory)
        return FoodCategory.allCases.compactMap { category in
            guard let items = buckets[category], !items.isEmpty else { return nil }
            return (category, items)
        }
    }

    /// Пусто ли в выбранном источнике при текущем запросе.
    private var currentSourceIsEmpty: Bool {
        if isSearching {
            return recentFoodItems.isEmpty && recentDishItems.isEmpty
                && filteredCustomFoods.isEmpty && filteredDishes.isEmpty
                && filteredBuiltInFoods.isEmpty
        }
        switch source {
        case .recent:   return recentFoodItems.isEmpty && recentDishItems.isEmpty
        case .mine:     return filteredCustomFoods.isEmpty && filteredDishes.isEmpty
        case .database: return filteredBuiltInFoods.isEmpty
        case .online:   return offResults.isEmpty
        }
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
        FoodRow(
            name: food.name,
            calories: food.caloriesPer100g,
            portion: "100 \(String(localized: "г"))",
            macros: food.macrosPer100g,
            icons: [food.foodCategory.icon],
            micros: store.notableMicronutrients(forFoodNamed: food.name, grams: 100),
            offersVitamins: store.foodsOfferedVitamins.contains(food.id),
            traits: food.traits
        )
    }

    private func dishRow(_ dish: Dish) -> some View {
        FoodRow(
            name: dish.name,
            calories: dish.caloriesPer100g,
            portion: "100 \(String(localized: "г"))",
            macros: dish.macrosPer100g,
            detail: "\(dish.ingredients.count) \(String(localized: "ингр."))",
            icons: store.foodCategories(of: dish).map(\.icon),
            micros: store.notableMicronutrients(forFoodNamed: dish.name, grams: 100),
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
