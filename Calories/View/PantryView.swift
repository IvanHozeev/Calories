import SwiftUI

struct PantryView: View {
    var store: CalorieStore

    @State private var showingNewFood = false
    @State private var showingNewDish = false
    @State private var showingScanner = false
    /// Свои продукты первыми: блюд у человека единицы, а продуктов десятки, и
    /// заходят сюда чаще всего за ними.
    @State private var tab: Tab = .products
    @State private var query = ""
    /// nil — показывать все категории.
    @State private var categoryFilter: FoodCategory?
    /// nil — любые. Чем богата еда: отбор по доминирующему макросу или, для
    /// клетчатки, по содержанию.
    @State private var richFilter: Rich?
    @State private var debouncedQuery = ""
    @State private var remoteResults: [FoodItem] = []
    @State private var isSearchingRemote = false
    /// Секции в том порядке, в каком они на экране: по нему имя держится всю
    /// длину категории, даже когда её заголовок давно уехал.
    private var sectionOrder: [String] {
        let source = trimmedQuery.isEmpty && tab == .products ? products : database
        return FoodCategory.grouped(source).map(\.0.title)
    }

    /// Переезд заголовка секции в шапку. Объектом, а не состоянием экрана:
    /// прокрутка меняет его на каждом кадре, и `@State` перестраивал бы весь
    /// список.
    @State private var head = SectionHeadState()
    /// Линия, на которой приклеенный заголовок встаёт: безопасная зона
    /// экрана. Меряем, а не задаём числом — у каждого экрана она своя.
    @State private var pinLine: CGFloat = 0
    @State private var serving: ServingTarget?
    /// Что показывать. Считается не в теле, а по изменению запроса, раздела
    /// и категории — иначе ввод в строку поиска перебирает базу на каждую букву.
    @State private var dishes: [Dish] = []
    @State private var products: [FoodItem] = []
    @State private var database: [FoodItem] = []

    /// Фильтр «богато»: белки, жиры, углеводы, клетчатка.
    ///
    /// Макрос — тот, на который приходится больше всего калорий продукта
    /// (по нему же красится название в строке); клетчатка — от трёх граммов
    /// на сто: меньше уже не «богато».
    enum Rich: String, CaseIterable, Identifiable {
        case protein, fat, carbs, fiber
        var id: String { rawValue }

        static let fiberGramsPer100 = 3.0

        var title: String {
            switch self {
            case .protein: return String(localized: "Белки")
            case .fat:     return String(localized: "Жиры")
            case .carbs:   return String(localized: "Углеводы")
            case .fiber:   return String(localized: "Клетчатка")
            }
        }

        func matches(_ food: FoodItem) -> Bool {
            switch self {
            case .protein: return food.macrosPer100g.leadingKind == .protein
            case .fat:     return food.macrosPer100g.leadingKind == .fat
            case .carbs:   return food.macrosPer100g.leadingKind == .carbs
            case .fiber:   return (food.micronutrients[.fiber] ?? 0) >= Self.fiberGramsPer100
            }
        }
    }

    enum Tab: String, CaseIterable, Identifiable {
        case dishes, products, database
        var id: String { rawValue }

        /// Значок раздела — он же значок кнопки в тулбаре, когда раздел выбран.
        var icon: String {
            switch self {
            case .dishes:   return "frying.pan"
            // Корзина, а не человечек: человечек читается как профиль, а это
            // не «я», это моя еда.
            case .products: return "basket"
            case .database: return "books.vertical"
            }
        }
    }

    /// Что записываем в дневник прямо отсюда — продукт или блюдо.
    ///
    /// Открывается тот же экран порции, что и в листе добавления еды. Раньше
    /// здесь был свой лист «Добавить в дневник» с выбором приёма пищи и полем
    /// веса — второй, непохожий способ сделать то же самое.
    enum ServingTarget: Identifiable {
        case food(FoodItem)
        case dish(Dish)

        var id: String {
            switch self {
            case .food(let food): return "food-\(food.id.uuidString)"
            case .dish(let dish): return "dish-\(dish.id.uuidString)"
            }
        }
    }

    /// Есть ли что показать из внешней базы — или она ещё ищет.
    /// Пока так, «Ничего не найдено» над её результатами было бы враньём.
    private var remoteHasOrMayHaveResults: Bool {
        !trimmedQuery.isEmpty && (isSearchingRemote || !remoteResults.isEmpty)
    }

    private var trimmedQuery: String {
        debouncedQuery.trimmingCharacters(in: .whitespaces)
    }

