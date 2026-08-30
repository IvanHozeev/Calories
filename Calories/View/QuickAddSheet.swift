import SwiftUI

/// Запись продукта или блюда в дневник за два тапа: приём пищи и вес.
/// Раньше со «Своей еды» попасть в дневник было нельзя вовсе — приходилось идти
/// на «Сегодня» и искать то же самое заново.
struct QuickAddSheet: View {
    var store: CalorieStore
    let name: String
    let caloriesPer100g: Int
    let macrosPer100g: Macros
    let defaultGrams: Double

    @Environment(\.dismiss) private var dismiss
    @State private var gramsText: String
    @State private var period: MealPeriod
    @FocusState private var gramsFocused: Bool

    init(store: CalorieStore, name: String, caloriesPer100g: Int, macrosPer100g: Macros, defaultGrams: Double = 100) {
        self.store = store
        self.name = name
        self.caloriesPer100g = caloriesPer100g
        self.macrosPer100g = macrosPer100g
        self.defaultGrams = defaultGrams > 0 ? defaultGrams : 100
        _gramsText = State(initialValue: String(Int(defaultGrams > 0 ? defaultGrams : 100)))
        _period = State(initialValue: MealPeriod.period(for: Date()))
    }

    private var grams: Double? {
        let cleaned = gramsText.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(cleaned), value > 0 else { return nil }
        return value
    }

    private var calories: Int {
        guard let grams else { return 0 }
        return Int((Double(caloriesPer100g) * grams / 100).rounded())
    }

    private var macros: Macros {
        guard let grams else { return .zero }
        return macrosPer100g.scaled(by: grams)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Приём пищи", selection: $period) {
                        ForEach(MealPeriod.allCases, id: \.self) { p in
                            Text(LocalizedStringKey(p.rawValue)).tag(p)
                        }
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text(name)
                }

                Section("Вес") {
                    HStack {
                        TextField("100", text: $gramsText)
                            .keyboardType(.numberPad)
                            .focused($gramsFocused)
                        Text("г")
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        ForEach([50, 100, 150, 200], id: \.self) { preset in
                            Button("\(preset)") { gramsText = "\(preset)" }
                                .buttonStyle(.bordered)
                                .font(.footnote)
                        }
                    }
                }

                Section("Будет записано") {
                    HStack {
                        Text("Калории")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(verbatim: "\(calories) \(String(localized: "ккал"))")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.green)
                    }
                    MacroTags(macros: macros)
                }
            }
            .glassRow()
            // Свайп вниз по списку должен убирать клавиатуру, а не упираться в неё.
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Добавить в дневник")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Добавить") {
                        guard let grams else { return }
                        store.add(
                            name: name,
                            calories: calories,
                            macros: macros,
                            grams: grams,
                            date: period.dateForToday()
                        )
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(grams == nil)
                }
            }
        }
    }
}
