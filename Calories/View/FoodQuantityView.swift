import SwiftUI

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

                HStack {
                    ForEach([100, 150, 200, 500], id: \.self) { value in
                        Button("\(value) г") {
                            grams = Double(value)
                            gramsText = "\(value)"
                        }
                        .buttonStyle(.bordered)
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
