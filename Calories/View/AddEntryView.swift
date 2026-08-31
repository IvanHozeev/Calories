import SwiftUI

struct AddEntryView: View {
    var store: CalorieStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedDate: Date
    @State private var searchText = ""
    @State private var debouncedSearch = ""
    @State private var draftItems: [MealItem] = []

    @State private var quickCalories = ""
    @State private var showingNewFood = false
    @State private var showingScanner = false
    @State private var editingFood: FoodItem? = nil

    @State private var offResults: [FoodItem] = []
    @State private var isSearchingOFF = false
    @State private var noNetwork = false
    @State private var source: FoodSource = .recent
    @State private var serving: ServingTarget?

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

    @FocusState private var quickCaloriesFocused: Bool

    init(store: CalorieStore, initialDate: Date = Date()) {
        self.store = store
        // Открываем на дне, который просили, но со временем «сейчас»: для сегодняшней
        // записи это привычное поведение, а для прошедшего дня — разумная отправная точка.
        let calendar = Calendar.current
        var parts = calendar.dateComponents([.year, .month, .day], from: initialDate)
        let now = calendar.dateComponents([.hour, .minute], from: Date())
        parts.hour = now.hour
        parts.minute = now.minute
        _selectedDate = State(initialValue: calendar.date(from: parts) ?? initialDate)
    }

