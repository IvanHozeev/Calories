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

    @State private var showingNewFood = false
    @State private var showingQuickCalories = false
    @State private var showingMealTime = false
    /// Трогали ли время руками. Пока нет — на экране о нём ни строки: еда почти
    /// всегда записывается тогда же, когда съедена. Как только время сдвинули,
    /// про это надо сказать, иначе приём пищи молча уедет в чужой день.
    @State private var timeAdjusted = false
    /// Активна ли строка поиска — стоит ли в ней курсор. Дату убираем уже по этому,
    /// не дожидаясь первой буквы: человек начал искать продукт, и всё остальное
    /// на экране ему сейчас мешает.
    @State private var searchFocused = false
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

    /// Что показываем на экране порции. Раньше он вставлялся в стек навигации
    /// внутри листа — получался лист с кнопкой «назад», два разных способа
    /// закрыть один экран. Теперь он всегда открывается поверх, одинаково
    /// откуда бы ни зашли.
    enum ServingTarget: Identifiable {
        case food(FoodItem, savable: Bool, quickSave: Bool)
        case dish(Dish)

        var id: String {
            switch self {
            case .food(let food, _, _): return "food-\(food.id.uuidString)"
            case .dish(let dish):       return "dish-\(dish.id.uuidString)"
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


    init(store: CalorieStore,
         initialDate: Date = Date(),
         initialAction: QuickAction? = nil,
         appendingTo entry: FoodEntry? = nil) {
        self.store = store
        self.appendingTo = entry
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
                        .onTapGesture { serving = .food(food, savable: true, quickSave: false) }
                }
            }
        }
    }

    var body: some View {
        NavigationStack {
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
                        }
                        .onDelete { offsets in
                            draftItems.remove(atOffsets: offsets)
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
                }

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

                if isSearching || source == .recent, !recentFoodItems.isEmpty || !recentDishItems.isEmpty {
                    Section("Недавнее") {
                        ForEach(recentFoodItems) { food in
                            foodRow(food)
                                .contentShape(Rectangle())
                                .onTapGesture { serving = .food(food, savable: false, quickSave: true) }
                        }
                        ForEach(recentDishItems) { dish in
                            dishRow(dish)
                                .contentShape(Rectangle())
                                .onTapGesture { serving = .dish(dish) }
                        }
                    }
                }

                if isSearching || source == .mine, !filteredDishes.isEmpty {
                    Section("Мои блюда") {
                        ForEach(filteredDishes) { dish in
                            dishRow(dish)
                                .contentShape(Rectangle())
                                .onTapGesture { serving = .dish(dish) }
                        }
                    }
                }

                // Свои продукты тоже разложены по категориям: их накапливается
                // не меньше, чем в базе. «Недавнее» намеренно оставлено плоским —
                // там порядок и есть смысл: сверху последнее съеденное, и
                // группировка сломала бы именно то, ради чего туда заходят.
                if isSearching || source == .mine {
                    ForEach(grouped(filteredCustomFoods), id: \.0) { category, foods in
                        Section {
                            ForEach(foods) { food in
                                foodRow(food)
                                    .contentShape(Rectangle())
                                    .onTapGesture { serving = .food(food, savable: false, quickSave: true) }
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
                        ForEach(grouped(filteredBuiltInFoods), id: \.0) { category, foods in
                            Section {
                                ForEach(foods) { food in
                                    foodRow(food)
                                        .contentShape(Rectangle())
                                        .onTapGesture { serving = .food(food, savable: true, quickSave: true) }
                                }
                            } header: {
                                Label(category.title, systemImage: category.icon)
                            }
                        }
                    }
                }
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
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        // Время приёма — само по себе, а не в меню: это не способ
                        // что-то добавить, а свойство записи.
                        Button {
                            showingMealTime = true
                        } label: {
                            Image(systemName: "clock")
                        }
                        .accessibilityLabel("Время приёма")
                        .accessibilityIdentifier("mealTime")

                        // Все способы добавить продукт — под одной кнопкой. Сверху те,
                        // что избавляют от ручного ввода: штрихкод, когда есть упаковка,
                        // фото — когда её нет. Ниже — ручные, для «этого нигде нет».
                        Menu {
                            if GeminiVisionService.isConfigured {
                                Button {
                                    showingPhoto = true
                                } label: {
                                    Label("Снять еду", systemImage: "camera")
                                }
                            }
                            Button {
                                showingScanner = true
                            } label: {
                                Label("Сканировать штрихкод", systemImage: "barcode.viewfinder")
                            }
                            Divider()
                            Button {
                                showingNewFood = true
                            } label: {
                                Label("Новый продукт", systemImage: "plus")
                            }
                            Button {
                                showingQuickCalories = true
                            } label: {
                                Label("Только калории", systemImage: "number")
                            }
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityIdentifier("addMenu")
                    }
                }
                // Плавающая кнопка нижней панели перекрывает список. Пока сохранять нечего,
                // она не нужна — показываем её только при непустом черновике.
                if !draftItems.isEmpty {
                    ToolbarItem(placement: .bottomBar) {
                        Button {
                            saveDraft()
                        } label: {
                            Text(verbatim: "\(String(localized: "Сохранить")) · \(draftTotalCalories) \(String(localized: "ккал"))")
                                .frame(maxWidth: .infinity)
                                .fontWeight(.semibold)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            // Чтобы последняя строка не оставалась навсегда под кнопкой.
            .contentMargins(.bottom, draftItems.isEmpty ? 0 : 64, for: .scrollContent)
            .fullScreenCover(item: $serving) { target in
                NavigationStack { servingScreen(target) }
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
            .sheet(isPresented: $showingQuickCalories) {
                // Шит закрываем первым: иначе экран уезжает из-под него и анимация
                // схлопывается в рывок — та же история, что и с экраном порции.
                QuickCaloriesSheet { calories in
                    showingQuickCalories = false
                    saveQuickCalories(calories)
                }
                .presentationDetents([.height(260)])
            }
            .sheet(isPresented: $showingNewFood) {
                NewFoodSheet(store: store)
                    .presentationDetents([.large])
            }
            .sheet(item: $editingFood) { food in
                NewFoodSheet(store: store, editingFood: food)
                    .presentationDetents([.medium])
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
                onAddAndSave: quickAction(enabled: quickSave)
            ) { item in
                addToDraft(item)
            }
        case .dish(let dish):
            DishQuantityView(dish: dish, onAddAndSave: addAndSave) { item in
                addToDraft(item)
            }
        }
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

    /// Запрос живёт ровно до попадания продукта в приём пищи: найденное уже
    /// добавлено, и следующий продукт ищут с чистого листа, а не стирают чужие
    /// буквы. Сбрасываем и debounced-копию, чтобы список вернулся сразу.
    private func addToDraft(_ item: MealItem) {
        draftItems.append(item)
        searchText = ""
        debouncedSearch = ""
    }

    /// Экран порции закрываем первым: иначе лист уезжает из-под открытого поверх
    /// него экрана, и анимация схлопывается в рывок.
    private func addAndSave(_ item: MealItem) {
        serving = nil
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
        dismiss()
    }

    /// Приём пищи, где известно только число калорий. Черновик, если он уже набран,
    /// уходит в дневник вместе с ним — иначе набранное пришлось бы сохранять отдельно.
    private func saveQuickCalories(_ calories: Int) {
        let items = draftItems + [MealItem(name: String(localized: "Приём пищи"), calories: calories, macros: .zero)]
        let totalCalories = items.reduce(0) { $0 + $1.calories }
        let totalMacros = items.reduce(Macros.zero) { $0 + $1.macros }
        let name = items.count == 1 ? String(localized: "Приём пищи") : joinedName(items)
        store.add(name: name, calories: totalCalories, macros: totalMacros, date: entryDate)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        dismiss()
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
        store.customFoods.contains { $0.name == food.name }
    }

    private func saveToMyFoods(_ food: FoodItem) {
        store.addCustomFood(
            name: food.name,
            caloriesPer100g: food.caloriesPer100g,
            protein: food.protein,
            fat: food.fat,
            carbs: food.carbs
        )
    }

    private func foodRow(_ food: FoodItem) -> some View {
        FoodRow(
            name: food.name,
            calories: food.caloriesPer100g,
            portion: "100 \(String(localized: "г"))",
            macros: food.macrosPer100g,
            icons: [food.foodCategory.icon]
        )
    }

    private func dishRow(_ dish: Dish) -> some View {
        FoodRow(
            name: dish.name,
            calories: dish.caloriesPer100g,
            portion: "100 \(String(localized: "г"))",
            macros: dish.macrosPer100g,
            detail: "\(dish.ingredients.count) \(String(localized: "ингр."))",
            icons: store.foodCategories(of: dish).map(\.icon)
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
