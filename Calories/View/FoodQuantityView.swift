import SwiftUI
import SwiftData

struct FoodQuantityView: View {
    let food: FoodItem
    let onAdd: (MealItem) -> Void
    var onSave: (() -> Void)? = nil
    var onAddAndSave: ((MealItem) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var grams: Double
    @State private var gramsText: String
    @FocusState private var gramsFocused: Bool

    init(food: FoodItem, onSave: (() -> Void)? = nil, onAddAndSave: ((MealItem) -> Void)? = nil, onAdd: @escaping (MealItem) -> Void) {
        self.food = food
        self.onSave = onSave
        self.onAddAndSave = onAddAndSave
        self.onAdd = onAdd
        let g = food.defaultGrams > 0 ? food.defaultGrams : 100
        _grams = State(initialValue: g)
        _gramsText = State(initialValue: "\(Int(g))")
    }

    private var calories: Int {
        Int((Double(food.caloriesPer100g) * grams / 100).rounded())
    }

    private var macros: Macros {
        food.macrosPer100g.scaled(by: grams)
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 12) {
                    Text(food.name)
                        .font(.title3.weight(.semibold))
                    Text("\(calories) ккал")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .foregroundStyle(.green)
                    Text("\(food.caloriesPer100g) ккал / 100 г")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    MacrosRow(macros: macros)
                        .padding(.top, 4)

                    MacroSplitBar(macros: macros)
                        .padding(.top, 8)
                        .padding(.horizontal, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }

            Section("Количество, г") {
                Stepper(value: $grams, in: 5...2000, step: 10) {
                    TextField("Граммы", text: $gramsText)
                        .keyboardType(.numberPad)
                        .focused($gramsFocused)
                        .font(.body.weight(.medium))
                        .onChange(of: gramsText) { _, newValue in
                            if let value = Double(newValue), value > 0 {
                                grams = min(value, 2000)
                            }
                        }
                        .onChange(of: grams) { _, newValue in
                            if !gramsFocused {
                                gramsText = "\(Int(newValue))"
                            }
                        }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach([50, 100, 150, 200, 350, 500], id: \.self) { value in
                            Button("\(value) г") {
                                grams = Double(value)
                                gramsText = "\(value)"
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            }
        }
        .glassRow()
        .navigationTitle("Порция")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Пополнение справочника — редкое действие, поэтому оно иконкой наверху.
            // Внизу под большим пальцем то, ради чего на экран и зашли.
            if let onSave {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onSave()
                        dismiss()
                    } label: {
                        Image(systemName: "bookmark")
                    }
                    .accessibilityLabel("Сохранить в мои продукты")
                    .accessibilityIdentifier("saveToMyFoods")
                }
            }
        }
        // Панель действий своя, а не ToolbarItem: в тулбаре две кнопки склеиваются
        // в одну капсулу без зазора, и широкая накрывает соседнюю.
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 10) {
                Button {
                    onAdd(MealItem(name: food.name, calories: calories, macros: macros, grams: grams))
                    dismiss()
                } label: {
                    // Растягивается подпись внутри кнопки, а не сама кнопка:
                    // иначе её фон занимает всю строку и съедает соседнюю.
                    Text("В приём пищи")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("addToMeal")

                // Второй сценарий: не копить приём пищи, а записать продукт сразу.
                if let onAddAndSave {
                    Button {
                        onAddAndSave(MealItem(name: food.name, calories: calories, macros: macros, grams: grams))
                    } label: {
                        Image(systemName: "checkmark")
                            .fontWeight(.semibold)
                            .frame(width: 24)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(.green)
                    .accessibilityIdentifier("addAndSave")
                    .accessibilityLabel("Добавить и сохранить")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 10)
            .background(.bar)
        }
    }
}

#Preview("FoodQuantityView") {
    NavigationStack {
        FoodQuantityView(
            food: FoodItem(name: "Куриная грудка варёная", caloriesPer100g: 165, protein: 31.0, fat: 3.6, carbs: 0.0)
        ) { _ in }
    }
}

