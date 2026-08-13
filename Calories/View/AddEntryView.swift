import SwiftUI

struct AddEntryView: View {
    @ObservedObject var store: CalorieStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedDate: Date
    @State private var searchText = ""

    @State private var quickCalories = ""

    @State private var manualName = ""
    @State private var manualCalories = ""
    @State private var manualProtein = ""
    @State private var manualFat = ""
    @State private var manualCarbs = ""

    @State private var showingNewFood = false

    init(store: CalorieStore, initialDate: Date = Date()) {
        self.store = store
        _selectedDate = State(initialValue: initialDate)
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

                Section {
                    HStack {
                        TextField("Ккал", text: $quickCalories)
                            .keyboardType(.numberPad)
                            .font(.title3.weight(.semibold))
                        Button("Добавить") {
                            guard let calories = Int(quickCalories) else { return }
                            store.add(name: "Приём пищи", calories: calories, date: entryDate)
                            dismiss()
                        }
                        .disabled(Int(quickCalories) == nil)
                        .buttonStyle(.borderedProminent)
                    }
                } header: {
                    Text("Быстро — только калории")
                } footer: {
                    Text("Для восстановления данных за прошлый день: выбери дату выше и впиши сколько всего было съедено.")
                }

                Section("Подробнее (название, БЖУ)") {
                    TextField("Название", text: $manualName)
                    TextField("Калории", text: $manualCalories)
                        .keyboardType(.numberPad)
                    HStack {
                        TextField("Белки, г", text: $manualProtein)
                            .keyboardType(.decimalPad)
                        TextField("Жиры, г", text: $manualFat)
                            .keyboardType(.decimalPad)
                        TextField("Углеводы, г", text: $manualCarbs)
                            .keyboardType(.decimalPad)
                    }
                    Button("Добавить") {
                        guard let calories = Int(manualCalories) else { return }
                        let name = manualName.trimmingCharacters(in: .whitespaces).isEmpty
                            ? "Приём пищи"
                            : manualName
                        let macros = Macros(
                            protein: Double(manualProtein.replacingOccurrences(of: ",", with: ".")) ?? 0,
                            fat: Double(manualFat.replacingOccurrences(of: ",", with: ".")) ?? 0,
                            carbs: Double(manualCarbs.replacingOccurrences(of: ",", with: ".")) ?? 0
                        )
                        store.add(name: name, calories: calories, macros: macros, date: entryDate)
                        dismiss()
                    }
                    .disabled(Int(manualCalories) == nil)
                }

                if !filteredCustomFoods.isEmpty {
                    Section("Мои продукты") {
                        ForEach(filteredCustomFoods) { food in
                            NavigationLink {
                                FoodQuantityView(store: store, food: food, date: entryDate)
                            } label: {
                                foodRow(food)
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    store.deleteCustomFood(food)
                                } label: {
                                    Label("Удалить", systemImage: "trash")
                                }
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
                                FoodQuantityView(store: store, food: food, date: entryDate)
                            } label: {
                                foodRow(food)
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Поиск продукта")
            .navigationTitle("Добавить")
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
            }
            .sheet(isPresented: $showingNewFood) {
                NewFoodSheet(store: store)
                    .presentationDetents([.medium])
            }
        }
    }

    /// День из пикера + текущее время суток — чтобы у записей был осмысленный порядок и время.
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

private struct NewFoodSheet: View {
    @ObservedObject var store: CalorieStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var caloriesPer100g = ""
    @State private var protein = ""
    @State private var fat = ""
    @State private var carbs = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Новый продукт (на 100 г)") {
                    TextField("Название", text: $name)
                        .focused($nameFocused)
                    TextField("Калории", text: $caloriesPer100g)
                        .keyboardType(.numberPad)
                    TextField("Белки, г", text: $protein)
                        .keyboardType(.decimalPad)
                    TextField("Жиры, г", text: $fat)
                        .keyboardType(.decimalPad)
                    TextField("Углеводы, г", text: $carbs)
                        .keyboardType(.decimalPad)
                }
            }
            .navigationTitle("Свой продукт")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        guard let calories = Int(caloriesPer100g),
                              !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        store.addCustomFood(
                            name: name,
                            caloriesPer100g: calories,
                            protein: Double(protein.replacingOccurrences(of: ",", with: ".")) ?? 0,
                            fat: Double(fat.replacingOccurrences(of: ",", with: ".")) ?? 0,
                            carbs: Double(carbs.replacingOccurrences(of: ",", with: ".")) ?? 0
                        )
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || Int(caloriesPer100g) == nil)
                    .fontWeight(.semibold)
                }
            }
            .onAppear { nameFocused = true }
        }
    }
}
