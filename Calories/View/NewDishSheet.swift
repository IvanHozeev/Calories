import SwiftUI

struct NewDishSheet: View {
    var store: CalorieStore
    @Environment(\.dismiss) private var dismiss
    var editingDish: Dish? = nil
    var isEmbedded: Bool = false

    @State private var name = ""
    @State private var ingredients: [DishIngredient] = []
    @State private var showingIngredientPicker = false
    @State private var showDiscardAlert = false

    private var totalCalories: Int { ingredients.reduce(0) { $0 + $1.calories } }
    private var totalMacros: Macros { ingredients.reduce(Macros.zero) { $0 + $1.macros } }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && !ingredients.isEmpty }
    private var hasChanges: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty || !ingredients.isEmpty }

    var body: some View {
        if isEmbedded {
            listContent
        } else {
            NavigationStack { listContent }
        }
    }

    private var listContent: some View {
        List {
            Section("Название") {
                TextField("Борщ, куриная грудка с рисом...", text: $name)
            }

            Section("Состав") {
                ForEach(ingredients) { ingredient in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ingredient.foodName)
                            Text("\(Int(ingredient.grams)) г")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(ingredient.calories) ккал")
                            .foregroundStyle(.secondary)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            if let idx = ingredients.firstIndex(where: { $0.id == ingredient.id }) {
                                ingredients.remove(at: idx)
                            }
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }

                Button {
                    showingIngredientPicker = true
                } label: {
                    Label("Добавить ингредиент", systemImage: "plus")
                }
            }

            if !ingredients.isEmpty {
                Section("Итого") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(verbatim: "\(totalCalories) \(String(localized: "ккал"))")
                                .font(.title3.weight(.semibold))
                            Spacer()
                            Text(verbatim: "\(Int(ingredients.reduce(0) { $0 + $1.grams })) \(String(localized: "г всего"))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        MacroTags(macros: totalMacros)
                        MacroSplitBar(macros: totalMacros)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .glassRow()
        .navigationTitle(editingDish == nil ? "Новое блюдо" : "Редактировать блюдо")
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(!isEmbedded && hasChanges)
        .confirmationDialog("Отменить изменения?", isPresented: $showDiscardAlert, titleVisibility: .visible) {
            Button("Отменить изменения", role: .destructive) { dismiss() }
            Button("Продолжить", role: .cancel) {}
        }
        .toolbar {
            if !isEmbedded {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        if hasChanges { showDiscardAlert = true } else { dismiss() }
                    }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                CheckmarkButton {
                    let trimmed = name.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty, !ingredients.isEmpty else { return }
                    if let dish = editingDish {
                        store.updateDish(dish, name: trimmed, ingredients: ingredients)
                    } else {
                        store.addDish(name: trimmed, ingredients: ingredients)
                    }
                    dismiss()
                }
                .disabled(!canSave)
                .fontWeight(.semibold)
            }
        }
        .sheet(isPresented: $showingIngredientPicker) {
            IngredientPickerSheet(store: store) { ingredient in
                ingredients.append(ingredient)
            }
        }
        .onAppear {
            if let dish = editingDish {
                name = dish.name
                ingredients = dish.ingredients
            }
        }
    }
}

struct IngredientPickerSheet: View {
    var store: CalorieStore
    @Environment(\.dismiss) private var dismiss
    let onAdd: (DishIngredient) -> Void

    @State private var searchText = ""
    @State private var selectedFood: FoodItem? = nil
    @State private var grams: Double = 100
    @State private var gramsText = "100"
    @FocusState private var gramsFocused: Bool

    private var filteredCustomFoods: [FoodItem] {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return store.customFoods }
        return store.customFoods.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var filteredBuiltIn: [FoodItem] {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return FoodDatabase.items }
        return FoodDatabase.items.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            if let food = selectedFood {
                gramsEntryView(for: food)
            } else {
                foodPickerView
            }
        }
    }

    private var foodPickerView: some View {
        List {
            if !filteredCustomFoods.isEmpty {
                Section("Мои продукты") {
                    ForEach(filteredCustomFoods) { food in
                        Button {
                            selectedFood = food
                            grams = 100
                            gramsText = "100"
                        } label: {
                            foodRow(food)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Section("База продуктов") {
                ForEach(filteredBuiltIn) { food in
                    Button {
                        selectedFood = food
                        grams = 100
                        gramsText = "100"
                    } label: {
                        foodRow(food)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .glassRow()
        .searchable(text: $searchText, prompt: "Поиск продукта")
        .navigationTitle("Выбери продукт")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Отмена") { dismiss() }
            }
        }
    }

    private func gramsEntryView(for food: FoodItem) -> some View {
        let cal = Int((Double(food.caloriesPer100g) * grams / 100).rounded())
        let m = food.macrosPer100g.scaled(by: grams)
        return List {
            Section(food.name) {
                HStack {
                    Text("Количество, г")
                    Spacer()
                    TextField("100", text: $gramsText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .focused($gramsFocused)
                        .frame(width: 80)
                        .onChange(of: gramsText) { _, v in
                            if let value = Double(v), value > 0 { grams = min(value, 5000) }
                        }
                }

                Stepper(value: $grams, in: 1...5000, step: 10) {
                    Text("\(Int(grams)) г")
                }
                .onChange(of: grams) { _, v in
                    if !gramsFocused { gramsText = "\(Int(v))" }
                }
            }

            Section("Итого") {
                HStack {
                    Text("\(cal) ккал")
                        .font(.headline)
                    Spacer()
                    Text("Б\(Int(m.protein)) Ж\(Int(m.fat)) У\(Int(m.carbs))")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Граммы")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Назад") { selectedFood = nil }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Добавить") {
                    let ingredient = DishIngredient(
                        foodName: food.name,
                        caloriesPer100g: food.caloriesPer100g,
                        macrosPer100g: food.macrosPer100g,
                        grams: grams
                    )
                    onAdd(ingredient)
                    dismiss()
                }
                .fontWeight(.semibold)
            }
        }
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
