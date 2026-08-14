import SwiftUI

struct AddEntryView: View {
    @ObservedObject var store: CalorieStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedDate: Date
    @State private var searchText = ""

    @State private var draftItems: [MealItem] = []

    @State private var quickCalories = ""

    @State private var manualName = ""
    @State private var manualCalories = ""
    @State private var manualProtein = ""
    @State private var manualFat = ""
    @State private var manualCarbs = ""

    @State private var showingNewFood = false

    private enum Field: Hashable {
        case quickCalories, manualName, manualCalories, manualProtein, manualFat, manualCarbs
    }
    @FocusState private var focusedField: Field?

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

                Section {
                    if draftItems.isEmpty {
                        Text("Пока пусто — добавь продукты ниже, потом сохрани приём пищи разом")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
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
                } header: {
                    Text("Приём пищи")
                }

                if !isToday {
                    Section {
                        HStack {
                            TextField("Ккал", text: $quickCalories)
                                .keyboardType(.numberPad)
                                .font(.title3.weight(.semibold))
                                .focused($focusedField, equals: .quickCalories)
                            Button("Сохранить") {
                                guard let calories = Int(quickCalories) else { return }
                                let items = draftItems + [MealItem(name: "Приём пищи", calories: calories, macros: .zero)]
                                let totalCalories = items.reduce(0) { $0 + $1.calories }
                                let totalMacros = items.reduce(Macros.zero) { $0 + $1.macros }
                                let name = items.count == 1 ? "Приём пищи" : joinedName(items)
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

                Section("Подробнее (название, БЖУ)") {
                    TextField("Название", text: $manualName)
                        .focused($focusedField, equals: .manualName)
                    TextField("Калории", text: $manualCalories)
                        .keyboardType(.numberPad)
                        .focused($focusedField, equals: .manualCalories)
                    HStack {
                        TextField("Белки, г", text: $manualProtein)
                            .keyboardType(.decimalPad)
                            .focused($focusedField, equals: .manualProtein)
                        TextField("Жиры, г", text: $manualFat)
                            .keyboardType(.decimalPad)
                            .focused($focusedField, equals: .manualFat)
                        TextField("Углеводы, г", text: $manualCarbs)
                            .keyboardType(.decimalPad)
                            .focused($focusedField, equals: .manualCarbs)
                    }
                    Button("В приём пищи") {
                        guard let calories = Int(manualCalories) else { return }
                        let name = manualName.trimmingCharacters(in: .whitespaces).isEmpty
                            ? "Продукт"
                            : manualName
                        let macros = Macros(
                            protein: Double(manualProtein.replacingOccurrences(of: ",", with: ".")) ?? 0,
                            fat: Double(manualFat.replacingOccurrences(of: ",", with: ".")) ?? 0,
                            carbs: Double(manualCarbs.replacingOccurrences(of: ",", with: ".")) ?? 0
                        )
                        draftItems.append(MealItem(name: name, calories: calories, macros: macros))
                        manualName = ""
                        manualCalories = ""
                        manualProtein = ""
                        manualFat = ""
                        manualCarbs = ""
                        focusedField = nil
                    }
                    .disabled(Int(manualCalories) == nil)
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
                        store.add(name: mealName, calories: draftTotalCalories, macros: draftTotalMacros, date: entryDate)
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

private struct NewFoodSheet: View {
    @ObservedObject var store: CalorieStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var caloriesPer100g = ""
    @State private var protein = ""
    @State private var fat = ""
    @State private var carbs = ""
    private enum Field: Hashable { case name, calories, protein, fat, carbs }
    @FocusState private var focusedField: Field?

    var body: some View {
        NavigationStack {
            Form {
                Section("Новый продукт (на 100 г)") {
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
            .onAppear { focusedField = .name }
        }
    }
}
