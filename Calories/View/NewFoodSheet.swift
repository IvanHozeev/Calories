import SwiftUI

struct NewFoodSheet: View {
    var store: CalorieStore
    @Environment(\.dismiss) private var dismiss

    var editingFood: FoodItem? = nil

    @State private var name = ""
    @State private var caloriesPer100g = ""
    @State private var protein = ""
    @State private var fat = ""
    @State private var carbs = ""
    @State private var category = FoodCategory.other
    private enum Field: Hashable { case search, name, calories, protein, fat, carbs }
    @FocusState private var focusedField: Field?

    @State private var searchQuery = ""
    @State private var offResults: [FoodItem] = []
    @State private var isSearchingOFF = false

    private var isEditing: Bool { editingFood != nil }

    private func number(_ text: String) -> Double {
        Double(text.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private var draftMacros: Macros {
        Macros(protein: number(protein), fat: number(fat), carbs: number(carbs))
    }

    /// Калорийность, вытекающая из БЖУ. Сверка с введённым числом ловит опечатки
    /// при переносе данных с упаковки — самый частый источник кривых продуктов.
    private var impliedCalories: Int {
        Int((draftMacros.protein * MacroTargets.kcalPerProteinGram
             + draftMacros.fat * MacroTargets.kcalPerFatGram
             + draftMacros.carbs * MacroTargets.kcalPerCarbGram).rounded())
    }

    private var enteredCalories: Int { Int(number(caloriesPer100g)) }

    private var hasMacros: Bool {
        draftMacros.protein > 0 || draftMacros.fat > 0 || draftMacros.carbs > 0
    }

    /// Расхождение больше 15% почти всегда означает ошибку, а не округление.
    private var caloriesMismatch: Bool {
        guard hasMacros, enteredCalories > 0, impliedCalories > 0 else { return false }
        return abs(Double(enteredCalories - impliedCalories)) / Double(impliedCalories) > 0.15
    }

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

                Section {
                    Picker("Категория", selection: $category) {
                        ForEach(FoodCategory.allCases) { item in
                            Label(item.title, systemImage: item.icon).tag(item)
                        }
                    }
                } footer: {
                    Text("По категории потом фильтруется список своих продуктов.")
                }

                if hasMacros {
                    Section {
                        MacroSplitBar(macros: draftMacros)
                            .padding(.vertical, 4)

                        HStack {
                            Text("По БЖУ выходит")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(verbatim: "\(impliedCalories) \(String(localized: "ккал"))")
                                .font(.body.weight(.medium))
                                .foregroundStyle(caloriesMismatch ? .orange : .primary)
                        }

                        if caloriesMismatch {
                            Label("Расходится с введёнными калориями — проверь данные с упаковки.",
                                  systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    } header: {
                        Text("Проверка")
                    }
                }
            }
            .glassRow()
            .task(id: searchQuery) {
                guard !searchQuery.isEmpty else { offResults = []; isSearchingOFF = false; return }
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                isSearchingOFF = true
                offResults = (try? await OpenFoodService.search(query: searchQuery)) ?? []
                isSearchingOFF = false
            }
            // Форма внутри листа по умолчанию не прячет клавиатуру при прокрутке,
            // и свайп вниз упирается в неё вместо того, чтобы её убрать.
            .scrollDismissesKeyboard(.interactively)
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
                            store.updateCustomFood(food, name: name, caloriesPer100g: calories, protein: p, fat: f, carbs: c, category: category)
                        } else {
                            store.addCustomFood(name: name, caloriesPer100g: calories, protein: p, fat: f, carbs: c, category: category)
                        }
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || Int(caloriesPer100g) == nil)
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                if let food = editingFood {
                    category = food.foodCategory
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
