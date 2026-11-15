import SwiftUI
import SwiftData

struct FoodQuantityView: View {
    let food: FoodItem
    let onAdd: (MealItem) -> Void
    var onSave: (() -> Void)? = nil
    var onAddAndSave: ((MealItem) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var savedToMyFoods = false

    @State private var grams: Double
    @State private var gramsText: String
    /// Штуки — у продукта «на штуку», чей вес неизвестен. Числа продукта
    /// введены на одну штуку, и в арифметике она — сто условных единиц.
    @State private var pieces: Double
    @FocusState private var gramsFocused: Bool

    /// Открыт переходом внутри стека, а не листом. Тогда «Отмена» не нужна:
    /// назад ведёт системная стрелка, и две кнопки закрытия спорили бы.
    var isPushed: Bool = false

    /// Подпись основной кнопки. При правке уже добавленного продукта это не
    /// «в приём пищи» — он уже там, — а подтверждение нового веса.
    private let addTitle: LocalizedStringKey

    /// День и набранный приём — чтобы показать, что порция сделает с днём.
    /// nil — не показываем: правят запись за прошлый день или экран открыт
    /// из «Рациона», где «после приёма» нечего сравнивать.
    private let impactBase: MealImpact.Base?

    /// С чего начинали: обычная порция, она же первая из быстрых.
    private let startGrams: Double

    init(food: FoodItem, grams initialGrams: Double? = nil, addTitle: LocalizedStringKey = "В приём пищи",
         onSave: (() -> Void)? = nil, onAddAndSave: ((MealItem) -> Void)? = nil,
         impactBase: MealImpact.Base? = nil,
         isPushed: Bool = false, onAdd: @escaping (MealItem) -> Void) {
        self.isPushed = isPushed
        self.impactBase = impactBase
        self.food = food
        self.addTitle = addTitle
        self.onSave = onSave
        self.onAddAndSave = onAddAndSave
        self.onAdd = onAdd
        let g = initialGrams ?? (food.defaultGrams > 0 ? food.defaultGrams : 100)
        self.startGrams = g
        _grams = State(initialValue: g)
        _gramsText = State(initialValue: "\(Int(g))")
        _pieces = State(initialValue: food.isPerUnit ? max(0.5, (initialGrams ?? 100) / 100) : 1)
    }

    /// Количество в единицах, на которые введены числа продукта: граммы или
    /// штуки, переведённые в сотни.
    private var amount: Double { food.isPerUnit ? pieces * 100 : grams }

    private var calories: Int {
        Int((Double(food.caloriesPer100g) * amount / 100).rounded())
    }

    /// Что положить в приём: у продукта «на штуку» — штуки без граммов.
    private var mealItem: MealItem {
        MealItem(name: food.name, calories: calories, macros: macros,
                 grams: food.isPerUnit ? nil : grams,
                 pieces: food.isPerUnit ? pieces : nil)
    }

    /// Ровно сто граммов: тогда съеденное и цена ста граммов — одно число.
    private var isHundredGrams: Bool { abs(amount - 100) < 0.5 }

    private var macros: Macros {
        food.macrosPer100g.portion(grams: amount)
    }

    var body: some View {
        Form {
            // Количество — первым, а не после карточки продукта.
            //
            // С поднятой цифровой клавиатурой экрану остаётся около трёхсот
            // пятидесяти точек, а число, которое набирают, и быстрые порции под
            // ним важнее всего остального: когда они стояли третьими, нижняя
            // панель «В приём пищи» закрывала их. Результат — калории, БЖУ и
            // «после приёма» — читается под числом, как в калькуляторе.
            if food.isPerUnit {
                // Штуками, а не граммами: вес у такого продукта неизвестен.
                // Половинками — выпил полшейка, съел полбатончика.
                Section {
                    AmountRow(label: PortionLabel.text(grams: nil, pieces: pieces) ?? "",
                              onMinus: { pieces = max(0.5, pieces - 0.5) },
                              onPlus: { pieces = min(20, pieces + 0.5) })
                        .listRowSeparator(.hidden)
                        .accessibilityIdentifier("piecesStepper")
                } header: {
                    Text("Количество, шт").listSectionTitle()
                }
            } else {
                Section {
                    AmountRow(text: $gramsText, focus: $gramsFocused, unit: String(localized: "г"),
                              onMinus: { grams = max(5, grams - 10) },
                              onPlus: { grams = min(2000, grams + 10) })
                        .listRowSeparator(.hidden)
                        .onChange(of: gramsText) { _, newValue in
                            if let value = Double(newValue), value > 0 {
                                grams = min(value, 2000)
                            }
                        }
                        .onChange(of: grams) { _, newValue in
                            // Не по фокусу, а по расхождению: с поднятой клавиатурой
                            // степпер тоже жмут, и строка оставалась со старым числом.
                            // Своё же набранное не перетираем — оно уже совпадает.
                            if Double(gramsText) != newValue {
                                gramsText = "\(Int(newValue))"
                            }
                        }
                    QuickAmounts(options: Self.quickOptions(start: startGrams), current: grams) {
                        grams = $0
                    }
                    .listRowSeparator(.hidden)
                } header: {
                    Text("Количество, г").listSectionTitle()
                }
            }

            // «После этого приёма» — прямо под количеством: граммы выбирают,
            // глядя на это число.
            if let impactBase {
                Section {
                    MealImpactCard(impact: MealImpact(base: impactBase,
                                                      thisCalories: calories, thisMacros: macros))
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            // Карточка сжата по высоте намеренно: с поднятой клавиатурой
            // экрану остаётся около половины, и раньше поле веса уезжало под
            // неё — приходилось ждать автоподскролл, чтобы увидеть, что
            // набираешь. Теперь и поле, и кнопки стоят сразу над клавиатурой.
            Section {
                VStack(spacing: 8) {
                    // Название ушло в заголовок экрана: оно и так стоит
                    // над карточкой, а второй копией забирало строку у чисел.
                    Text("\(calories) ккал")
                        .font(.app(size: 28, weight: .bold))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                    // Цена ста граммов — только когда она отличается от
                    // съеденного: на ста граммах это было то же число дважды.
                    if !isHundredGrams {
                        Text(food.isPerUnit ? "\(food.caloriesPer100g) ккал / шт"
                                            : "\(food.caloriesPer100g) ккал / 100 г")
                            .font(.app(.caption2))
                            .foregroundStyle(.secondary)
                    }

                    MacrosRow(macros: macros)
                        .padding(.top, 2)

                    // Без подписей: названия макросов уже стоят над числами в
                    // строке выше, и вторая копия забирала у экрана высоту, а
                    // с поднятой клавиатурой её и так в обрез.
                    MacroSplitBar(macros: macros, showsLabels: false)
                        .padding(.top, 4)
                        .padding(.horizontal, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }

            // Свойство еды — последним: сначала числа и граммы, которые
            // выбирают, потом вывод из них.
            if !food.traits.isEmpty {
                Section {
                    FoodTraitLines(traits: food.traits)
                }
            }

        }
        .glassRow()
        // Клавиатура над цифровым полем закрывает половину экрана, а кнопки
        // «Готово» у numberPad нет — убрать её можно только смахиванием.
        .scrollDismissesKeyboard(.interactively)
        // Одного scrollDismissesKeyboard мало: он живёт на прокрутке, а здесь
        // содержимое короткое и двигать нечего — смахивание уходило в никуда.
        // Жест ловим сами и не мешаем прокрутке, когда она всё-таки есть.
        .simultaneousGesture(
            DragGesture(minimumDistance: 24).onEnded { drag in
                if drag.translation.height > 40 { gramsFocused = false }
            }
        )
        // Клавиатура сразу: на этот экран приходят ровно за одним — сказать,
        // сколько съел. Ждать ещё одного тапа по полю незачем.
        //
        // Через `task` с задержкой: фокус, поставленный до конца перехода,
        // система гасит вместе с анимацией push, и клавиатура не появляется.
        // Задержка нужна, иначе клавиатура выезжает одновременно с переходом
        // и экран подлагивает.
        .task {
            try? await Task.sleep(for: .milliseconds(250))
            // Штуки выбирают степпером, поля с клавиатурой нет.
            if !food.isPerUnit { gramsFocused = true }
        }
        .navigationTitle(food.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbar {
            // Пополнение справочника — редкое действие, поэтому оно иконкой наверху.
            // Внизу под большим пальцем то, ради чего на экран и зашли.
            if !isPushed {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
            // Пополнение справочника не должно закрывать экран: порцию ещё
            // не выбрали, а ради неё сюда и зашли. Кнопка просто исчезает —
            // сохранять второй раз нечего, и это же служит подтверждением.
            if let onSave, !savedToMyFoods {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onSave()
                        savedToMyFoods = true
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
        //
        // Фона у панели нет: матовая полоса торчала над содержимым отдельной
        // плашкой. Кнопки заметны сами по себе, а safeAreaInset и без неё не даёт
        // содержимому под ними застревать.
        .safeAreaInset(edge: .bottom) {
            // Кнопки во всю ширину и делят её поровну. Раньше они были по
            // размеру подписи и стояли по центру между распорками: одинокое
            // «Готово» при правке висело маленькой плашкой посреди экрана над
            // клавиатурой и не читалось как главное действие.
            HStack(spacing: 10) {
                // Второй сценарий: не копить приём пищи, а записать продукт сразу.
                if let onAddAndSave {
                    Button {
                        onAddAndSave(mealItem)
                    } label: {
                        Text("Сохранить")
                            .frame(maxWidth: .infinity)
                    }
                    // Вторая кнопка серая, главная чёрная: «записать сразу» —
                    // запасное действие, а не то, ради чего пришли.
                    .buttonStyle(.secondaryAction)
                    .accessibilityIdentifier("addAndSave")
                    .accessibilityLabel("Добавить и сохранить")
                }

                Button {
                    // Клавиатуру убираем до ухода: иначе она остаётся поднятой
                    // над вернувшимся списком и накрывает панель «Сохранить».
                    gramsFocused = false
                    // Закрывается экран сам, но через `dismiss` только когда
                    // открыт листом. В стеке за это отвечает тот, кто его
                    // открыл: со строкой поиска в нижнем тулбаре `dismiss`
                    // отсюда уносил весь лист приёма пищи, а не одну порцию.
                    onAdd(mealItem)
                    if !isPushed { dismiss() }
                } label: {
                    Text(addTitle)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.mainAction)
                .accessibilityIdentifier("addToMeal")
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 10)
        }
    }

    /// Быстрые порции: с чего начали (обычная), затем сто, сто пятьдесят и
    /// двести пятьдесят — без повторов, не больше четырёх.
    static func quickOptions(start: Double) -> [Double] {
        var options: [Double] = [start.rounded()]
        for candidate in [100.0, 150, 250, 200, 50] where !options.contains(candidate) {
            options.append(candidate)
            if options.count == 4 { break }
        }
        return options
    }
}

/// Количество: крупное число между «−» и «+».
///
/// Раньше это был системный степпер с мелким полем в строке. Число, ради
/// которого на экран и заходят, стоило набрано кеглем текста; теперь оно
/// главное на экране, а «−» и «+» — под большим пальцем по краям. Поле, как
/// и раньше, редактируется с клавиатуры.
private struct AmountRow: View {
    var text: Binding<String>? = nil
    var focus: FocusState<Bool>.Binding? = nil
    /// Готовая подпись вместо поля — для штук, где поля с клавиатурой нет.
    var label: String? = nil
    var unit: String = ""
    var onMinus: () -> Void
    var onPlus: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            stepButton("minus", label: String(localized: "Меньше"), action: onMinus)
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let text, let focus {
                    TextField("Граммы", text: text)
                        .keyboardType(.numberPad)
                        .focused(focus)
                        .font(.app(size: 34, weight: .bold))
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .fixedSize()
                    Text(verbatim: unit)
                        .font(.app(.body))
                        .foregroundStyle(.secondary)
                } else if let label {
                    Text(verbatim: label)
                        .font(.app(size: 34, weight: .bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
            }
            Spacer(minLength: 0)
            stepButton("plus", label: String(localized: "Больше"), action: onPlus)
        }
        .padding(.vertical, 4)
    }

    private func stepButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.app(size: 18, weight: .bold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 48, height: 48)
                .background(Color.secondary.opacity(0.16), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: label))
    }
}

/// Быстрые порции под числом: нажал — граммы подставились.
private struct QuickAmounts: View {
    let options: [Double]
    let current: Double
    let pick: (Double) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(options, id: \.self) { value in
                let selected = abs(current - value) < 0.5
                Button {
                    pick(value)
                } label: {
                    Text(verbatim: "\(Int(value)) \(String(localized: "г"))")
                        .font(.app(.subheadline, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(selected ? Color(.systemBackground) : Color.primary)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(selected ? Color.primary : Color.secondary.opacity(0.16),
                                    in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
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
    var onAddAndSave: ((MealItem) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var grams: Double
    @State private var gramsText: String
    @FocusState private var gramsFocused: Bool

    var isPushed: Bool = false


    /// Подпись основной кнопки: из приёма пищи блюдо кладут в него, а из
    /// поиска — сразу в дневник.
    private let addTitle: LocalizedStringKey

    /// День и набранный приём — как у продукта.
    private let impactBase: MealImpact.Base?

    init(dish: Dish, addTitle: LocalizedStringKey = "В приём пищи",
         onAddAndSave: ((MealItem) -> Void)? = nil,
         remainingGrams: Double? = nil,
         impactBase: MealImpact.Base? = nil,
         isPushed: Bool = false, onAdd: @escaping (MealItem) -> Void) {
        self.isPushed = isPushed
        self.impactBase = impactBase
        self.dish = dish
        self.addTitle = addTitle
        self.onAddAndSave = onAddAndSave
        self.remainingGrams = remainingGrams
        self.onAdd = onAdd
        // Предлагаем то, что действительно есть.
        //
        // В кастрюле осталось двести грамм, а порция по умолчанию четыреста —
        // подставлять четыреста значит предлагать съесть то, чего нет, и
        // заставлять человека вычитать самому. Если остатка меньше порции,
        // берём остаток: доесть то, что есть, — обычный конец партии.
        let defaultGrams: Double
        if let remainingGrams, remainingGrams > 0, remainingGrams < dish.servingGrams {
            defaultGrams = remainingGrams
        } else {
            defaultGrams = dish.servingGrams
        }
        _grams = State(initialValue: defaultGrams)
        _gramsText = State(initialValue: "\(Int(defaultGrams))")
    }

    /// Сколько этого блюда ещё осталось в партии. nil — партии нет.
    private let remainingGrams: Double?

    private var calories: Int {
        Int((Double(dish.caloriesPer100g) * grams / 100).rounded())
    }

    /// Ровно сто граммов: тогда съеденное и цена ста граммов — одно число.
    private var isHundredGrams: Bool { abs(grams - 100) < 0.5 }

    private var macros: Macros {
        dish.macrosPer100g.portion(grams: grams)
    }

    var body: some View {
        Form {
            // Количество — первым: см. FoodQuantityView.
            Section {
                AmountRow(text: $gramsText, focus: $gramsFocused, unit: String(localized: "г"),
                          onMinus: { grams = max(5, grams - 10) },
                          onPlus: { grams = min(5000, grams + 10) })
                    .listRowSeparator(.hidden)
                    .onChange(of: gramsText) { _, newValue in
                        if let value = Double(newValue), value > 0 {
                            grams = min(value, 5000)
                        }
                    }
                    .onChange(of: grams) { _, newValue in
                        // Не по фокусу, а по расхождению: с поднятой клавиатурой
                        // степпер тоже жмут, и строка оставалась со старым числом.
                        // Своё же набранное не перетираем — оно уже совпадает.
                        if Double(gramsText) != newValue {
                            gramsText = "\(Int(newValue))"
                        }
                    }
                QuickAmounts(options: FoodQuantityView.quickOptions(start: dish.servingGrams),
                             current: grams) { grams = $0 }
                    .listRowSeparator(.hidden)
            } header: {
                Text("Количество, г").listSectionTitle()
            }

            if let impactBase {
                Section {
                    MealImpactCard(impact: MealImpact(base: impactBase,
                                                      thisCalories: calories, thisMacros: macros))
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            Section {
                VStack(spacing: 8) {
                    // Название — в заголовке экрана, как и у продукта.
                    Text("\(calories) ккал")
                        .font(.app(size: 28, weight: .bold))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                    if !isHundredGrams {
                        Text("\(dish.caloriesPer100g) ккал / 100 г")
                            .font(.app(.caption))
                            .foregroundStyle(.secondary)
                    }

                    MacrosRow(macros: macros)
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }

            // Свойство — под количеством, как у продукта.
            if !dish.traits.isEmpty {
                Section {
                    FoodTraitLines(traits: dish.traits)
                }
            }


            if !dish.ingredients.isEmpty {
                Section("Состав") {
                    ForEach(dish.ingredients) { ingredient in
                        HStack {
                            Text(ingredient.foodName)
                                .font(.app(.body, weight: .semibold))
                            Spacer()
                            Text("\(Int(ingredient.grams)) г")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .glassRow()
        // Клавиатура над цифровым полем закрывает половину экрана, а кнопки
        // «Готово» у numberPad нет — убрать её можно только смахиванием.
        .scrollDismissesKeyboard(.interactively)
        // Одного scrollDismissesKeyboard мало: он живёт на прокрутке, а здесь
        // содержимое короткое и двигать нечего — смахивание уходило в никуда.
        // Жест ловим сами и не мешаем прокрутке, когда она всё-таки есть.
        .simultaneousGesture(
            DragGesture(minimumDistance: 24).onEnded { drag in
                if drag.translation.height > 40 { gramsFocused = false }
            }
        )
        // Клавиатура сразу: на этот экран приходят ровно за одним — сказать,
        // сколько съел. Ждать ещё одного тапа по полю незачем.
        //
        // Через `task` с задержкой: фокус, поставленный до конца перехода,
        // система гасит вместе с анимацией push, и клавиатура не появляется.
        // Задержка нужна, иначе клавиатура выезжает одновременно с переходом
        // и экран подлагивает.
        .task {
            try? await Task.sleep(for: .milliseconds(250))
            gramsFocused = true
        }
        .navigationTitle(dish.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbar {
            if !isPushed {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 10) {
                if let onAddAndSave {
                    Button {
                        onAddAndSave(MealItem(name: dish.name, calories: calories, macros: macros, grams: grams))
                    } label: {
                        Text("Сохранить")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.secondaryAction)
                    .accessibilityIdentifier("addAndSave")
                    .accessibilityLabel("Добавить и сохранить")
                }

                Button {
                    gramsFocused = false
                    onAdd(MealItem(name: dish.name, calories: calories, macros: macros, grams: grams))
                    if !isPushed { dismiss() }
                } label: {
                    Text(addTitle)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.mainAction)
                .accessibilityIdentifier("addToMeal")
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 10)
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
