import SwiftUI

struct NewFoodSheet: View {
    var store: CalorieStore
    @Environment(\.dismiss) private var dismiss

    var editingFood: FoodItem? = nil
    /// Открыт как экран внутри навигации, а не как лист. Тогда «Отмена» не нужна:
    /// назад ведёт сама навигация.
    var isEmbedded: Bool = false

    @State private var name = ""
    @State private var caloriesPer100g = ""
    @State private var protein = ""
    @State private var fat = ""
    @State private var carbs = ""
    @State private var category = FoodCategory.other
    /// Пусто — значит обычные 100 г.
    @State private var servingGrams = ""
    @State private var showingQuickAdd = false
    /// Витамины, взятые из каталога, и строка, из которой они взяты.
    @State private var linkedMicronutrients = Micronutrients()
    @State private var linkedCatalogID: Int?
    @State private var linkedSourceName: String?
    private enum Field: Hashable { case search, name, calories, protein, fat, carbs }
    @FocusState private var focusedField: Field?

    @State private var searchQuery = ""
    @State private var offResults: [FoodItem] = []
    @State private var isSearchingOFF = false

    private var isEditing: Bool { editingFood != nil }

    /// Витамины и минералы показываем от источника: у своих продуктов их нет,
    /// у продуктов базы бывают. Вводить их руками негде и незачем.
    private var micronutrients: Micronutrients {
        if !linkedMicronutrients.isEmpty { return linkedMicronutrients }
        return editingFood?.micronutrients ?? Micronutrients()
    }

    /// Подходящие строки каталога — по названию, которое человек уже написал.
    ///
    /// Связывать молча нельзя: «Творог мой» похож на «Творог 5%», но витамины
    /// приедут чужие, и человек об этом не узнает. Поэтому предлагаем, а
    /// подставляем только по нажатию.
    private var micronutrientSuggestions: [CatalogFood] {
        let query = name.trimmingCharacters(in: .whitespaces)
        // Только при создании: в редакторе уже сохранённого продукта эта
        // секция лезет туда, куда зашли поправить одно число.
        guard !isEditing, query.count >= 3, linkedCatalogID == nil, micronutrients.isEmpty else { return [] }
        return FoodCatalog.search(query, limit: 3).filter { !$0.micronutrients.isEmpty }
    }

