import SwiftUI

struct NewDishSheet: View {
    var store: CalorieStore
    @Environment(\.dismiss) private var dismiss
    var editingDish: Dish? = nil
    var isEmbedded: Bool = false

    @State private var name = ""
    /// Пусто — значит «вся кастрюля»: подставится полный вес блюда.
    @State private var servingGrams = ""

    /// Порция, на которую считаем. Пустое поле означает «вся кастрюля».
    private var portionGrams: Double {
        servingGramsValue > 0 ? servingGramsValue : totalGrams
    }

    private var portionCalories: Int {
        guard totalGrams > 0 else { return 0 }
        return Int((Double(totalCalories) * portionGrams / totalGrams).rounded())
    }

    private var portionMacros: Macros {
        guard totalGrams > 0 else { return .zero }
        return totalMacros.scaled(by: portionGrams / totalGrams * 100)
    }

    private var servingGramsValue: Double {
        Double(servingGrams.replacingOccurrences(of: ",", with: ".")) ?? 0
    }
    @State private var ingredients: [DishIngredient] = []
    /// Ингредиент, которому правят вес. Одно и то же блюдо собирают из разных
    /// количеств, и переклад ингредиента заново ради двадцати грамм — лишняя работа.
    @State private var gramsEditTarget: DishIngredient?
    @State private var gramsEditText = ""
    @State private var showingIngredientPicker = false
    @State private var showDiscardAlert = false
    @State private var showingQuickAdd = false

    private var totalCalories: Int { ingredients.reduce(0) { $0 + $1.calories } }
    private var totalGrams: Double { ingredients.reduce(0) { $0 + $1.grams } }

    /// Блюдо кладётся в дневник как продукт: значения на 100 г и порция по умолчанию —
    /// вес всего блюда, потому что чаще всего съедается оно целиком.
    private var perHundredGrams: (calories: Int, macros: Macros) {
        guard totalGrams > 0 else { return (0, .zero) }
        let factor = 100 / totalGrams
        return (
            Int((Double(totalCalories) * factor).rounded()),
            Macros(protein: totalMacros.protein * factor,
                   fat: totalMacros.fat * factor,
                   carbs: totalMacros.carbs * factor)
        )
    }
    private var totalMacros: Macros { ingredients.reduce(Macros.zero) { $0 + $1.macros } }

