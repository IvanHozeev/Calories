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
    @State private var quickAdd: QuickAddTarget?

    enum Tab: String, CaseIterable, Identifiable {
        case dishes, products, database
        var id: String { rawValue }
    }

    /// Что именно кладём в дневник. Блюда и продукты хранятся разными типами,
    /// поэтому шит принимает уже приведённые к «на 100 г» значения.
    struct QuickAddTarget: Identifiable {
        let id = UUID()
        let name: String
        let caloriesPer100g: Int
        let macrosPer100g: Macros
        let defaultGrams: Double
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
        var items = FoodDatabase.items
        if let categoryFilter {
            items = items.filter { $0.foodCategory == categoryFilter }
        }
        guard !trimmedQuery.isEmpty else { return items }
        return items.filter { $0.name.localizedCaseInsensitiveContains(trimmedQuery) }
    }

    /// Категории берём из того раздела, который открыт: фильтровать базу по
    /// категориям своих продуктов бессмысленно, и наоборот.
    private var usedCategories: [FoodCategory] {
        let source = tab == .database ? FoodDatabase.items : store.customFoods
        let used = Set(source.map(\.foodCategory))
        return FoodCategory.allCases.filter { used.contains($0) }
    }

    var body: some View {
        List {
            Section {
                Picker("Раздел", selection: $tab) {
                    Text("Блюда (\(filteredDishes.count))").tag(Tab.dishes)
                    Text("Продукты (\(filteredProducts.count))").tag(Tab.products)
                    Text("База (\(filteredDatabase.count))").tag(Tab.database)
                }
                .pickerStyle(.segmented)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            switch tab {
            case .dishes: dishesSection
            case .products: productsSection
            case .database: databaseSection
            }

            if !trimmedQuery.isEmpty {
                remoteSection
            }
        }
        .glassRow()
        .navigationTitle("Моя еда")
        .scrollIndicators(.hidden)
        .searchable(text: $query, prompt: Text("Поиск в базе или моих блюдах"))
        .task(id: query) {
            // Свои списки фильтруются мгновенно, а сеть дёргаем только после паузы.
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            debouncedQuery = query

            let text = query.trimmingCharacters(in: .whitespaces)
            guard text.count >= 3 else { remoteResults = []; isSearchingRemote = false; return }
            isSearchingRemote = true
            defer { isSearchingRemote = false }
            remoteResults = (try? await OpenFoodService.search(query: text)) ?? []
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

            ToolbarItem(placement: .topBarTrailing) {
                Button { showingScanner = true } label: {
                    Image(systemName: "barcode.viewfinder")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showingNewFood = true } label: {
                        Label("Новый продукт", systemImage: "plus")
                    }
                    Button { showingNewDish = true } label: {
                        Label("Новое блюдо", systemImage: "fork.knife")
                    }
                } label: {
                    Image(systemName: "plus")
                }
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
        .sheet(item: $quickAdd) { target in
            QuickAddSheet(
                store: store,
                name: target.name,
                caloriesPer100g: target.caloriesPer100g,
                macrosPer100g: target.macrosPer100g,
                defaultGrams: target.defaultGrams
            )
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Блюда

    @ViewBuilder
    private var dishesSection: some View {
        if filteredDishes.isEmpty {
            Section {
                Text(trimmedQuery.isEmpty ? "Пока нет своих блюд" : "Ничего не найдено")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
                            detail: "\(dish.ingredients.count) \(String(localized: "ингр."))"
                        )
                    }
                    .swipeActions(edge: .leading) {
                        quickAddButton {
                            QuickAddTarget(
                                name: dish.name,
                                caloriesPer100g: dish.caloriesPer100g,
                                macrosPer100g: dish.macrosPer100g,
                                defaultGrams: dish.totalGrams > 0 ? dish.totalGrams : 100
                            )
                        }
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
    private var databaseSection: some View {
        if filteredDatabase.isEmpty {
            Section {
                Text("Ничего не найдено")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } else {
            ForEach(grouped(filteredDatabase), id: \.0) { category, foods in
                Section {
                    ForEach(foods) { food in
                        NavigationLink {
                            FoodDetailView(food: food, store: store)
                        } label: {
                            foodRow(food)
                        }
                        .swipeActions(edge: .leading) {
                            quickAddButton { target(for: food) }
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
    private var productsSection: some View {
        if filteredProducts.isEmpty {
            Section {
                Text(trimmedQuery.isEmpty ? "Пока нет своих продуктов" : "Ничего не найдено")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } else {
            // Свои продукты разложены так же, как база: список копится и без
            // заголовков читается ничуть не лучше встроенного.
            ForEach(grouped(filteredProducts), id: \.0) { category, foods in
                Section {
                    ForEach(foods) { food in
                        NavigationLink {
                            FoodDetailView(food: food, store: store)
                        } label: {
                            foodRow(food)
                        }
                        .swipeActions(edge: .leading) {
                            quickAddButton { target(for: food) }
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
        Section {
            if isSearchingRemote {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Ищем…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else if remoteResults.isEmpty {
                Text("В базе продуктов ничего не найдено")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(remoteResults) { food in
                    Button {
                        quickAdd = target(for: food)
                    } label: {
                        HStack {
                            foodRow(food)
                            Spacer()
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(.blue)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Text("Открытая база продуктов")
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
            icon: food.foodCategory.icon
        )
    }

    private func target(for food: FoodItem) -> QuickAddTarget {
        QuickAddTarget(
            name: food.name,
            caloriesPer100g: food.caloriesPer100g,
            macrosPer100g: food.macrosPer100g,
            defaultGrams: food.defaultGrams > 0 ? food.defaultGrams : 100
        )
    }

    private func quickAddButton(_ make: @escaping () -> QuickAddTarget) -> some View {
        Button {
            quickAdd = make()
        } label: {
            Image(systemName: "plus.circle.fill")
        }
        .tint(.blue)
    }
}
