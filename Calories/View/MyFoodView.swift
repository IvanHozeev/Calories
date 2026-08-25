import SwiftUI

struct MyFoodView: View {
    var store: CalorieStore

    @State private var showingNewFood = false
    @State private var showingNewDish = false
    @State private var showingScanner = false
    @State private var tab: Tab = .dishes
    @State private var query = ""
    @State private var debouncedQuery = ""
    @State private var remoteResults: [FoodItem] = []
    @State private var isSearchingRemote = false
    @State private var quickAdd: QuickAddTarget?

    enum Tab: String, CaseIterable, Identifiable {
        case dishes, products
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
        guard !trimmedQuery.isEmpty else { return store.customFoods }
        return store.customFoods.filter { $0.name.localizedCaseInsensitiveContains(trimmedQuery) }
    }

    var body: some View {
        List {
            Section {
                Picker("Раздел", selection: $tab) {
                    Text("Блюда (\(filteredDishes.count))").tag(Tab.dishes)
                    Text("Продукты (\(filteredProducts.count))").tag(Tab.products)
                }
                .pickerStyle(.segmented)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            switch tab {
            case .dishes: dishesSection
            case .products: productsSection
            }

            if !trimmedQuery.isEmpty {
                remoteSection
            }
        }
        .glassRow()
        .navigationTitle("Моя еда")
        // См. ContentView: ширину задаём отступом всего списка, потому что стеклянный
        // фон ячейки рисует listRowBackground во всю строку и на listRowInsets не
        // реагирует. Свой фон списка гасим и красим полную ширину сами, иначе в
        // отступах просвечивает белый фон окна.
        .scrollContentBackground(.hidden)
        .padding(.horizontal, 16)
        .background(Color(.systemGroupedBackground))
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

    @ViewBuilder
    private var productsSection: some View {
        if filteredProducts.isEmpty {
            Section {
                Text(trimmedQuery.isEmpty ? "Пока нет своих продуктов" : "Ничего не найдено")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } else {
            Section {
                ForEach(filteredProducts) { food in
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
            macros: food.macrosPer100g.scaled(by: grams)
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