struct DishQuantityView: View {
    let dish: Dish
    let onAdd: (MealItem) -> Void
    var onAddAndSave: ((MealItem) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var grams: Double
    @State private var gramsText: String
    @FocusState private var gramsFocused: Bool

    init(dish: Dish, onAddAndSave: ((MealItem) -> Void)? = nil, onAdd: @escaping (MealItem) -> Void) {
        self.dish = dish
        self.onAddAndSave = onAddAndSave
        self.onAdd = onAdd
        let defaultGrams = dish.totalGrams > 0 ? dish.totalGrams : 100
        _grams = State(initialValue: defaultGrams)
        _gramsText = State(initialValue: "\(Int(defaultGrams))")
    }

    private var calories: Int {
        Int((Double(dish.caloriesPer100g) * grams / 100).rounded())
    }

    private var macros: Macros {
        dish.macrosPer100g.scaled(by: grams)
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 12) {
                    Text(dish.name)
                        .font(.title3.weight(.semibold))
                    Text("\(calories) ккал")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .foregroundStyle(.green)
                    Text("\(dish.caloriesPer100g) ккал / 100 г")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    MacrosRow(macros: macros)
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }

            Section("Количество, г") {
                Stepper(value: $grams, in: 5...5000, step: 10) {
                    TextField("Граммы", text: $gramsText)
                        .keyboardType(.numberPad)
                        .focused($gramsFocused)
                        .font(.body.weight(.medium))
                        .onChange(of: gramsText) { _, newValue in
                            if let value = Double(newValue), value > 0 {
                                grams = min(value, 5000)
                            }
                        }
                        .onChange(of: grams) { _, newValue in
                            if !gramsFocused {
                                gramsText = "\(Int(newValue))"
                            }
                        }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach([50, 100, 150, 200, 350, 500], id: \.self) { value in
                            Button("\(value) г") {
                                grams = Double(value)
                                gramsText = "\(value)"
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            }

            if !dish.ingredients.isEmpty {
                Section("Состав") {
                    ForEach(dish.ingredients) { ingredient in
                        HStack {
                            Text(ingredient.foodName)
                            Spacer()
                            Text("\(Int(ingredient.grams)) г")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .glassRow()
        .navigationTitle("Порция")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 10) {
                Button {
                    onAdd(MealItem(name: dish.name, calories: calories, macros: macros, grams: grams))
                    dismiss()
                } label: {
                    Text("В приём пищи")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("addToMeal")

                if let onAddAndSave {
                    Button {
                        onAddAndSave(MealItem(name: dish.name, calories: calories, macros: macros, grams: grams))
                    } label: {
                        Image(systemName: "checkmark")
                            .fontWeight(.semibold)
                            .frame(width: 24)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(.green)
                    .accessibilityIdentifier("addAndSave")
                    .accessibilityLabel("Добавить и сохранить")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 10)
            .background(.bar)
        }
    }
}

struct FoodDetailView: View {
    let food: FoodItem
    let store: CalorieStore

    @State private var grams: Double
    @State private var gramsText: String
    @State private var showingEdit = false
    @State private var showingQuickAdd = false
    @FocusState private var gramsFocused: Bool

    init(food: FoodItem, store: CalorieStore) {
        self.food = food
        self.store = store
        let g = food.defaultGrams > 0 ? food.defaultGrams : 100
        _grams = State(initialValue: g)
        _gramsText = State(initialValue: "\(Int(g))")
    }

    private var calories: Int {
        Int((Double(food.caloriesPer100g) * grams / 100).rounded())
    }

    private var macros: Macros {
        food.macrosPer100g.scaled(by: grams)
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 12) {
                    Text(food.name)
                        .font(.title3.weight(.semibold))
                    Text("\(calories) ккал")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .foregroundStyle(.green)
                        .contentTransition(.numericText())
                    Text("\(food.caloriesPer100g) ккал / 100 г")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    MacrosRow(macros: macros)
                        .padding(.top, 4)

                    MacroSplitBar(macros: macros)
                        .padding(.top, 8)
                        .padding(.horizontal, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }

            Section {
                Button {
                    showingQuickAdd = true
                } label: {
                    Label("Добавить в дневник", systemImage: "plus.circle.fill")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
            }

            Section {
                HStack {
                    Text("Белки")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.1f \(String(localized: "г / 100 г"))", food.protein))
                }
                HStack {
                    Text("Жиры")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.1f \(String(localized: "г / 100 г"))", food.fat))
                }
                HStack {
                    Text("Углеводы")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.1f \(String(localized: "г / 100 г"))", food.carbs))
                }
            } header: {
                Text("Пищевая ценность")
            }

            Section {
                Stepper(value: $grams, in: 5...2000, step: 5) {
                    TextField("Граммы", text: $gramsText)
                        .keyboardType(.numberPad)
                        .focused($gramsFocused)
                        .font(.body.weight(.medium))
                        .onChange(of: gramsText) { _, newValue in
                            if let value = Double(newValue), value > 0 {
                                grams = min(value, 2000)
                            }
                        }
                        .onChange(of: grams) { _, newValue in
                            if !gramsFocused { gramsText = "\(Int(newValue))" }
                        }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach([50, 100, 150, 200, 350, 500], id: \.self) { value in
                            Button("\(value) г") {
                                grams = Double(value)
                                gramsText = "\(value)"
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            } header: {
                Text("Порция по умолчанию")
            } footer: {
                Text("Это значение будет подставляться при добавлении продукта в приём пищи.")
            }
        }
        .glassRow()
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(food.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingEdit = true } label: {
                        Image(systemName: "pencil")
                    }
                    .tint(.blue)
            }
        }
        .onChange(of: grams) { _, newValue in
            store.setDefaultGrams(food, grams: newValue)
        }
        .sheet(isPresented: $showingEdit) {
            NewFoodSheet(store: store, editingFood: food)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingQuickAdd) {
            QuickAddSheet(
                store: store,
                name: food.name,
                caloriesPer100g: food.caloriesPer100g,
                macrosPer100g: food.macrosPer100g,
                defaultGrams: grams
            )
            .presentationDetents([.medium, .large])
        }
    }
}

#Preview("DishQuantityView") {
    let dish = Dish(name: "Борщ", ingredients: [
        DishIngredient(foodName: "Картофель варёный", caloriesPer100g: 87, macrosPer100g: Macros(protein: 2, fat: 0.1, carbs: 20), grams: 150),
        DishIngredient(foodName: "Говядина", caloriesPer100g: 250, macrosPer100g: Macros(protein: 26, fat: 15, carbs: 0), grams: 100),
        DishIngredient(foodName: "Капуста белокочанная", caloriesPer100g: 25, macrosPer100g: Macros(protein: 1.3, fat: 0.1, carbs: 6), grams: 100),
    ])
    NavigationStack {
        DishQuantityView(dish: dish) { _ in }
    }
}
