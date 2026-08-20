import SwiftUI
import SwiftData

struct FoodQuantityView: View {
    let food: FoodItem
    let onAdd: (MealItem) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var grams: Double = 100
    @State private var gramsText: String = "100"
    @FocusState private var gramsFocused: Bool

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
                        .foregroundStyle(.green)
                    Text("\(food.caloriesPer100g) ккал / 100 г")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    MacrosRow(macros: macros)
                        .padding(.top, 4)
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

                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                    ForEach([50, 100, 150, 200, 350, 500], id: \.self) { value in
                        Button("\(value) г") {
                            grams = Double(value)
                            gramsText = "\(value)"
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .navigationTitle("Порция")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("В приём пищи") {
                    onAdd(MealItem(name: food.name, calories: calories, macros: macros, grams: grams))
                    dismiss()
                }
                .fontWeight(.semibold)
            }
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
    @Environment(\.dismiss) private var dismiss

    @State private var grams: Double
    @State private var gramsText: String
    @FocusState private var gramsFocused: Bool

    init(dish: Dish, onAdd: @escaping (MealItem) -> Void) {
        self.dish = dish
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

                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                    ForEach([50, 100, 150, 200, 350, 500], id: \.self) { value in
                        Button("\(value) г") {
                            grams = Double(value)
                            gramsText = "\(value)"
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                    }
                }
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
        .navigationTitle("Порция")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("В приём пищи") {
                    onAdd(MealItem(name: dish.name, calories: calories, macros: macros, grams: grams))
                    dismiss()
                }
                .fontWeight(.semibold)
            }
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
