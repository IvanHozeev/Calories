import SwiftUI

struct MyFoodView: View {
    var store: CalorieStore

    @State private var showingNewFood = false
    @State private var showingNewDish = false
    @State private var showingScanner = false
    @State private var tab: Tab = .dishes
    @State private var query = ""
    /// nil — показывать все категории.
    @State private var categoryFilter: FoodCategory?
    @State private var debouncedQuery = ""
    @State private var remoteResults: [FoodItem] = []
    @State private var isSearchingRemote = false
    @State private var serving: ServingTarget?

    enum Tab: String, CaseIterable, Identifiable {
        case dishes, products, database
        var id: String { rawValue }
    }

    /// Что записываем в дневник прямо отсюда — продукт или блюдо.
    ///
    /// Открывается тот же экран порции, что и в листе добавления еды. Раньше
    /// здесь был свой лист «Добавить в дневник» с выбором приёма пищи и полем
    /// веса — второй, непохожий способ сделать то же самое.
    enum ServingTarget: Identifiable {
        case food(FoodItem)
        case dish(Dish)

        var id: String {
            switch self {
            case .food(let food): return "food-\(food.id.uuidString)"
            case .dish(let dish): return "dish-\(dish.id.uuidString)"
            }
        }
    }

    /// Есть ли что показать из внешней базы — или она ещё ищет.
    /// Пока так, «Ничего не найдено» над её результатами было бы враньём.
    private var remoteHasOrMayHaveResults: Bool {
        !trimmedQuery.isEmpty && (isSearchingRemote || !remoteResults.isEmpty)
    }

    private var trimmedQuery: String {
        debouncedQuery.trimmingCharacters(in: .whitespaces)
    }

    private var filteredDishes: [Dish] {
        guard !trimmedQuery.isEmpty else { return store.dishes }
        return store.dishes.filter { $0.name.localizedCaseInsensitiveContains(trimmedQuery) }
    }

    private var filteredProducts: [FoodItem] {
        var items = store.customFoods
        if let categoryFilter {
            items = items.filter { $0.foodCategory == categoryFilter }
        }
        guard !trimmedQuery.isEmpty else { return items }
        return items.filter { $0.name.localizedCaseInsensitiveContains(trimmedQuery) }
    }

    /// Встроенная база. Она тут не для полноты: свой продукт заводят как раз
    /// глядя на похожий из базы, и ради этого раньше приходилось уходить в
    /// лист добавления еды.
    private var filteredDatabase: [FoodItem] {
        // Сначала поиск, потом категория: поиск уже отдаёт результаты по
        // убыванию уместности, и фильтр по категории этот порядок сохраняет.
        var items = trimmedQuery.isEmpty
            ? FoodDatabase.items
            : FoodDatabase.search(trimmedQuery, limit: 200)
        if let categoryFilter {
            items = items.filter { $0.foodCategory == categoryFilter }
        }
        return items
    }

    /// Категории берём из того раздела, который открыт: фильтровать базу по
    /// категориям своих продуктов бессмысленно, и наоборот.
    private var usedCategories: [FoodCategory] {
        let source = tab == .database ? FoodDatabase.items : store.customFoods
        let used = Set(source.map(\.foodCategory))
        return FoodCategory.allCases.filter { used.contains($0) }
    }