    private var filteredDishes: [Dish] {
        guard !trimmedQuery.isEmpty else { return store.dishes }
        return store.dishes.filter { $0.name.localizedCaseInsensitiveContains(trimmedQuery) }
    }

    private var filteredProducts: [FoodItem] {
        var items = store.customFoods
        if let categoryFilter {
            items = items.filter { $0.foodCategory == categoryFilter }
        }
        if let richFilter {
            items = items.filter(richFilter.matches)
        }
        guard !trimmedQuery.isEmpty else { return items }
        return items.filter { $0.matches(trimmedQuery) }
    }

    /// Встроенная база. Она тут не для полноты: свой продукт заводят как раз
    /// глядя на похожий из базы, и ради этого раньше приходилось уходить в
    /// лист добавления еды.
    private var filteredDatabase: [FoodItem] {
        // Сначала поиск, потом категория: поиск уже отдаёт результаты по
        // убыванию уместности, и фильтр по категории этот порядок сохраняет.
        var items = trimmedQuery.isEmpty
            ? FoodDatabase.items
            : FoodDatabase.search(trimmedQuery, limit: 200)
        if let categoryFilter {
            items = items.filter { $0.foodCategory == categoryFilter }
        }
        if let richFilter {
            items = items.filter(richFilter.matches)
        }
        return items
    }

    /// Категории берём из того раздела, который открыт: фильтровать базу по
    /// категориям своих продуктов бессмысленно, и наоборот.
    private var usedCategories: [FoodCategory] {
        let source = tab == .database ? FoodDatabase.items : store.customFoods
        let used = Set(source.map(\.foodCategory))
        return FoodCategory.allCases.filter { used.contains($0) }
    }