    /// Витамины и минералы блюда — из состава его ингредиентов.
    ///
    /// Считается на лету, а не берётся у сохранённого блюда: ингредиенты правят
    /// прямо здесь, и показывать состав, собранный до правки, значит показывать
    /// чужое блюдо.
    private var nutrientProfile: NutrientProfile? {
        DishNutrients.profile(of: ingredients) { store.nutrientProfilesByName[$0]?.per100g }
    }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && !ingredients.isEmpty }
    private var hasChanges: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty || !ingredients.isEmpty }

    var body: some View {
        if isEmbedded {
            listContent
        } else {
            NavigationStack { listContent }
        }
    }

    /// Ноль и мусор игнорируем: пустой вес превратил бы ингредиент в строку
    /// без калорий, а удаление для этого есть отдельным свайпом.
    private func nutrientRow(_ nutrient: Micronutrient, per100g: Double) -> some View {
        let amount = per100g * portionGrams / 100
        let share = amount / nutrient.dailyValue
        return HStack {
            Text(nutrient.title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(verbatim: formatted(amount, nutrient))
                .monospacedDigit()
            Text(verbatim: "· \(Int((share * 100).rounded()))%")
                .font(.caption)
                .foregroundStyle(nutrient.isCeiling ? .orange : .secondary)
                .monospacedDigit()
        }
    }

    /// Микронутриенты различаются на три порядка: B12 — микрограммы, калий —
    /// сотни миллиграмм. Один формат на оба даёт либо «0 мкг», либо «558.0 мг».
    private func formatted(_ amount: Double, _ nutrient: Micronutrient) -> String {
        let digits = amount < 10 ? 1 : 0
        return String(format: "%.\(digits)f \(nutrient.unit)", amount)
    }

    private func applyGrams(to ingredient: DishIngredient) {
        defer { gramsEditTarget = nil }
        let value = Double(gramsEditText.replacingOccurrences(of: ",", with: ".")) ?? 0
        guard value > 0, let idx = ingredients.firstIndex(where: { $0.id == ingredient.id }) else { return }
        ingredients[idx].grams = value
    }

    private var listContent: some View {
        List {
            Section("Название") {
                TextField("Борщ, куриная грудка с рисом...", text: $name)
            }

            // Порция и итог — одно и то же, разнесённое по двум карточкам:
            // число калорий имеет смысл только применительно к порции. Готовят
            // на несколько раз, а едят один, поэтому и считаем на порцию, а не
            // на всю кастрюлю.
            if !ingredients.isEmpty {
                Section {
                    HStack {
                        TextField("Вся кастрюля", text: $servingGrams)
                            .keyboardType(.decimalPad)
                        Text("г")
                            .foregroundStyle(.secondary)
                    }
                    .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(verbatim: "\(portionCalories) \(String(localized: "ккал"))")
                                .font(.title3.weight(.semibold))
                                .contentTransition(.numericText())
                            Spacer()
                            Text(verbatim: "\(Int(totalGrams)) \(String(localized: "г всего"))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        MacroTags(macros: portionMacros)
                        MacroSplitBar(macros: portionMacros)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Размер порции")
                } footer: {
                    Text("Готовят обычно на несколько раз. Укажи привычную порцию — она подставится при добавлении, и числа ниже посчитаны на неё.")
                }
            }

            if let profile = nutrientProfile, !profile.per100g.isEmpty {
                Section {
                    ForEach(Micronutrient.allCases) { nutrient in
                        // Ноль означает «этого здесь нет»: строка с нулём ничего
                        // не сообщает и только удлиняет список.
                        if let per100g = profile.per100g[nutrient], per100g > 0 {
                            nutrientRow(nutrient, per100g: per100g)
                        }
                    }
                } header: {
                    Text("Витамины и минералы")
                } footer: {
                    if profile.coverage < 1 {
                        // Доля названа вслух: недобор, которого нет, оспорить
                        // нечем, если про пробел в составе промолчать.
                        Text(String(format: String(localized: "Посчитано по %d%% массы блюда — у остальных ингредиентов состава нет. Значит это нижняя граница, а не итог."),
                                    Int((profile.coverage * 100).rounded())))
                    } else {
                        Text("Доля суточной нормы в порции. У натрия это доля потолка, а не цели.")
                    }
                }
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
                    .swipeActions(edge: .leading) {
                        Button {
                            gramsEditText = String(format: "%g", ingredient.grams)
                            gramsEditTarget = ingredient
                        } label: {
                            Label("Граммы", systemImage: "scalemass")
                        }
                        .tint(.blue)
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

        }
        .glassRow()
        .alert(
            "Граммы",
            isPresented: Binding(get: { gramsEditTarget != nil },
                                 set: { if !$0 { gramsEditTarget = nil } }),
            presenting: gramsEditTarget
        ) { target in
            TextField("Граммы", text: $gramsEditText)
                .keyboardType(.decimalPad)
            Button("Отмена", role: .cancel) { gramsEditTarget = nil }
            Button("Сохранить") { applyGrams(to: target) }
        } message: { target in
            Text(verbatim: target.foodName)
        }
        .sheet(isPresented: $showingQuickAdd) {
            QuickAddSheet(
                store: store,
                name: name.trimmingCharacters(in: .whitespaces),
                caloriesPer100g: perHundredGrams.calories,
                macrosPer100g: perHundredGrams.macros,
                defaultGrams: totalGrams
            )
            .presentationDetents([.medium, .large])
        }
        // Свайп вниз по списку должен убирать клавиатуру, а не упираться в неё.
        .scrollDismissesKeyboard(.interactively)
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
                        store.updateDish(dish, name: trimmed, ingredients: ingredients, servingGrams: servingGramsValue)
                    } else {
                        store.addDish(name: trimmed, ingredients: ingredients, servingGrams: servingGramsValue)
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
                servingGrams = dish.defaultServingGrams > 0
                    ? String(format: "%g", dish.defaultServingGrams)
                    : ""
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
        return FoodDatabase.search(searchText)
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
        // Свайп вниз по списку должен убирать клавиатуру, а не упираться в неё.
        .scrollDismissesKeyboard(.interactively)
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