    var body: some View {
        // Отборы считаем по разу за перерисовку и передаём дальше: они нужны и
        // в подписях сегментов, и в самой секции, а каждый — это проход
        // с локале-зависимым сравнением по всей базе.
        let dishes = filteredDishes
        let products = filteredProducts
        let database = filteredDatabase

        return List {
            Section {
                Picker("Раздел", selection: $tab) {
                    // Без счётчиков: «Мои продукты (128)» не влезает в сегмент и
                    // обрезается многоточием, а количество и так видно в списке.
                    Text("Мои блюда").tag(Tab.dishes)
                    Text("Мои продукты").tag(Tab.products)
                    Text("База").tag(Tab.database)
                }
                .pickerStyle(.segmented)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            // Недавнее показываем только на нетронутом экране: когда человек
            // уже ищет или отфильтровал категорию, он знает, что ему нужно, и
            // повторный список сверху только мешает.
            if trimmedQuery.isEmpty, categoryFilter == nil {
                recentSection
            }

            switch tab {
            case .dishes: dishesSection(dishes)
            case .products: productsSection(products)
            case .database: databaseSection(database)
            }

            if !trimmedQuery.isEmpty {
                remoteSection
            }
        }
        .glassRow()
        .navigationTitle("Рацион")
        .scrollIndicators(.hidden)
        .searchable(text: $query, prompt: Text("Поиск в базе или моих блюдах"))
        // Клавиатура уходит протягиванием списка вниз, как в остальных списках.
        .scrollDismissesKeyboard(.interactively)
        .task(id: query) {
            // Свои списки фильтруются мгновенно, а сеть дёргаем только после паузы.
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            debouncedQuery = query

            let text = query.trimmingCharacters(in: .whitespaces)
            guard text.count >= 3 else { remoteResults = []; isSearchingRemote = false; return }
            isSearchingRemote = true
            defer { isSearchingRemote = false }
            remoteResults = (try? await FoodSearch.search(query: text)) ?? []
        }
        .toolbar {
            // Фильтр — меню, а не полоса чипов: категорий девять, полосой они
            // не помещаются и превращаются в горизонтальную прокрутку, где
            // выбранная категория уезжает из виду.
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Категория", selection: $categoryFilter) {
                        Text("Все категории").tag(FoodCategory?.none)
                        ForEach(usedCategories) { item in
                            Label(item.title, systemImage: item.icon).tag(FoodCategory?.some(item))
                        }
                    }
                } label: {
                    Image(systemName: categoryFilter == nil
                          ? "line.3.horizontal.decrease.circle"
                          : "line.3.horizontal.decrease.circle.fill")
                }
                .accessibilityIdentifier("categoryFilter")
                .accessibilityLabel("Категория")
            }