    var body: some View {
        // Готовые отборы, а не пересчёт в теле: пока набирают запрос, тело
        // перерисовывается на каждую букву, и проход по всей базе с
        // локале-зависимым сравнением на каждом нажатии подвешивал ввод.
        // Пересчёт идёт по отложенному запросу — ниже, в onChange.
        List {
            // Раздел — полосой сегментов под поиском, как в макете. Раньше он
            // прятался в меню тулбара «потому что переключают редко», но
            // меню не говорило, в каком разделе человек, пока его не
            // откроешь. Полоса показывает это сразу. При поиске её нет: он
            // идёт по всем разделам разом.
            if trimmedQuery.isEmpty {
                Section {
                    Picker("Раздел", selection: $tab) {
                        Text("Рецепты").tag(Tab.dishes)
                        Text("Продукты").tag(Tab.products)
                        Text("База").tag(Tab.database)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("sectionFilter")
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }
            }

            // Недавнее показываем только на нетронутом экране: когда человек
            // уже ищет или отфильтровал категорию, он знает, что ему нужно, и
            // повторный список сверху только мешает.
            // Сваренное — первым в «Рецептах»: что стоит в холодильнике и
            // сколько ему осталось, важнее списка рецептов вообще.
            if trimmedQuery.isEmpty, categoryFilter == nil, richFilter == nil, tab == .dishes {
                fridgeSection
            }

            if trimmedQuery.isEmpty, categoryFilter == nil, richFilter == nil {
                recentSection
            }

            // Пока ищут — ищем везде, а не в выбранном разделе.
            //
            // Раздел выбирают, чтобы листать: «мои продукты», «мои блюда»,
            // «база». Но ищущий не знает, в каком из них лежит нужное, —
            // и на «моих продуктах» запрос к базе не находил ничего,
            // хотя продукт там есть. Раздел остаётся про листание, поиск
            // идёт по всему сразу; пустые разделы молчат.
            if trimmedQuery.isEmpty {
                switch tab {
                case .dishes: dishesSection(dishes)
                case .products: productsSection(products)
                case .database: databaseSection(database)
                }
            } else {
                if !products.isEmpty { productsSection(products) }
                if !dishes.isEmpty { dishesSection(dishes) }
                if !database.isEmpty { databaseSection(database) }
                if products.isEmpty, dishes.isEmpty, database.isEmpty, remoteResults.isEmpty, !isSearchingRemote {
                    Section {
                        Text("Ничего не нашлось ни в своих продуктах, ни в рецептах, ни в базе.")
                            .foregroundStyle(.secondary)
                            .font(.app(.callout))
                    }
                }
                remoteSection
            }
        }
        .glassRow()
        .measuresPinLine()
        .onPreferenceChange(PinLineKey.self) { pinLine = $0; head.update(pinLine: $0) }
        .onPreferenceChange(SectionHeadKey.self) { heads in
            head.update(heads: heads, order: sectionOrder, pinLine: pinLine)
        }
        // Заголовок тот же, что на «Сегодня» и «Профиле»: один кегль, одно
        // место. Своя пара имён в центре шапки выглядела чужой — другой
        // размер, другое место, другая анимация. Меняется только текст: имя
        // экрана или имя категории, до которой доехали.
        .tabTitle(head.current ?? String(localized: "Рацион"), trailingRoom: 176, rising: head.rising)
        // На корневых вкладках заголовок скрыт: крупный спорил с содержимым,
        // а название и так в таббаре.
        .scrollIndicators(.hidden)
        .searchable(text: $query, prompt: Text("Поиск еды"))
        // Клавиатура уходит протягиванием списка вниз, как в остальных списках.
        .scrollDismissesKeyboard(.interactively)
        .onAppear(perform: recomputeLists)
        .onChange(of: debouncedQuery) { _, _ in recomputeLists() }
        .onChange(of: categoryFilter) { _, _ in recomputeLists() }
        .onChange(of: richFilter) { _, _ in recomputeLists() }
        .onChange(of: tab) { _, _ in recomputeLists() }
        .onChange(of: store.customFoods.count) { _, _ in recomputeLists() }
        .onChange(of: store.dishes.count) { _, _ in recomputeLists() }
        .task(id: query) {
            // Свои списки фильтруются мгновенно, а сеть дёргаем только после паузы.
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            debouncedQuery = query

            let text = query.trimmingCharacters(in: .whitespaces)
            guard text.count >= 3 else { remoteResults = []; isSearchingRemote = false; return }
            isSearchingRemote = true
            defer { isSearchingRemote = false }
            remoteResults = (try? await FoodSearch.search(query: text)) ?? []
        }
        .toolbar {
            // Порядок — как в макете: сканер, плюс. Штрихкод вынут из меню:
            // он избавляет от ручного ввода и нужен чаще, чем «новый
            // продукт», так что прятать его под плюсом не за что.
            // Фильтр по категории — слева от них: им пользуются реже.
            //
            // Фильтр — меню, а не полоса чипов: категорий девять, полосой
            // они не помещаются и превращаются в горизонтальную прокрутку,
            // где выбранная категория уезжает из виду.
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    // Без значков: список категорий со значками читался
                    // лесенкой картинок, а названия и так говорят всё.
                    Picker("Категория", selection: $categoryFilter) {
                        Text("Все категории").tag(FoodCategory?.none)
                        ForEach(usedCategories) { item in
                            Text(verbatim: item.title).tag(FoodCategory?.some(item))
                        }
                    }
                    Picker("Богато", selection: $richFilter) {
                        Text("Любые").tag(Rich?.none)
                        ForEach(Rich.allCases) { item in
                            Text(verbatim: item.title).tag(Rich?.some(item))
                        }
                    }
                } label: {
                    Image(systemName: categoryFilter == nil && richFilter == nil
                          ? "line.3.horizontal.decrease.circle"
                          : "line.3.horizontal.decrease.circle.fill")
                }
                .accessibilityIdentifier("categoryFilter")
                .accessibilityLabel("Категория")
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button { showingScanner = true } label: {
                    Image(systemName: "barcode.viewfinder")
                }
                .accessibilityLabel("Сканировать штрихкод")
                .accessibilityIdentifier("scanBarcodeButton")
            }

            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showingNewFood = true } label: {
                        Label("Новый продукт", systemImage: "plus")
                    }
                    Button { showingNewDish = true } label: {
                        Label("Новый рецепт", systemImage: "fork.knife")
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Добавить")
                .accessibilityIdentifier("addMenu")
            }
        }
        .sheet(isPresented: $showingNewFood) {
            NewFoodSheet(store: store)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingNewDish) {
            NewDishSheet(store: store)
                // Половина экрана и целый: рецепт начинают с названия и
                // одного продукта, а дособирают из десятка — и на середине
                // список состава упирается в край листа. Вторая высота
                // даёт дотянуть его до конца, не закрывая и не открывая
                // заново.
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingScanner) {
            BarcodeScannerSheet(store: store) { item in
                record(item)
            }
            .presentationDetents([.medium])
        }
        .sheet(item: $serving) { target in
            NavigationStack {
                switch target {
                case .food(let food):
                    FoodQuantityView(
                        food: food,
                        onSave: store.isInMyFoods(food) ? nil : { store.saveToMyFoods(food) }
                    ) { item in
                        record(item)
                    }
                case .dish(let dish):
                    DishQuantityView(dish: dish,
                                     remainingGrams: store.batchState(of: dish)?.remainingGrams) { item in
                        record(item)
                    }
                }
            }
        }
    }

    // MARK: - Блюда

    /// Недавно заведённое и поправленное — сверху, до общего списка.
    ///
    /// Продукт заводят ровно тогда, когда собираются им пользоваться, а в
    /// списке по категориям он лежит вперемешку с теми, что завели полгода
    /// назад, и его приходится искать глазами сразу после создания.
    /// Блюда с остатком, старшие по суткам — выше: их доедать в первую очередь.
    private var fridge: [(dish: Dish, state: DishBatch.State)] {
        store.dishes
            .compactMap { dish in
                store.batchState(of: dish).flatMap { $0.isFinished ? nil : (dish: dish, state: $0) }
            }
            .sorted { $0.state.dayNumber() > $1.state.dayNumber() }
    }

    @ViewBuilder
    private var fridgeSection: some View {
        let batches = fridge
        if !batches.isEmpty {
            Section {
                ForEach(batches, id: \.dish.id) { batch in
                    NavigationLink {
                        NewDishSheet(store: store, editingDish: batch.dish, isEmbedded: true)
                    } label: {
                        FridgeBatchRow(dish: batch.dish, state: batch.state) {
                            serving = .dish(batch.dish)
                        }
                    }
                }
            } header: {
                Text("В холодильнике").listSectionTitle()
            }
        }
    }

    @ViewBuilder
    private var recentSection: some View {
        switch tab {
        case .dishes:
            // В «Рецептах» недавнего нет: «Все рецепты» — короткий список, и
            // повторять его первые три строки сверху значило показывать одно
            // и то же дважды.
            EmptyView()
        case .products:
            let recent = store.customFoods
                .filter { $0.updatedAt != nil }
                .sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
                .prefix(3)
            if recent.count > 1 {
                Section {
                    ForEach(recent) { food in
                        NavigationLink {
                            NewFoodSheet(store: store, editingFood: food, isEmbedded: true)
                        } label: {
                            foodRow(food)
                        }
                    }
                } header: {
                    Text("Недавнее").listSectionTitle()
                }
            }
        case .database:
            EmptyView()
        }
    }

    /// Остаток партии строкой блюда — или nil, когда партии нет.
    private func batchDetail(_ dish: Dish) -> String? {
        guard let state = store.batchState(of: dish), !state.isFinished else { return nil }
        if let servings = state.remainingServings, servings >= 0.5 {
            return PortionCount.left(servings)
        }
        return String(format: String(localized: "осталось %.0f г"), state.remainingGrams)
    }

    @ViewBuilder
    private func dishesSection(_ filteredDishes: [Dish]) -> some View {
        if filteredDishes.isEmpty {
            if trimmedQuery.isEmpty || !remoteHasOrMayHaveResults {
            Section {
                Text(trimmedQuery.isEmpty ? "Пока нет своих рецептов" : "Ничего не найдено")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            }
        } else {
            Section {
                ForEach(filteredDishes) { dish in
                    NavigationLink {
                        NewDishSheet(store: store, editingDish: dish, isEmbedded: true)
                    } label: {
                        DishRow(dish: dish)
                    }
                    .swipeActions(edge: .leading) {
                        recordButton { serving = .dish(dish) }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            store.deleteDish(dish)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("Удалить")
                    }
                }
            } header: {
                // Без поиска — «Все рецепты», как в макете; при поиске блюда
                // идут среди продуктов и базы, и заголовок у них свой.
                Text(trimmedQuery.isEmpty ? "Все рецепты" : "Рецепты").listSectionTitle()
            }
        }
    }

    // MARK: - Продукты

    /// База разложена по категориям, как и в листе добавления еды: одним
    /// списком из шести десятков строк она не читается.
    @ViewBuilder
    private func databaseSection(_ filteredDatabase: [FoodItem]) -> some View {
        if filteredDatabase.isEmpty {
            if !remoteHasOrMayHaveResults {
                Section {
                    Text("Ничего не найдено")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            ForEach(FoodCategory.grouped(filteredDatabase), id: \.0) { category, foods in
                Section {
                    ForEach(foods) { food in
                        // Строку каталога изменить нельзя — она лежит файлом в
                        // бандле, — поэтому экран только показывает. Структура
                        // у него та же, что у своего продукта.
                        NavigationLink {
                            CatalogFoodView(food: food, store: store)
                        } label: {
                            foodRow(food)
                        }
                        .swipeActions(edge: .leading) {
                            recordButton { serving = .food(food) }
                            saveToMyFoodsButton(food)
                        }
                    }
                } header: {
                    Text(verbatim: category.title)
                        // Гаснет, уезжая в шапку: имя не должно стоять в двух
                        // местах разом.
                        .tracksSectionHead(category.title)
                }
            }
        }
    }

    /// Порядок берём из самого перечисления — он осмысленный (мясо, рыба,
    /// молочное...), в отличие от алфавитного.
    @ViewBuilder
    private func productsSection(_ filteredProducts: [FoodItem]) -> some View {
        if filteredProducts.isEmpty {
            if trimmedQuery.isEmpty || !remoteHasOrMayHaveResults {
            Section {
                Text(trimmedQuery.isEmpty ? "Пока нет своих продуктов" : "Ничего не найдено")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            }
        } else {
            // Свои продукты разложены так же, как база: список копится и без
            // заголовков читается ничуть не лучше встроенного.
            ForEach(FoodCategory.grouped(filteredProducts), id: \.0) { category, foods in
                Section {
                    ForEach(foods) { food in
                        // Свой продукт открывается сразу редактируемым — как блюдо.
                        // Отдельная кнопка-карандаш на экране-детали была лишним
                        // шагом ровно там, куда и заходят, чтобы что-то поправить.
                        NavigationLink {
                            NewFoodSheet(store: store, editingFood: food, isEmbedded: true)
                        } label: {
                            foodRow(food)
                        }
                        .swipeActions(edge: .leading) {
                            recordButton { serving = .food(food) }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                store.deleteCustomFood(food)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .accessibilityLabel("Удалить")
                        }
                    }
                } header: {
                    Text(verbatim: category.title)
                        // Гаснет, уезжая в шапку: имя не должно стоять в двух
                        // местах разом.
                        .tracksSectionHead(category.title)
                }
            }
        }
    }

    // MARK: - Внешняя база

    @ViewBuilder
    private var remoteSection: some View {
        if isSearchingRemote || !remoteResults.isEmpty {
            Section {
                if isSearchingRemote && remoteResults.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Ищем…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    // Строка как в базе: тап открывает тот же экран продукта,
                    // свайп — записать или положить в свои. Отдельный синий плюс
                    // в строке был единственной такой кнопкой во всём приложении.
                    ForEach(remoteResults) { food in
                        NavigationLink {
                            CatalogFoodView(food: food, store: store)
                        } label: {
                            foodRow(food)
                        }
                        .swipeActions(edge: .leading) {
                            recordButton { serving = .food(food) }
                            saveToMyFoodsButton(food)
                        }
                    }
                }
            } header: {
                Text("Открытая база продуктов").listSectionTitle()
            }
        }
    }

    // MARK: - Общее

    private func foodRow(_ food: FoodItem) -> some View {
        let grams = food.defaultGrams > 0 ? food.defaultGrams : 100
        let kcal = Int((Double(food.caloriesPer100g) * grams / 100).rounded())
        return FoodRow(
            name: food.name,
            calories: kcal,
            caloriesPer100g: food.caloriesPer100g,
            portion: "\(Int(grams)) \(String(localized: "г"))",
            macros: food.macrosPer100g.portion(grams: grams),
            micros: store.notableMicronutrients(forFoodNamed: food.name, grams: grams),
            offersVitamins: store.foodsOfferedVitamins.contains(food.id),
            leadingMacros: food.macrosPer100g,
            traits: food.traits
        )
    }

    /// Записать в дневник: открывает экран порции.
    private func recordButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "fork.knife")
        }
        .tint(.blue)
        .accessibilityLabel("В приём пищи")
    }

    /// Положить продукт из базы в свои — одним свайпом, не открывая его.
    @ViewBuilder
    private func saveToMyFoodsButton(_ food: FoodItem) -> some View {
        if !store.isInMyFoods(food) {
            Button {
                store.saveToMyFoods(food)
            } label: {
                Image(systemName: "bookmark")
            }
            .tint(.indigo)
            .accessibilityLabel("В мои продукты")
        }
    }

    /// Запись с экрана порции прямо в дневник.
    /// Пересобрать списки разделов.
    private func recomputeLists() {
        dishes = filteredDishes
        products = filteredProducts
        database = filteredDatabase
    }

    private func record(_ item: MealItem) {
        // С составом: по нему «Недавнее» видит продукт, а разбор дня —
        // категорию. Запись из одного продукта — это он сам.
        store.add(name: item.name, calories: item.calories, macros: item.macros, grams: item.grams,
                  components: [EntryComponent(name: item.name, calories: item.calories,
                                              macros: item.macros, grams: item.grams)])
    }
}
