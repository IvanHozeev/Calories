import SwiftUI

struct NewDishSheet: View {
    @ObservedObject var store: CalorieStore
    @Environment(\.dismiss) private var dismiss
    var editingDish: Dish? = nil

    @State private var name = ""
    @State private var ingredients: [DishIngredient] = []
    @State private var showingIngredientPicker = false

    private var totalCalories: Int { ingredients.reduce(0) { $0 + $1.calories } }
    private var totalMacros: Macros { ingredients.reduce(Macros.zero) { $0 + $1.macros } }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && !ingredients.isEmpty }

    var body: some View {
        NavigationStack {
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
                    }
                    .onDelete { offsets in
                        ingredients.remove(atOffsets: offsets)
                    }

                    Button {
                        showingIngredientPicker = true
                    } label: {
                        Label("Добавить ингредиент", systemImage: "plus")
                    }
                }

                if !ingredients.isEmpty {
                    Section {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(totalCalories) ккал")
                                    .font(.headline)
                                Text("Б\(Int(totalMacros.protein)) Ж\(Int(totalMacros.fat)) У\(Int(totalMacros.carbs))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(Int(ingredients.reduce(0) { $0 + $1.grams })) г всего")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("Итого")
                    }
                }
            }
            .navigationTitle(editingDish == nil ? "Новое блюдо" : "Редактировать блюдо")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
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
}

struct IngredientPickerSheet: View {
    @ObservedObject var store: CalorieStore
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