            // Все способы пополнить справочник — под одной кнопкой, как и на
            // экране приёма пищи. Сверху штрихкод: он избавляет от ручного ввода,
            // ниже — то, что придётся заполнять самому.
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showingScanner = true } label: {
                        Label("Сканировать штрихкод", systemImage: "barcode.viewfinder")
                    }
                    Divider()
                    Button { showingNewFood = true } label: {
                        Label("Новый продукт", systemImage: "plus")
                    }
                    Button { showingNewDish = true } label: {
                        Label("Новое блюдо", systemImage: "fork.knife")
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier("addMenu")
            }

        }
        .sheet(isPresented: $showingNewFood) {
            NewFoodSheet(store: store)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showingNewDish) {
            NewDishSheet(store: store)
        }
        .sheet(isPresented: $showingScanner) {
            BarcodeScannerSheet(store: store)
        }
        .sheet(item: $serving) { target in
            NavigationStack {
                switch target {
                case .food(let food):
                    FoodQuantityView(
                        food: food,
                        onSave: store.isInMyFoods(food) ? nil : { store.saveToMyFoods(food) }
                    ) { item in
                        record(item)
                    }
                case .dish(let dish):
                    DishQuantityView(dish: dish) { item in
                        record(item)
                    }
                }
            }
        }
    }

    // MARK: - Блюда

    /// Недавно заведённое и поправленное — сверху, до общего списка.
    ///
    /// Продукт заводят ровно тогда, когда собираются им пользоваться, а в
    /// списке по категориям он лежит вперемешку с теми, что завели полгода
    /// назад, и его приходится искать глазами сразу после создания.
    @ViewBuilder
    private var recentSection: some View {
        switch tab {
        case .dishes:
            let recent = store.dishes
                .sorted { ($0.updatedAt ?? $0.createdAt) > ($1.updatedAt ?? $1.createdAt) }
                .prefix(3)
            if recent.count > 1 {
                Section("Недавнее") {
                    ForEach(recent) { dish in
                        NavigationLink {
                            NewDishSheet(store: store, editingDish: dish, isEmbedded: true)
                        } label: {
                            FoodRow(
                                name: dish.name,
                                calories: dish.totalCalories,
                                portion: String(format: "%.0f \(String(localized: "г"))", dish.totalGrams),
                                macros: dish.totalMacros,
                                detail: "\(dish.ingredients.count) \(String(localized: "ингр."))",
                                icons: store.foodCategories(of: dish).map(\.icon),
                                leadingMacros: dish.macrosPer100g
                            )
                        }
                        .leadingMacroRow(dish.macrosPer100g)
                    }
                }
            }
        case .products:
            let recent = store.customFoods
                .filter { $0.updatedAt != nil }
                .sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
                .prefix(3)
            if recent.count > 1 {
                Section("Недавнее") {
                    ForEach(recent) { food in
                        NavigationLink {
                            NewFoodSheet(store: store, editingFood: food, isEmbedded: true)
                        } label: {
                            foodRow(food)
                        }
                        .leadingMacroRow(food.macrosPer100g)
                    }
                }
            }
        case .database:
            EmptyView()
        }
    }

    @ViewBuilder
    private func dishesSection(_ filteredDishes: [Dish]) -> some View {
        if filteredDishes.isEmpty {
            if trimmedQuery.isEmpty || !remoteHasOrMayHaveResults {
            Section {
                Text(trimmedQuery.isEmpty ? "Пока нет своих блюд" : "Ничего не найдено")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            }
        } else {
            Section {
                ForEach(filteredDishes) { dish in
                    NavigationLink {
                        NewDishSheet(store: store, editingDish: dish, isEmbedded: true)
                    } label: {
                        FoodRow(
                            name: dish.name,
                            calories: dish.totalCalories,
                            portion: String(format: "%.0f \(String(localized: "г"))", dish.totalGrams),
                            macros: dish.totalMacros,
                            detail: "\(dish.ingredients.count) \(String(localized: "ингр."))",
                            icons: store.foodCategories(of: dish).map(\.icon),
                            leadingMacros: dish.macrosPer100g
                        )
                    }
                    .leadingMacroRow(dish.macrosPer100g)
                    .swipeActions(edge: .leading) {
                        recordButton { serving = .dish(dish) }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            store.deleteDish(dish)
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Продукты

    /// База разложена по категориям, как и в листе добавления еды: одним
    /// списком из шести десятков строк она не читается.
    @ViewBuilder
    private func databaseSection(_ filteredDatabase: [FoodItem]) -> some View {
        if filteredDatabase.isEmpty {
            if !remoteHasOrMayHaveResults {
                Section {
                    Text("Ничего не найдено")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            ForEach(grouped(filteredDatabase), id: \.0) { category, foods in
                Section {
                    ForEach(foods) { food in
                        // Строку каталога изменить нельзя — она лежит файлом в
                        // бандле, — поэтому экран только показывает. Структура
                        // у него та же, что у своего продукта.
                        NavigationLink {
                            CatalogFoodView(food: food, store: store)
                        } label: {
                            foodRow(food)
                        }
                        .leadingMacroRow(food.macrosPer100g)
                        .swipeActions(edge: .leading) {
                            recordButton { serving = .food(food) }
                            saveToMyFoodsButton(food)
                        }
                    }
                } header: {
                    Label(category.title, systemImage: category.icon)
                }
            }
        }
    }

    /// Порядок берём из самого перечисления — он осмысленный (мясо, рыба,
    /// молочное...), в отличие от алфавитного.
    private func grouped(_ foods: [FoodItem]) -> [(FoodCategory, [FoodItem])] {
        let buckets = Dictionary(grouping: foods, by: \.foodCategory)
        return FoodCategory.allCases.compactMap { category in
            guard let items = buckets[category], !items.isEmpty else { return nil }
            return (category, items)
        }
    }

    @ViewBuilder
    private func productsSection(_ filteredProducts: [FoodItem]) -> some View {
        if filteredProducts.isEmpty {
            if trimmedQuery.isEmpty || !remoteHasOrMayHaveResults {
            Section {
                Text(trimmedQuery.isEmpty ? "Пока нет своих продуктов" : "Ничего не найдено")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            }
        } else {
            // Свои продукты разложены так же, как база: список копится и без
            // заголовков читается ничуть не лучше встроенного.
            ForEach(grouped(filteredProducts), id: \.0) { category, foods in
                Section {
                    ForEach(foods) { food in
                        // Свой продукт открывается сразу редактируемым — как блюдо.
                        // Отдельная кнопка-карандаш на экране-детали была лишним
                        // шагом ровно там, куда и заходят, чтобы что-то поправить.
                        NavigationLink {
                            NewFoodSheet(store: store, editingFood: food, isEmbedded: true)
                        } label: {
                            foodRow(food)
                        }
                        .leadingMacroRow(food.macrosPer100g)
                        .swipeActions(edge: .leading) {
                            recordButton { serving = .food(food) }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                store.deleteCustomFood(food)
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                    }
                } header: {
                    Label(category.title, systemImage: category.icon)
                }
            }
        }
    }

    // MARK: - Внешняя база

    @ViewBuilder
    private var remoteSection: some View {
        if isSearchingRemote || !remoteResults.isEmpty {
            Section {
                if isSearchingRemote && remoteResults.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Ищем…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    // Строка как в базе: тап открывает тот же экран продукта,
                    // свайп — записать или положить в свои. Отдельный синий плюс
                    // в строке был единственной такой кнопкой во всём приложении.
                    ForEach(remoteResults) { food in
                        NavigationLink {
                            CatalogFoodView(food: food, store: store)
                        } label: {
                            foodRow(food)
                        }
                        .leadingMacroRow(food.macrosPer100g)
                        .swipeActions(edge: .leading) {
                            recordButton { serving = .food(food) }
                            saveToMyFoodsButton(food)
                        }
                    }
                }
            } header: {
                Text("Открытая база продуктов")
            }
        }
    }

    // MARK: - Общее

    private func foodRow(_ food: FoodItem) -> some View {
        let grams = food.defaultGrams > 0 ? food.defaultGrams : 100
        let kcal = Int((Double(food.caloriesPer100g) * grams / 100).rounded())
        return FoodRow(
            name: food.name,
            calories: kcal,
            portion: "\(Int(grams)) \(String(localized: "г"))",
            macros: food.macrosPer100g.scaled(by: grams),
            icons: [food.foodCategory.icon],
            micros: store.notableMicronutrients(forFoodNamed: food.name, grams: grams),
            offersVitamins: store.foodsOfferedVitamins.contains(food.id),
            leadingMacros: food.macrosPer100g
        )
    }

    /// Записать в дневник: открывает экран порции.
    private func recordButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "fork.knife")
        }
        .tint(.blue)
        .accessibilityLabel("В приём пищи")
    }

    /// Положить продукт из базы в свои — одним свайпом, не открывая его.
    @ViewBuilder
    private func saveToMyFoodsButton(_ food: FoodItem) -> some View {
        if !store.isInMyFoods(food) {
            Button {
                store.saveToMyFoods(food)
            } label: {
                Image(systemName: "bookmark")
            }
            .tint(.indigo)
            .accessibilityLabel("В мои продукты")
        }
    }

    /// Запись с экрана порции прямо в дневник.
    private func record(_ item: MealItem) {
        store.add(name: item.name, calories: item.calories, macros: item.macros, grams: item.grams)
    }
}
