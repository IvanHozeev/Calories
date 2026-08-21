import SwiftUI

struct AddEntryView: View {
    @ObservedObject var store: CalorieStore
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
        let all = store.customFoods + FoodDatabase.items
        return store.recentFoodNames.prefix(8).compactMap { name in
            all.first { $0.name == name }
        }
    }

    private var recentDishItems: [Dish] {
        guard debouncedSearch.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        return store.recentFoodNames.prefix(8).compactMap { name in
            store.dishes.first { $0.name == name }
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
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                    Text("Б\(Int(item.macros.protein)) Ж\(Int(item.macros.fat)) У\(Int(item.macros.carbs))")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(item.calories) ккал")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .onDelete { offsets in
                            draftItems.remove(atOffsets: offsets)
                        }

                        HStack {
                            Text("Итого")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\(draftTotalCalories) ккал")
                                .font(.subheadline.weight(.semibold))
                        }
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
                            let items = draftItems + [MealItem(name: "Приём пищи", calories: calories, macros: .zero)]
                            let totalCalories = items.reduce(0) { $0 + $1.calories }
                            let totalMacros = items.reduce(Macros.zero) { $0 + $1.macros }
                            let name = items.count == 1 ? "Приём пищи" : joinedName(items)
                            store.recordRecentFoods(draftItems.map(\.name))
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
                                FoodQuantityView(food: food) { item in
                                    draftItems.append(item)
                                }
                            } label: {
                                foodRow(food)
                            }
                        }
                        ForEach(recentDishItems) { dish in
                            NavigationLink {
                                DishQuantityView(dish: dish) { item in
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
                                DishQuantityView(dish: dish) { item in
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
                                FoodQuantityView(food: food) { item in
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
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        store.recordRecentFoods(draftItems.map(\.name))
                        let grams = draftItems.count == 1 ? draftItems[0].grams : nil
                        store.add(name: mealName, calories: draftTotalCalories, macros: draftTotalMacros, grams: grams, date: entryDate)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        dismiss()
                    } label: {
                        Text(draftItems.isEmpty ? "Сохранить" : "Сохранить (\(draftTotalCalories) ккал)")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(draftItems.isEmpty)
                }
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
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(food.name)
                Text("Б\(Int(food.macrosPer100g.protein)) Ж\(Int(food.macrosPer100g.fat)) У\(Int(food.macrosPer100g.carbs))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(food.caloriesPer100g) ккал/100г")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func dishRow(_ dish: Dish) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(dish.name)
                Text("Б\(Int(dish.macrosPer100g.protein)) Ж\(Int(dish.macrosPer100g.fat)) У\(Int(dish.macrosPer100g.carbs))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(dish.caloriesPer100g) ккал/100г")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct NewFoodSheet: View {
    @ObservedObject var store: CalorieStore
    @Environment(\.dismiss) private var dismiss

    var editingFood: FoodItem? = nil

    @State private var name = ""
    @State private var caloriesPer100g = ""
    @State private var protein = ""
    @State private var fat = ""
    @State private var carbs = ""
    private enum Field: Hashable { case search, name, calories, protein, fat, carbs }
    @FocusState private var focusedField: Field?

    @State private var searchQuery = ""
    @State private var offResults: [FoodItem] = []
    @State private var isSearchingOFF = false

    private var isEditing: Bool { editingFood != nil }

    var body: some View {
        NavigationStack {
            Form {
                if !isEditing {
                    Section {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)
                            TextField("Найти в базе данных...", text: $searchQuery)
                                .autocorrectionDisabled()
                                .focused($focusedField, equals: .search)
                            if isSearchingOFF {
                                ProgressView()
                            } else if !searchQuery.isEmpty {
                                Button {
                                    searchQuery = ""
                                    offResults = []
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        if !offResults.isEmpty {
                            ForEach(offResults.prefix(12), id: \.id) { food in
                                Button {
                                    fillFrom(food)
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(food.name)
                                                .foregroundStyle(.primary)
                                            Text("Б\(Int(food.protein)) Ж\(Int(food.fat)) У\(Int(food.carbs))")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Text("\(food.caloriesPer100g) ккал/100г")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("Поиск")
                    }
                }

                Section(isEditing ? "Продукт (на 100 г)" : "Данные на 100 г") {
                    TextField("Название", text: $name)
                        .focused($focusedField, equals: .name)
                    TextField("Калории", text: $caloriesPer100g)
                        .keyboardType(.numberPad)
                        .focused($focusedField, equals: .calories)
                    TextField("Белки, г", text: $protein)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .protein)
                    TextField("Жиры, г", text: $fat)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .fat)
                    TextField("Углеводы, г", text: $carbs)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .carbs)
                }
            }
            .task(id: searchQuery) {
                guard !searchQuery.isEmpty else { offResults = []; isSearchingOFF = false; return }
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                isSearchingOFF = true
                offResults = (try? await OpenFoodService.search(query: searchQuery)) ?? []
                isSearchingOFF = false
            }
            .navigationTitle(isEditing ? "Редактировать" : "Свой продукт")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    CheckmarkButton {
                        guard let calories = Int(caloriesPer100g),
                              !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        let p = Double(protein.replacingOccurrences(of: ",", with: ".")) ?? 0
                        let f = Double(fat.replacingOccurrences(of: ",", with: ".")) ?? 0
                        let c = Double(carbs.replacingOccurrences(of: ",", with: ".")) ?? 0
                        if let food = editingFood {
                            store.updateCustomFood(food, name: name, caloriesPer100g: calories, protein: p, fat: f, carbs: c)
                        } else {
                            store.addCustomFood(name: name, caloriesPer100g: calories, protein: p, fat: f, carbs: c)
                        }
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || Int(caloriesPer100g) == nil)
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                if let food = editingFood {
                    name = food.name
                    caloriesPer100g = "\(food.caloriesPer100g)"
                    protein = food.protein > 0 ? String(format: "%g", food.protein) : ""
                    fat = food.fat > 0 ? String(format: "%g", food.fat) : ""
                    carbs = food.carbs > 0 ? String(format: "%g", food.carbs) : ""
                    focusedField = .name
                } else {
                    focusedField = .search
                }
            }
        }
    }

    private func fillFrom(_ food: FoodItem) {
        name = food.name
        caloriesPer100g = "\(food.caloriesPer100g)"
        protein = food.protein > 0 ? String(format: "%g", food.protein) : ""
        fat = food.fat > 0 ? String(format: "%g", food.fat) : ""
        carbs = food.carbs > 0 ? String(format: "%g", food.carbs) : ""
        searchQuery = ""
        offResults = []
        focusedField = .name
    }
}
