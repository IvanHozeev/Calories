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

    @FocusState private var quickCaloriesFocused: Bool

    init(store: CalorieStore, initialDate: Date = Date()) {
        self.store = store
        _selectedDate = State(initialValue: initialDate)
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

    private var recentFoodItems: [FoodItem] {
        guard debouncedSearch.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        return store.recentFoods
    }

    private var recentDishItems: [Dish] {
        guard debouncedSearch.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        return store.recentDishes
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
                    NavigationLink {
                        FoodQuantityView(food: food, onSave: isSaved(food) ? nil : { saveToMyFoods(food) }) { item in
                            draftItems.append(item)
                        }
                    } label: {
                        foodRow(food)
                    }
                }
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    DatePicker(
                        "Дата",
                        selection: $selectedDate,
                        in: ...Date(),
                        displayedComponents: .date
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

                if !recentFoodItems.isEmpty || !recentDishItems.isEmpty {
                    Section("Недавнее") {
                        ForEach(recentFoodItems) { food in
                            NavigationLink {
                                FoodQuantityView(food: food, onAddAndSave: addAndSave) { item in
                                    draftItems.append(item)
                                }
                            } label: {
                                foodRow(food)
                            }
                        }
                        ForEach(recentDishItems) { dish in
                            NavigationLink {
                                DishQuantityView(dish: dish, onAddAndSave: addAndSave) { item in
                                    draftItems.append(item)
                                }
                            } label: {
                                dishRow(dish)
                            }
                        }
                    }
                }

                if !filteredDishes.isEmpty {
                    Section("Мои блюда") {
                        ForEach(filteredDishes) { dish in
                            NavigationLink {
                                DishQuantityView(dish: dish, onAddAndSave: addAndSave) { item in
                                    draftItems.append(item)
                                }
                            } label: {
                                dishRow(dish)
                            }
                        }
                    }
                }

                if !filteredCustomFoods.isEmpty {
                    Section("Мои продукты") {
                        ForEach(filteredCustomFoods) { food in
                            NavigationLink {
                                FoodQuantityView(food: food, onAddAndSave: addAndSave) { item in
                                    draftItems.append(item)
                                }
                            } label: {
                                foodRow(food)
                            }
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
                    }
                }

                if isSearchingOFF || !debouncedSearch.isEmpty {
                    offSearchSection
                }

                Section("База продуктов") {
                    if filteredBuiltInFoods.isEmpty {
                        Text("Ничего не найдено")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(filteredBuiltInFoods) { food in
                            NavigationLink {
                                FoodQuantityView(food: food, onSave: isSaved(food) ? nil : { saveToMyFoods(food) }, onAddAndSave: addAndSave) { item in
                                    draftItems.append(item)
                                }
                            } label: {
                                foodRow(food)
                            }
                        }
                    }
                }
            }
            .glassRow()
            .searchable(text: $searchText, prompt: "Поиск продукта")
            .task(id: searchText) {
                guard !searchText.isEmpty else {
                    debouncedSearch = ""
                    offResults = []
                    noNetwork = false
                    isSearchingOFF = false
                    return
                }
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                debouncedSearch = searchText
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

    /// День из пикера + текущее время суток — чтобы у приёма пищи было осмысленное время.
    private var entryDate: Date {
        let calendar = Calendar.current
        var dayComponents = calendar.dateComponents([.year, .month, .day], from: selectedDate)
        let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: Date())
        dayComponents.hour = timeComponents.hour
        dayComponents.minute = timeComponents.minute
        dayComponents.second = timeComponents.second
        return calendar.date(from: dayComponents) ?? selectedDate
    }

    private func addAndSave(_ item: MealItem) {
        let allItems = draftItems + [item]
        let totalCalories = allItems.reduce(0) { $0 + $1.calories }
        let totalMacros = allItems.reduce(Macros.zero) { $0 + $1.macros }
        let name = allItems.count == 1 ? item.name : joinedName(allItems)
        let grams = allItems.count == 1 ? item.grams : nil
        store.add(name: name, calories: totalCalories, macros: totalMacros, grams: grams, date: entryDate)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        dismiss()
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
            macros: food.macrosPer100g
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