    private var servingGramsValue: Double {
        Double(servingGrams.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private var servingToSave: Double { servingGramsValue > 0 ? servingGramsValue : 100 }

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

    private var portionCalories: Int {
        Int((number(caloriesPer100g) * servingToSave / 100).rounded())
    }

    /// Микронутриенты различаются на три порядка: B12 в твороге — 0.4 мкг,
    /// калий в шпинате — 558 мг. Один формат на оба даёт либо «0 мкг», либо
    /// «558.0 мг».
    private func formatted(_ amount: Double, _ nutrient: Micronutrient) -> String {
        let digits = amount < 10 ? 1 : 0
        return String(format: "%.\(digits)f \(nutrient.unit)", amount)
    }

    private var hasMacros: Bool {
        draftMacros.protein > 0 || draftMacros.fat > 0 || draftMacros.carbs > 0
    }

    /// Расхождение больше 15% почти всегда означает ошибку, а не округление.
    private var caloriesMismatch: Bool {
        guard hasMacros, enteredCalories > 0, impliedCalories > 0 else { return false }
        return abs(Double(enteredCalories - impliedCalories)) / Double(impliedCalories) > 0.15
    }

    private func macroField(_ title: LocalizedStringKey, text: Binding<String>,
                            unit: LocalizedStringKey, keyboard: UIKeyboardType,
                            field: Field) -> some View {
        HStack {
            TextField(title, text: text)
                .keyboardType(keyboard)
                .focused($focusedField, equals: field)
            Text(unit)
                .foregroundStyle(.secondary)
        }
        // Без этого разделитель начинается от подписи с единицей, а не от края
        // строки: у поля ввода нет своей направляющей, и её берут от текста.
        // На экране это выглядело обрывком линии под «ккал г г г».
        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
    }

    var body: some View {
        if isEmbedded {
            formContent
        } else {
            NavigationStack { formContent }
        }
    }

    /// Порядок секций такой же, как на экране блюда: что это → сколько порция →
    /// из чего состоит → что в итоге выходит → добавить в дневник. Экраны
    /// открываются одним и тем же движением, и читаться должны одинаково.
    private var formContent: some View {
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

                Section("Название") {
                    TextField("Название", text: $name)
                        .focused($focusedField, equals: .name)
                    Picker("Категория", selection: $category) {
                        ForEach(FoodCategory.allCases) { item in
                            Label(item.title, systemImage: item.icon).tag(item)
                        }
                    }
                }

                // Единица стоит подписью справа, а не в подсказке поля: подсказка
                // исчезает на первом же символе, и человек остаётся с четырьмя
                // одинаковыми числами без единиц. У калорий её не было вовсе.
                // Поля и полоска БЖУ — одно и то же, разнесённое по двум карточкам:
                // полоска показывает ровно то, что вводится выше, и проверка на
                // расхождение относится к тем же четырём числам. Сведено вместе,
                // чтобы результат было видно, не отрывая глаз от полей.
                Section("Данные на 100 г") {
                    macroField("Калории", text: $caloriesPer100g, unit: "ккал",
                               keyboard: .numberPad, field: .calories)
                    macroField("Белки", text: $protein, unit: "г",
                               keyboard: .decimalPad, field: .protein)
                    macroField("Жиры", text: $fat, unit: "г",
                               keyboard: .decimalPad, field: .fat)
                    macroField("Углеводы", text: $carbs, unit: "г",
                               keyboard: .decimalPad, field: .carbs)

                    // Полоска рисует ровно те четыре числа, что введены выше,
                    // поэтому стоит сразу за ними.
                    if hasMacros {
                        MacroSplitBar(macros: draftMacros)
                            .padding(.vertical, 4)

                        if caloriesMismatch {
                            Label("По БЖУ выходит другое число калорий — проверь данные с упаковки.",
                                  systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }

                Section {
                    HStack {
                        TextField("100", text: $servingGrams)
                            .keyboardType(.decimalPad)
                        Text("г")
                            .foregroundStyle(.secondary)
                    }
                    .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }

                    // Пересчёт на порцию — здесь, а не в данных на сто грамм:
                    // вводят с упаковки, а едят порцию, и это единственное место,
                    // где порция уже известна.
                    if hasMacros || enteredCalories > 0 {
                        LabeledContent("В порции") {
                            Text(verbatim: "\(portionCalories) \(String(localized: "ккал"))")
                                .font(.body.weight(.medium))
                                .monospacedDigit()
                        }
                        MacroTags(macros: draftMacros.scaled(by: servingToSave))
                    }
                } header: {
                    Text("Порция по умолчанию")
                } footer: {
                    Text("Это значение будет подставляться при добавлении продукта в приём пищи.")
                }

                if !micronutrientSuggestions.isEmpty {
                    Section {
                        ForEach(micronutrientSuggestions) { candidate in
                            Button {
                                linkedMicronutrients = candidate.micronutrients
                                linkedCatalogID = candidate.id
                                linkedSourceName = candidate.localizedName
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(verbatim: candidate.localizedName)
                                        MicroTags(nutrients: candidate.micronutrients.notable(inGrams: 100))
                                    }
                                    Spacer()
                                    Image(systemName: "plus.circle")
                                        .foregroundStyle(.blue)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text("Витамины из базы")
                    } footer: {
                        // Прямо говорим, что именно возьмётся: калории и БЖУ с
                        // упаковки трогать нельзя, они точнее любого справочника.
                        Text("Возьмём только витамины и минералы. Калории и БЖУ останутся твои.")
                    }
                }

                if !micronutrients.isEmpty {
                    Section {
                        ForEach(Micronutrient.allCases) { nutrient in
                            // Ноль показывать нечего: он означает «в продукте
                            // этого нет», и строка с прочерком только удлиняет
                            // список, ничего не сообщая.
                            if let amount = micronutrients[nutrient], amount > 0 {
                                HStack {
                                    Text(nutrient.title)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text(verbatim: formatted(amount * servingToSave / 100, nutrient))
                                        .monospacedDigit()
                                    Text(verbatim: "· \(Int((amount * servingToSave / 100 / nutrient.dailyValue * 100).rounded()))%")
                                        .font(.caption)
                                        .foregroundStyle(nutrient.isCeiling ? .orange : .secondary)
                                        .monospacedDigit()
                                }
                            }
                        }
                        if let linkedSourceName {
                            Button(role: .destructive) {
                                linkedMicronutrients = Micronutrients()
                                linkedCatalogID = nil
                                self.linkedSourceName = nil
                            } label: {
                                Label("Отвязать от базы", systemImage: "link.badge.plus")
                            }
                        }
                    } header: {
                        Text("Витамины и минералы")
                    } footer: {
                        if let linkedSourceName {
                            Text(String(format: String(localized: "Взяты из «%@». Доля суточной нормы в порции."), linkedSourceName))
                        } else {
                            Text("Доля суточной нормы в порции. У натрия это доля потолка, а не цели.")
                        }
                    }
                }

            }
            .glassRow()
            .sheet(isPresented: $showingQuickAdd) {
                QuickAddSheet(
                    store: store,
                    name: name.trimmingCharacters(in: .whitespaces),
                    caloriesPer100g: Int(caloriesPer100g) ?? 0,
                    macrosPer100g: draftMacros,
                    defaultGrams: servingToSave
                )
                .presentationDetents([.medium, .large])
            }
            .task(id: searchQuery) {
                guard !searchQuery.isEmpty else { offResults = []; isSearchingOFF = false; return }
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                isSearchingOFF = true
                offResults = (try? await FoodSearch.search(query: searchQuery)) ?? []
                isSearchingOFF = false
            }
            // Форма внутри листа по умолчанию не прячет клавиатуру при прокрутке,
            // и свайп вниз упирается в неё вместо того, чтобы её убрать.
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(isEditing ? "Редактировать" : "Свой продукт")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isEmbedded {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Отмена") { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    CheckmarkButton {
                        guard let calories = Int(caloriesPer100g),
                              !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        let p = Double(protein.replacingOccurrences(of: ",", with: ".")) ?? 0
                        let f = Double(fat.replacingOccurrences(of: ",", with: ".")) ?? 0
                        let c = Double(carbs.replacingOccurrences(of: ",", with: ".")) ?? 0
                        if let food = editingFood {
                            store.updateCustomFood(food, name: name, caloriesPer100g: calories, protein: p, fat: f, carbs: c, category: category, defaultGrams: servingToSave, micronutrients: micronutrients, catalogID: linkedCatalogID ?? food.catalogID)
                        } else {
                            store.addCustomFood(name: name, caloriesPer100g: calories, protein: p, fat: f, carbs: c, category: category, defaultGrams: servingToSave, micronutrients: micronutrients, catalogID: linkedCatalogID)
                        }
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || Int(caloriesPer100g) == nil)
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                // Продукт базы заполняет поля так же, как свой, — разница только
                // в том, что сохранение заведёт новый, а не изменит старый.
                if let food = editingFood {
                    category = food.foodCategory
                    name = food.name
                    caloriesPer100g = "\(food.caloriesPer100g)"
                    protein = food.protein > 0 ? String(format: "%g", food.protein) : ""
                    fat = food.fat > 0 ? String(format: "%g", food.fat) : ""
                    carbs = food.carbs > 0 ? String(format: "%g", food.carbs) : ""
                    servingGrams = food.defaultGrams > 0 && food.defaultGrams != 100
                        ? String(format: "%g", food.defaultGrams) : ""
                    // На экране-детали фокус не забираем: иначе клавиатура
                    // выскакивает сразу после перехода и закрывает половину экрана.
                    linkedCatalogID = food.catalogID
                    if let id = food.catalogID,
                       let source = FoodCatalog.all.first(where: { $0.id == id }) {
                        linkedSourceName = source.localizedName
                    }
                    if !isEmbedded { focusedField = .name }
                } else {
                    focusedField = .search
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
