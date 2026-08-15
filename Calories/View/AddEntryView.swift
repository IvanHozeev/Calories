import SwiftUI

struct AddEntryView: View {
    @ObservedObject var store: CalorieStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedDate: Date
    @State private var searchText = ""
    @State private var draftItems: [MealItem] = []

    @State private var quickCalories = ""
    @State private var showingNewFood = false
    @State private var editingFood: FoodItem? = nil

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
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else {
            return store.customFoods
        }
        return store.customFoods.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var filteredBuiltInFoods: [FoodItem] {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else {
            return FoodDatabase.items
        }
        return FoodDatabase.items.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var recentFoodItems: [FoodItem] {
        guard searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        let all = store.customFoods + FoodDatabase.items
        return store.recentFoodNames.prefix(8).compactMap { name in
            all.first { $0.name == name }
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

                if !isToday {
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
                                dismiss()
                            }
                            .disabled(Int(quickCalories) == nil)
                            .buttonStyle(.borderedProminent)
                        }
                    } header: {
                        Text("Быстро — только калории")
                    } footer: {
                        Text("Для восстановления данных за прошлый день: впиши сколько всего было съедено — сохранится сразу, без черновика. Если уже добавлены другие продукты выше, они попадут в ту же запись.")
                    }
                }
                
                if !recentFoodItems.isEmpty {
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
                                    Label("Удалить", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    editingFood = food
                                } label: {
                                    Label("Изменить", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                        }
                    }
                }

                Section("База продуктов") {
                    if filteredBuiltInFoods.isEmpty {
                        Text("Ничего не найдено")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(filteredBuiltInFoods) { food in
                            NavigationLink {
                                FoodQuantityView(food: food) { item in
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
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Приём пищи")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingNewFood = true
                    } label: {
                        Image(systemName: "plus.app")
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        store.recordRecentFoods(draftItems.map(\.name))
                        let grams = draftItems.count == 1 ? draftItems[0].grams : nil
                        store.add(name: mealName, calories: draftTotalCalories, macros: draftTotalMacros, grams: grams, date: entryDate)
                        dismiss()
                    } label: {
                        Text(draftItems.isEmpty ? "Сохранить" : "Сохранить (\(draftTotalCalories) ккал)")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(draftItems.isEmpty)
                }
            }
            .sheet(isPresented: $showingNewFood) {
                NewFoodSheet(store: store)
                    .presentationDetents([.medium])
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
    private enum Field: Hashable { case name, calories, protein, fat, carbs }
    @FocusState private var focusedField: Field?

    private var isEditing: Bool { editingFood != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section(isEditing ? "Продукт (на 100 г)" : "Новый продукт (на 100 г)") {
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
                }
                focusedField = .name
            }
        }
    }
}