    /// Быстрый ввод «только калории» имеет смысл лишь для восстановления прошлых дней —
    /// для сегодняшнего дня продукт стоит указывать явно.
    private var isToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
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
        return FoodDatabase.items.filter { $0.name.localizedCaseInsensitiveContains(debouncedSearch) }
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
            } else if offResults.isEmpty {
                Text("Ничего не найдено")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(offResults) { food in
                    Button {
                        serving = .food(food, savable: true, quickSave: false)
                    } label: {
                        foodRow(food)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    // Время, а не только дата: поел и записал через час — приём пищи
                    // должен встать на то время, когда он был, иначе «вчерашний обед»
                    // попадёт в дневник ночью и перепутает картину дня.
                    DatePicker(
                        "Когда",
                        selection: $selectedDate,
                        in: ...Date(),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }
                .onChange(of: selectedDate) { _, newValue in
                    if Calendar.current.isDateInToday(newValue) {
                        quickCalories = ""
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

                Section {
                    HStack {
                        TextField("Ккал", text: $quickCalories)
                            .keyboardType(.numberPad)
                            .font(.title3.weight(.semibold))
                            .focused($quickCaloriesFocused)
                        Button("Сохранить") {
                            guard let calories = Int(quickCalories) else { return }
                            let items = draftItems + [MealItem(name: String(localized: "Приём пищи"), calories: calories, macros: .zero)]
                            let totalCalories = items.reduce(0) { $0 + $1.calories }
                            let totalMacros = items.reduce(Macros.zero) { $0 + $1.macros }
                            let name = items.count == 1 ? String(localized: "Приём пищи") : joinedName(items)
                            store.add(name: name, calories: totalCalories, macros: totalMacros, date: entryDate)
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            dismiss()
                        }
                        .disabled(Int(quickCalories) == nil)
                        .buttonStyle(.borderedProminent)
                    }
                } header: {
                    Text("Быстро — только калории")
                }

                Section {
                    Picker("Источник", selection: $source) {
                        ForEach(FoodSource.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                    .listRowBackground(Color.clear)
                }

                if source == .recent, !recentFoodItems.isEmpty || !recentDishItems.isEmpty {
                    Section("Недавнее") {
                        ForEach(recentFoodItems) { food in
                            Button {
                                serving = .food(food, savable: false, quickSave: true)
                            } label: {
                                foodRow(food)
                            }
                            .buttonStyle(.plain)
                        }
                        ForEach(recentDishItems) { dish in
                            Button {
                                serving = .dish(dish)
                            } label: {
                                dishRow(dish)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if source == .mine, !filteredDishes.isEmpty {
                    Section("Мои блюда") {
                        ForEach(filteredDishes) { dish in
                            Button {
                                serving = .dish(dish)
                            } label: {
                                dishRow(dish)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Свои продукты тоже разложены по категориям: их накапливается
                // не меньше, чем в базе. «Недавнее» намеренно оставлено плоским —
                // там порядок и есть смысл: сверху последнее съеденное, и
                // группировка сломала бы именно то, ради чего туда заходят.
                if source == .mine {
                    ForEach(grouped(filteredCustomFoods), id: \.0) { category, foods in
                        Section {
                            ForEach(foods) { food in
                                Button {
                                    serving = .food(food, savable: false, quickSave: true)
                                } label: {
                                    foodRow(food)
                                }
                                .buttonStyle(.plain)
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

                if source == .online {
                    offSearchSection
                }

                if source == .database {
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
                                    Button {
                                        serving = .food(food, savable: true, quickSave: true)
                                    } label: {
                                        foodRow(food)
                                    }
                                    .buttonStyle(.plain)
                                }
                            } header: {
                                Label(category.title, systemImage: category.icon)
                            }
                        }
                    }
                }

                // Пустой результат — тупик, если не подсказать, где искать дальше.
                if source != .online, currentSourceIsEmpty, !debouncedSearch.isEmpty {
                    Section {
                        Button {
                            source = .online
                        } label: {
                            Label("Поискать в интернете", systemImage: "globe")
                        }
                    } footer: {
                        Text("В выбранном источнике ничего не нашлось.")
                    }
                }
            }
            .glassRow()
            // Поиск закреплён в навбаре намеренно. При размещении по умолчанию
            // строка поиска уходит вниз экрана — туда же, где появляется панель
            // с кнопкой «Сохранить», как только в черновике есть хоть один продукт.
            // Панель выигрывала это место, поиск пропадал насовсем, и добавить
            // второй продукт становилось нечем.
            .searchable(text: $searchText,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Поиск продукта")
            // Сетевой поиск ходит в сеть только на своей вкладке. Раньше он уходил
            // на каждое нажатие клавиши, даже когда искали в своих продуктах.
            .task(id: "\(source.rawValue)|\(searchText)") {
                debouncedSearch = searchText
                guard source == .online else {
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
                    let results = try await OpenFoodService.search(query: searchText)
                    guard !Task.isCancelled else { isSearchingOFF = false; return }
                    offResults = results
                    noNetwork = false
                } catch let urlError as URLError where
                    urlError.code == .notConnectedToInternet ||
                    urlError.code == .networkConnectionLost ||
                    urlError.code == .timedOut ||
                    urlError.code == .cannotFindHost ||
                    urlError.code == .cannotConnectToHost {
                    noNetwork = true
                } catch {
                    // CancellationError или decode error — просто сбрасываем индикатор
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
                        Button {
                            showingScanner = true
                        } label: {
                            Image(systemName: "barcode.viewfinder")
                        }
                        Button {
                            showingNewFood = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
                // Плавающая кнопка нижней панели перекрывает список. Пока сохранять нечего,
                // она не нужна — показываем её только при непустом черновике.
                if !draftItems.isEmpty {
                    ToolbarItem(placement: .bottomBar) {
                        Button {
                            let grams = draftItems.count == 1 ? draftItems[0].grams : nil
                            store.add(name: mealName, calories: draftTotalCalories, macros: draftTotalMacros, grams: grams, date: entryDate)
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            dismiss()
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
            .sheet(isPresented: $showingScanner) {
                BarcodeScannerSheet(store: store) { item in
                    draftItems.append(item)
                }
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
                draftItems.append(item)
            }
        case .dish(let dish):
            DishQuantityView(dish: dish, onAddAndSave: addAndSave) { item in
                draftItems.append(item)
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

    /// Экран порции закрываем первым: иначе лист уезжает из-под открытого поверх
    /// него экрана, и анимация схлопывается в рывок.
    private func addAndSave(_ item: MealItem) {
        serving = nil
        let allItems = draftItems + [item]
        let totalCalories = allItems.reduce(0) { $0 + $1.calories }
        let totalMacros = allItems.reduce(Macros.zero) { $0 + $1.macros }
        let name = allItems.count == 1 ? item.name : joinedName(allItems)
        let grams = allItems.count == 1 ? item.grams : nil
        store.add(name: name, calories: totalCalories, macros: totalMacros, grams: grams, date: entryDate)
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
            icon: food.foodCategory.icon
        )
    }

    private func dishRow(_ dish: Dish) -> some View {
        FoodRow(
            name: dish.name,
            calories: dish.caloriesPer100g,
            portion: "100 \(String(localized: "г"))",
            macros: dish.macrosPer100g,
            detail: "\(dish.ingredients.count) \(String(localized: "ингр."))"
        )
    }
}
