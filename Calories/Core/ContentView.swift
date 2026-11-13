import SwiftUI
import SwiftData

struct ContentView: View {
    var store: CalorieStore
    var stepStore: StepStore
    /// Как кольцу появиться при запуске. Решает это `RootView`: только он
    /// знает, была заставка или нет и когда она ушла.
    var ringEntrance: RingEntrance = .none
    @State private var showingAdd = false
    /// Короткие листы с «Сегодня» — одним модификатором: несколько `.sheet`
    /// на одной вьюхе спорят, и срабатывает только последний.
    @State private var todaySheet: TodaySheet?
    @State private var ringSpinTicket = 0
    /// Насколько список стянут. Читает его только кольцо — см. `RingPull`.
    @State private var ringPull = RingPull()

    enum TodaySheet: String, Identifiable {
        case weight, quickCalories, newFood, newDish, scanner, fasting
        var id: String { rawValue }
    }
    @State private var showingMeasurements = false
    /// Экран истории: календарь месяца, за кнопкой в конце полоски недели.
    @State private var selectedHistoryDay: Date?
    @State private var showingDayNutrition = false
    @State private var showingSteps = false
    @State private var showingBankInfo = false
    @State private var showingPaywall = false
    @State private var showingPlan = false
    /// С чего открыть добавление, если пришли по меню на иконке.
    @State private var entryAction: QuickAction?
    /// Запись, к которой добавляют ещё еды.
    @State private var appendingTo: FoodEntry?
    @State private var showingFasting = false
    /// Общие настройки расписания, а не свой экземпляр: раньше «Сегодня» и
    /// настройки читали каждый своё, и включённое деление дня не появлялось
    /// до перезапуска. Держим в `@State`, чтобы вкладка перерисовывалась,
    /// когда тумблер переключили на соседней.
    @State private var mealSchedule = MealScheduleSettings.shared
    @State private var showingMealSchedule = false
    /// Что предложить при тапе на «Пора есть» — обычное блюдо для этого приёма.
    @State private var initialUsualMeal: UsualMeal.Suggestion? = nil
    /// Крупное кольцо уехало под шапку — в шапке его подменяет миниатюра.
    @State private var ringIsAway = false
    /// Поверх «Сегодня» что-то открыто.
    private var isCovered: Bool {
        todaySheet != nil || showingAdd || appendingTo != nil || showingMeasurements
    }
    /// Высота списка и то, сколько у него снизу занято таббаром. Из этих
    /// двух считается, сколько места осталось кольцу.
    /// Блюдо, которое открываем из подсказки про сваренное.
    @State private var openingDish: Dish?
    @State private var listHeight: CGFloat = 0
    @State private var listBottomInset: CGFloat = 0

    /// Пробую настройки на экране Сегодня

    /// Высота первого экрана: ровно видимая часть списка.
    ///
    /// Полоска и плитки берут своё, остаток достаётся кольцу — поэтому блок
    /// кончается у таббара, а дневник начинается со следующего экрана.
    /// Нижняя граница не для красоты: на маленьком экране с крупным шрифтом
    /// без неё кольцо схлопнулось бы в точку.
    private var summaryHeight: CGFloat {
        // Подсказки дня живут под кольцом — все в одном месте, чтобы их не
        // искать по экрану. Приходят они не каждый день, и платить за них
        // должен экран, а не кольцо: без добавки каждая отъедала бы у знака
        // свою высоту, потому что блок фиксирован.
        let weighIn: CGFloat = (store.profile == nil || !store.hasWeighedToday) ? 52 : 0
        let batch: CGFloat = store.batchHint() == nil ? 0 : 52
        return max(listHeight - listBottomInset - 8, 420) + weighIn + batch
    }
    private let quickActions = QuickActionRouter.shared

    /// Разбирает нажатие на иконке. Забираем действие сразу, чтобы повторный показ
    /// экрана не открыл камеру во второй раз.
    private func consumeQuickAction(_ action: QuickAction?) {
        guard let action else { return }
        quickActions.pending = nil
        switch action {
        case .weight:
            todaySheet = .weight
        case .measurements:
            showingMeasurements = true
        case .scanner:
            todaySheet = .scanner
        case .meal:
            entryAction = action
            showingAdd = true
        }
    }

    /// Копия, к которой надо прокрутить список. Сбрасывается сразу после
    /// прокрутки: это событие, а не состояние.
    @State private var copiedEntryID: UUID?

    /// Дата в шапке — с заглавной, какой бы формы она ни была.
    ///
    /// Сама по себе она приходит вразнобой: в русском день недели словом
    /// строчный («воскресенье, 8 ноября»), а сокращённый — с прописной
    /// («Вс, 8 ноября»), потому что это разные формы в данных локали.
    /// В шапке это одна и та же строка, и меняться от длины её написание
    /// не должно. Языкам без регистра — арабскому, ивриту — поднятие
    /// регистра ничего не делает.
    private static func dateLine(_ style: Date.FormatStyle) -> String {
        let text = Date().formatted(style)
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    var body: some View {
        NavigationStack {
            // Ридер ради одного: показать, куда уехала копия приёма. Копия
            // получает время «сейчас», а значит попадает в текущий приём —
            // он же первый в списке, и с середины дневника новая строка
            // появляется за верхней кромкой, то есть будто бы нигде.
            ScrollViewReader { scroll in
            List {
                Section {
                    summaryCards
                        // Блок по своему содержимому: кольцо не тянется на весь
                        // экран, карточки идут за ним сразу, без пустоты между ними.
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 16, trailing: 16))
                }
                .listSectionSeparator(.hidden)

                // Стекло — только строкам дневника.
                //
                // На списке целиком оно побеждало прозрачный фон, заданный
                // строке: первый экран получал белую плашку во всю свою
                // высоту, и в светлой теме под плитками торчал её край.
                diarySections
                    .glassRow()
            }
            .listStyle(.insetGrouped)
            // Полоску дней — ближе к шапке.
            //
            // Сгруппированный список отбивает первую секцию от навигации на
            // три десятка точек: они нужны заголовку секции, которого здесь
            // нет. Полоска дней — продолжение шапки, а не отдельный блок, и
            // повисала она в пустоте, пока под ней кольцу места не хватало.
            .contentMargins(.top, 8, for: .scrollContent)
            // Шапка размывает содержимое под собой, а не отрезает его.
            //
            // По умолчанию у неё своя заливка и жёсткая кромка: под шапкой
            // проходил шов, и прокрученные плитки обрывались по линейке.
            // Мягкий край — то же, что уже стоит в «Рационе»: содержимое
            // уходит под шапку, растворяясь.
            .scrollEdgeEffectStyle(.soft, for: .top)
            .scrollIndicators(.hidden)
            // Перетяг спрашиваем у самого списка, а не вычисляем по тому, где
            // оказалось кольцо.
            //
            // Кольцо запоминало своё положение в покое — первое, которое
            // увидело, — и дальше считало перетягом любое отклонение от него.
            // Но блок первого экрана меняет высоту в тот же день: приходит
            // строка взвешивания, приходит подсказка про сваренное, и каждая
            // забирает свои пятьдесят две точки. Кольцо съезжает вниз, запомненный
            // покой остаётся наверху — и кольцо считает, что список стянут,
            // когда он стоит. Отсюда и поворот, появлявшийся сам собой, и
            // рывок на возврате: оно возвращалось не на место, а к чужой
            // отметке.
            //
            // У списка это число есть без всяких отметок.
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                max(0, -(geometry.contentOffset.y + geometry.contentInsets.top))
            } action: { _, pull in
                ringPull.offset = pull
            }
            .onChange(of: copiedEntryID) { _, id in
                guard let id else { return }
                withAnimation(.snappy) { scroll.scrollTo(id, anchor: .center) }
                copiedEntryID = nil
            }
            // Пока тянут вниз, кольцо делает оборот — тот же жест, что у знака на
            // запуске. Обновление мгновенное, поэтому ждём конца оборота, иначе
            // индикатор списка пропадал бы на полпути.
            .refreshable {
                store.refresh()
                ringSpinTicket += 1
                try? await Task.sleep(for: .seconds(ProgressRing.refreshHold))
            }
            .navigationDestination(for: FoodEntry.self) { entry in
                EditEntrySheet(store: store, entry: entry, isEmbedded: true)
            }
            .navigationDestination(isPresented: $showingFasting) {
                FastingView(store: store)
            }
            .navigationDestination(item: $openingDish) { dish in
                NewDishSheet(store: store, editingDish: dish, isEmbedded: true)
            }
            .navigationDestination(isPresented: $showingPlan) {
                PlanView(store: store)
            }
            .navigationTitle("Сегодня")
            // Какое именно сегодня — в нашей же шапке, рядом с кольцом:
            // «Сегодня» — слово без числа, а записи в приложении о днях, и
            // день недели с датой человек держит в голове сам ровно до
            // первого раза, когда ошибётся. Системная `.navigationSubtitle`
            // здесь не годится — она встала бы второй такой же строкой.
            // Крупным, но в самой шапке: большой заголовок над содержимым
            // уезжает прокруткой, а «Сегодня» с датой нужны и после неё.
            .toolbarTitleDisplayMode(.inline)
            // Системный заголовок гасим: наш стоит в левом слоте, и средний
            // остаётся свободным — iOS рисует в нём своё «Сегодня», и слово
            // оказывается на экране дважды.
            .hiddenNavigationTitle()
            .toolbar {
                // Кольцо уезжает влево от «Сегодня», а не вправо к кнопкам.
                //
                // Справа оно стояло среди действий — плюса, шагов, настроек —
                // и читалось ещё одной кнопкой в ряду, хотя это не действие,
                // а то же кольцо дня, просто уехавшее под шапку. Слева от
                // заголовка у него своё место: знак экрана перед его
                // названием, а ряд действий справа остаётся рядом действий.
                //
                // Заголовок при этом наш, а не системный: `.inlineLarge`
                // держит слева самого себя, и поставить что-либо перед ним
                // нельзя — лишний элемент уезжает в «ещё» справа. Поэтому
                // шапку собираем сами, повторяя системную: крупное название
                // и дата под ним.
                // В левом слоте, а не в среднем.
                //
                // Средний к левому краю не прижать: тулбар меряет его
                // содержимое и ставит рамку по центру того, что осталось от
                // кнопок. Пока шапка была широкой — знак, название и полная
                // дата, — она занимала промежуток целиком и стояла у края
                // как бы сама собой; стоило дате уйти, и всё съезжало к
                // середине. Ни `maxWidth: .infinity`, ни распорка внутри
                // ряда этого не меняют. В левом слоте прижимать нечего — он
                // и есть левый край, и тем же слотом стоят «Профиль» с
                // «Рационом», так что все три вкладки начинаются на одной
                // вертикали.
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 8) {
                        if ringIsAway {
                            ProgressRing(
                                consumed: store.consumedToday,
                                goal: store.adaptedTodayGoal,
                                macros: store.macrosToday,
                                proteinTarget: store.proteinTarget,
                                fatTarget: store.fatTarget,
                                carbsTarget: store.carbsTarget,
                                miniature: 34,
                                onOpen: {
                                    entryAction = nil
                                    showingAdd = true
                                }
                            )
                            .accessibilityHidden(true)
                            .transition(.scale(scale: 0.2).combined(with: .opacity))
                        }
                        VStack(alignment: .leading, spacing: 0) {
                            // Одного кегля в обоих состояниях. Пробовали
                            // поднимать название ещё на ступень, когда дата
                            // уходит и оно остаётся в шапке одно, — крупным
                            // оно лезет вперёд знака дня, ради которого
                            // шапку и собирали.
                            //
                            // `title2` — верх лестницы заголовков: столько
                            // же у «Профиля» и «Рациона», на ступень меньше
                            // у экранов, открытых из них переходом.
                            Text("Сегодня")
                                .font(.app(.title2, weight: .bold))
                            // Дата — только пока экран в покое.
                            //
                            // День недели словом не сокращаем: «Сб, 7 нояб.»
                            // читается справочником. Но когда кольцо уезжает
                            // в шапку, оно забирает своё место, и полная
                            // дата туда уже не входит — обрывалась на
                            // «нояб…». Вместо того чтобы её ужимать, убираем
                            // совсем: прокрутили — значит смотрят дневник, а
                            // не сверяются с числом, и в шапке остаётся знак
                            // дня и название экрана.
                            //
                            // `ViewThatFits` при этом остаётся: при крупном
                            // системном шрифте и в других языках строка
                            // длиннее, и отступать ей лучше ступенями, чем
                            // обрываться.
                            if !ringIsAway {
                                ViewThatFits(in: .horizontal) {
                                    Text(Self.dateLine(.dateTime.weekday(.wide).day().month(.wide)))
                                    Text(Self.dateLine(.dateTime.weekday(.abbreviated).day().month(.wide)))
                                    Text(Self.dateLine(.dateTime.day().month(.wide)))
                                }
                                .font(.app(.caption))
                                .foregroundStyle(.secondary)
                                .transition(.opacity)
                            }
                        }
                        .lineLimit(1)
                    }
                    // Свой размер: левый слот выдаёт минимум ширины, и без
                    // этого название приезжает одной буквой с многоточием.
                    .fixedSize()
                }
                .withoutSharedBackground()
                ToolbarItem(placement: .topBarTrailing) {
                    HStack {
                        Menu {
                            Button {
                                todaySheet = .scanner
                            } label: {
                                Label("Сканировать штрихкод", systemImage: "barcode.viewfinder")
                            }
                            Divider()
                            Button {
                                entryAction = nil
                                showingAdd = true
                            } label: {
                                Label("Приём пищи", systemImage: "fork.knife")
                            }
                            Button {
                                todaySheet = .quickCalories
                            } label: {
                                Label("Только калории", systemImage: "number")
                            }
                            Button {
                                todaySheet = .newFood
                            } label: {
                                Label("Новый продукт", systemImage: "plus")
                            }
                            Button {
                                todaySheet = .newDish
                            } label: {
                                Label("Новый рецепт", systemImage: "frying.pan")
                            }
                            Divider()
                            Button {
                                todaySheet = .weight
                            } label: {
                                Label("Взвеситься", systemImage: "scalemass")
                            }
                            Button {
                                showingMeasurements = true
                            } label: {
                                Label("Снять замеры", systemImage: "ruler")
                            }
                            Button {
                                todaySheet = .fasting
                            } label: {
                                Label("Голодание", systemImage: "moon.stars")
                            }
                            .accessibilityIdentifier("openFasting")
                        } label: {
                            Image(systemName: "plus")
                        }
                        // Голосом значок не прочитать: без подписи VoiceOver
                        // говорит «plus» — имя символа, а не действие. Там, где
                        // у кнопки нет слова рядом, его даёт подпись.
                        .accessibilityLabel("Добавить")
                        .accessibilityIdentifier("addMenu")
                    }
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: ringIsAway)
                }

                // Отдельный ToolbarItem для шагов (остается на своем месте)
                ToolbarItem(placement: .topBarTrailing) {
                    StepsChip(store: stepStore) { showingSteps = true }
                        .accessibilityIdentifier("steps")
                }
            }
            .background {
                GeometryReader { geometry in
                    Color.clear
                        .onChange(of: geometry.size.height, initial: true) { _, height in
                            guard !isCovered else { return }
                            listHeight = height
                        }
                        // Таббар вычитаем по безопасной области, а не числом:
                        // высота списка приходит вместе с местом под ним, и
                        // без этого последний ряд плиток уезжал под таббар.
                        //
                        // Пока сверху лист — не меряем вовсе. Клавиатуру,
                        // поднятую листом, безопасная область списка считает
                        // своей: нижний отступ прыгает на три сотни точек,
                        // блок первого экрана схлопывается до своего минимума,
                        // и плитки наезжают на кольцо. Экран под листом не
                        // меняется, значит и перемерять его нечего — мерку
                        // берём ту, что была до показа.
                        .onChange(of: geometry.safeAreaInsets.bottom, initial: true) { _, inset in
                            guard !isCovered else { return }
                            listBottomInset = inset
                        }
                }
            }
            .sheet(isPresented: $showingAdd, onDismiss: { entryAction = nil }) {
                AddEntryView(store: store, initialAction: entryAction,
                             initialUsualMeal: initialUsualMeal,
                             onFinish: { showingAdd = false; initialUsualMeal = nil })
                // Во всю высоту, без половины: приём собирают с поиском, списком
                // и черновиком, и на половине экрана помещалась строка-две, а под
                // листом оставался живой экран «Сегодня», который при вводе
                // перерисовывался вместе с клавиатурой.
                .presentationBackground(Color(.systemBackground))
            }
            .sheet(item: $appendingTo) { entry in
                AddEntryView(store: store, appendingTo: entry,
                             onFinish: { appendingTo = nil })
                .presentationBackground(Color(.systemBackground))
            }
            .sheet(item: $todaySheet) { sheet in
                switch sheet {
                case .weight:
                    AddWeightView(store: store)
                        .presentationDetents([.height(AddWeightView.sheetHeight)])
                case .quickCalories:
                    QuickCaloriesSheet { calories, date in
                        store.add(name: String(localized: "Приём пищи"), calories: calories, date: date)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        todaySheet = nil
                    }
                    .presentationDetents([.height(250)])
                // Обе высоты у обоих: продукт и рецепт заводят по-разному —
                // одному хватает названия и калорий, другому нужен весь
                // состав. Пусть человек сам решает, сколько ему места, а не
                // мы за него: лист с двумя высотами тянется в обе стороны.
                case .newFood:
                    NewFoodSheet(store: store)
                        .presentationDetents([.medium, .large])
                case .newDish:
                    NewDishSheet(store: store)
                        .presentationDetents([.medium, .large])
                case .fasting:
                    NavigationStack {
                        FastingView(store: store)
                            .toolbar {
                                ToolbarItem(placement: .confirmationAction) {
                                    CheckmarkButton { todaySheet = nil }
                                }
                            }
                    }
                case .scanner:
                    // Отсканированное записывается приёмом пищи; сохранить в мои
                    // продукты можно второй кнопкой на экране продукта.
                    BarcodeScannerSheet(store: store) { item in
                        store.add(name: item.name, calories: item.calories, macros: item.macros, grams: item.grams)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }
                    .presentationDetents([.medium])
                }
            }
            // Замеры открываются прямо здесь, а не переходом на экран замеров:
            // по контролу приходят с лентой в руках, чтобы вбить числа, а не
            // смотреть выводы. Выводы — там, где им и место, на «Теле».
            .fullScreenCover(isPresented: $showingMeasurements) {
                MeasurementEntrySheet(store: store, isPresented: $showingMeasurements)
            }
            .navigationDestination(isPresented: $showingDayNutrition) {
                DayNutritionView(store: store)
            }
            .navigationDestination(item: $selectedHistoryDay) { date in
                DayDetailView(store: store, date: date)
            }
            .navigationDestination(isPresented: $showingSteps) {
                StepsNavigationView(store: stepStore)
            }
            // Переходом, а не листом: расписание — экран настройки, с которого
            // уходят назад, а не задача, которую закрывают галочкой. Листом он
            // к тому же перекрывал «Сегодня», ради которого его и открывали.
            .navigationDestination(isPresented: $showingMealSchedule) {
                MealScheduleSheet(entries: store.todayEntries.map { (date: $0.date, calories: $0.calories) },
                                  dailyGoal: store.adaptedTodayGoal,
                                  settings: mealSchedule,
                                  store: store,
                                  isEmbedded: true)
            }
            .navigationDestination(isPresented: $showingPaywall) {
                PaywallView(store: store)
            }
            // Действие с иконки может прилететь и до появления экрана (холодный
            // старт), и во время работы — забираем его в обоих случаях.
            .task { consumeQuickAction(quickActions.pending) }
            .onChange(of: quickActions.pending) { _, action in consumeQuickAction(action) }
            // Закрытие макроса — событие, а не перекраска.
            //
            // Цвет приложения идёт за недобранным макросом, и без отклика его
            // смена посреди дня читается как сбой: вот всё было бирюзовым, а
            // стало коралловым. Короткий тук говорит, что это сделал человек,
            // а не приложение сломалось.
            .onChange(of: store.focusMacro) { oldValue, newValue in
                guard oldValue != nil, newValue != oldValue else { return }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
            .onChange(of: store.consumedToday) { oldValue, newValue in
                let goal = store.adaptedTodayGoal
                if oldValue < goal && newValue >= goal {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
                // Островок — вслед за дневником. Здесь же, а не своим
                // наблюдателем: еда меняет съеденное за день, и другого
                // признака «в дневнике что-то произошло» у экрана нет.
                syncKosherActivity()
            }
            .onAppear { syncKosherActivity() }
            }
        }
        // Клавиатура этот экран не двигает.
        //
        // Поля ввода здесь нет ни одного: клавиатуру поднимает лист поверх —
        // калории, новый рецепт. Но безопасную область она сужает всему, что
        // под ней, и «Сегодня» вместе с листом сжималось: полоска взвешивания
        // наезжала на кольцо, а само кольцо мельчало. Клавиатура принадлежит
        // листу и лежит над экраном, а не внутри его вёрстки.
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }
}

extension ContentView {
    /// Время приёма пищи: когда ел. Если записей несколько — от первой до
    /// последней, потому что приём редко укладывается в минуту.
}

// MARK: - Части экрана «Сегодня»
//
// Тело `body` разрослось до пятисот строк, и это стоило не только чтения:
// на таком дереве компилятор один раз уже сдался с «unable to type-check this
// expression in reasonable time». Куски вынесены свойствами с явным типом —
// так проверка типов идёт по частям, а сам `body` показывает устройство
// экрана, а не его содержимое.
private extension ContentView {
    /// Сегодняшний день сверху экрана: кольцо, макросы и полоски.
    ///
    /// Порядок читается как отъезд камеры: кольцо и макросы — это прямо
    /// сейчас, дальше ближайший приём (часы), голодание (дни), план (недели)
    /// и неделя позади.
    var summaryCards: some View {
        // Расписание спрашиваем один раз: строится оно примерно за миллисекунду,
        // а в теле оно нужно дважды — проверить, есть ли приёмы, и показать их.
        let slots = store.todaySlots
        return VStack(spacing: 16) {
            // Полоска дней первой строкой содержимого, а не прибитой панелью.
            //
            // Прибитая, она занимала место всегда, даже когда человек читает
            // дневник и до прошлых дней ему нет дела. Первой строкой она
            // стоит под шапкой, пока экран в покое, и уезжает под неё, стоит
            // потянуть список вверх, — так же, как это делает поиск в списке
            // чатов. Прокрутка её толкает, а не обходит.
            WeekStrip(weeks: store.weekStripWeeks(),
                      onSelect: { selectedHistoryDay = $0 })

            // Подсказки — отдельной строкой сразу под первым экраном:
            // свою высоту они берут у дневника, а не у кольца.
            if hasDayHints {
                Section {
                    dayHints
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 16, trailing: 16))
                }
                .listSectionSeparator(.hidden)
            }
            
            PullableRing(
                consumed: store.consumedToday,
                goal: store.adaptedTodayGoal,
                macros: store.macrosToday,
                proteinTarget: store.proteinTarget,
                fatTarget: store.fatTarget,
                carbsTarget: store.carbsTarget,
                spinTicket: ringSpinTicket,
                pull: ringPull,
                onOpen: {
                    entryAction = nil
                    showingAdd = true
                },
                // Подмена кольца миниатюрой — с анимацией, иначе её нет
                // вовсе: `.transition` на элементе тулбара отыгрывается
                // только тогда, когда само изменение состояния анимировано.
                // Короткая пружина без перелёта: знак догоняет шапку, а не
                // прыгает в неё.
                // Пока поверх экрана лист, кольцо не пересчитываем.
                //
                // iOS показывает лист, уменьшая экран под ним карточкой, и
                // это не вёрстка, а преобразование — но в глобальных
                // координатах оно видно: кольцо «уезжает» под шапку, хотя
                // человек ничего не листал. На коротком листе это заметно
                // глазом — кольцо на заднем плане съёживалось и бледнело.
                onAway: { away in
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                        ringIsAway = away
                    }
                },
                entrance: ringEntrance,
                isCovered: isCovered
            )
            // Кольцу — весь остаток: высоту блока задаёт экран, полоска и
            // плитки берут своё, остальное кольцу. Так не нужно знать ни
            // высоту полоски, ни число рядов — они меняются, а это нет.
            //
            // Без своего минимума: он нужен был, пока в блоке жили подсказки
            // и места кольцу могло не остаться совсем. Подсказки съехали в
            // свою строку, состав блока постоянный — а минимум с тех пор
            // только мешал: когда сумма полоски, кольца и шести плиток
            // переваливала за высоту блока, список обрезал нижний ряд.
            // Кольцо минимум 200 точек высоты, чтобы хорошо читалось, но не
            // растягивается на весь экран — карточки под ним не должны уезжать.
            .frame(minHeight: 220)
            // Воздух снизу, но не сверху: знак берёт не весь остаток, а
            // остаток минус поле. Снизу эти четырнадцать точек держат кольцо
            // от полоски взвешивания и плиток. Сверху же над ним полоска
            // дней, и между ними и так шестнадцать точек отбивки — вместе
            // выходило тридцать, и дуга, у которой наверху разрыв, висела
            // ещё ниже. Освободившееся достаётся самому знаку.
            .padding(.bottom, 30)

            // Сваренное напоминает о себе само: доесть, пока не испортилось,
            // или приготовить, пока не кончилось. Одна строка на самую
            // срочную кастрюлю — список дел по холодильнику тут не нужен.
            if let hint = store.batchHint() {
                BatchHintRow(dish: hint.dish, state: hint.state, advice: hint.advice) {
                    openingDish = hint.dish
                }
            }

            // Взвешивание — сразу под кольцом.
            //
            // Это первое дело дня и то, из чего считается вся остальная
            // картина: без утреннего веса ни тренд, ни расход не сдвинутся.
            // В хвосте экрана, под плитками и напоминаниями, строка
            // попадалась на глаза последней — когда до весов уже не дойти.
            if store.profile == nil {
                NavigationLink {
                    SettingsView(store: store)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "person.crop.circle.badge.questionmark")
                            .font(.app(.footnote))
                        Text("Заполнить профиль")
                            .font(.app(.caption))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.app(.caption2))
                    }
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.blue.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            } else if !store.hasWeighedToday,
                      // Только утром: вечерний вес выше на съеденное за день
                      // и тренд только сбивает. Из «+» взвеситься можно всегда.
                      WeighInWindow.isOpen(now: Date(), wakeHour: hourOfDay(mealSchedule.wake)) {
                Button {
                    todaySheet = .weight
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "scalemass")
                            .font(.app(.footnote))
                        Text("Взвешивание")
                            .font(.app(.caption))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.app(.caption2))
                    }
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                // Имя строке нужно тесту: он следит, чтобы кольцо на неё не
                // наезжало. Проверять это глазами выходит плохо — наезд уже
                // приезжал дважды.
                .accessibilityIdentifier("weighInRow")
            }

            // Экран читается как отъезд камеры: кольцо и макросы —
            // сегодняшний день, дальше ближайший приём (часы),
            // голодание (ближайшие дни), план (недели вперёд) и
            // неделя позади. Раньше план стоял выше приёмов, хотя
            // в него заходят раз в неделю, а на ближайший приём
            // смотрят по нескольку раз в день.
            // Две плитки вместо двух полос.
            //
            // Полоса во всю ширину несла три слова и стрелку, остальное было
            // воздухом, и таких полос подряд стояло две. Плитки занимают ту же
            // высоту вдвоём, сколько раньше одна полоса, и читаются как два
            // ответа на два разных вопроса: когда есть и куда иду.
            VStack(spacing: 12) {
            HStack(spacing: 12) {
                if mealSchedule.isEnabled, !slots.isEmpty {
                    MealScheduleStrip(slots: slots,
                                      remainingToday: max(0, store.adaptedTodayGoal - store.consumedToday),
                                      dailyGoal: store.adaptedTodayGoal,
                                      onOpen: { showingMealSchedule = true },
                                      onEat: { addFromMealTile() })
                    .tile
                }

                PlanStrip(
                    store: store,
                    onOpenPlan: { showingPlan = true },
                    onShowPaywall: { showingPaywall = true }
                )
                .tile
            }

            // Макросы под ними: приём и план — про то, что делать сейчас и
            // куда идёшь, а макросы — отчёт о том, что уже съедено. Решение
            // выше отчёта.
            MacrosCard(
                macros: store.macrosToday,
                proteinTarget: store.proteinTarget,
                fatTarget: store.fatTarget,
                carbsTarget: store.carbsTarget,
                fiber: store.micronutrients(on: Date()).fiber,
                fiberIsPartial: store.micronutrients(on: Date()).fiberIsPartial,
                weightKg: store.weightKg,
                behindMacros: behindMacros,
                onOpen: { showingDayNutrition = true },
                gymDayName: store.gymHeavyDayName,
                focus: store.focusMacro
            )
            }
        }
    }

    /// Есть ли сегодня хоть одна подсказка.
    ///
    /// Спрашиваем до того, как строить строку: пустая строка в списке — это
    /// не ничто, а пустая плашка с фоном и отступами, и под плитками
    /// оставался светлый обрезок с провалом до дневника.
    private var hasDayHints: Bool {
        if needsBackupReminder { return true }
        if store.recoveryAdvice() != nil { return true }
        if store.fastingHint() != nil { return true }
        if store.isPremium, store.reviewIsDue, store.proposedGoal != nil { return true }
        if store.calorieBankBonus != 0 { return true }
        if let advice = dailyAdvice, advice != .none { return true }
        return false
    }

    /// Тап по плитке приёма, когда пора есть: сразу добавление еды с «Как
    /// обычно» для этого приёма.
    ///
    /// Раньше для этого была отдельная строка-подсказка под плитками. Она
    /// повторяла плитку — тот же приём, то же время — и стоила строки и
    /// второго тапа по тому же вопросу. Теперь состояние живёт в самой
    /// плитке: её вид и её тап отвечают на «пора?» одинаково.
    private func addFromMealTile() {
        guard let slot = MealSchedule.nextSlot(store.todaySlots, now: Date()) else { return }
        initialUsualMeal = store.usualMeals(period: slot.period, days: 180).first
        showingAdd = true
    }

    /// Макросы, которые требуют внимания: белок и жиры — отстают от темпа,
    /// углеводы — заметно превышают норму.
    ///
    /// Считается для плиток под кольцом: там же, где видно количество,
    /// уместно и «добавь белка», и «углеводы сверх нормы». Отдельными
    /// строками эти советы жили в хвосте экрана и появлялись с утра, когда
    /// оценивать их ещё рано.
    private var behindMacros: Set<MacroKind> {
        let progress = DailyAdviceEngine.dayProgress(wake: hourOfDay(mealSchedule.wake),
                                                     sleep: hourOfDay(mealSchedule.sleep),
                                                     now: Date())
        var behind: Set<MacroKind> = []
        if DailyAdviceEngine.isBehindPace(eaten: store.macrosToday.protein,
                                          target: store.proteinTarget,
                                          progress: progress) {
            behind.insert(.protein)
        }
        if DailyAdviceEngine.isBehindPace(eaten: store.macrosToday.fat,
                                          target: store.fatTarget,
                                          progress: progress) {
            behind.insert(.fat)
        }
        if DailyAdviceEngine.isOverTarget(eaten: store.macrosToday.carbs,
                                          target: store.carbsTarget,
                                          progress: progress) {
            behind.insert(.carbs)
        }
        return behind
    }

    /// Совет дня: одно контекстное сообщение на основе данных пользователя.
    private var dailyAdvice: DailyAdvice? {
        let calendar = Calendar.current
        let lastLoggedDay = store.entriesByDay.keys.sorted().last
        let weighIns = store.weightEntries.map { AdviceWeighIn(date: $0.date, kg: $0.weightKg) }
        return DailyAdviceEngine.advice(
            consumedToday: store.consumedToday,
            adaptedTodayGoal: store.adaptedTodayGoal,
            macrosToday: store.macrosToday,
            proteinTarget: store.proteinTarget,
            fatTarget: store.fatTarget,
            carbsTarget: store.carbsTarget,
            weighIns: weighIns,
            lastLoggedDay: lastLoggedDay,
            wakeHour: hourOfDay(mealSchedule.wake),
            sleepHour: hourOfDay(mealSchedule.sleep)
        )
    }

    /// Час суток дробным числом: 7.5 — это 7:30.
    ///
    /// Нужен совету дня, чтобы сравнивать съеденное с темпом дня, а не
    /// с итоговой нормой.
    private func hourOfDay(_ date: Date) -> Double {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return Double(parts.hour ?? 0) + Double(parts.minute ?? 0) / 60
    }

    /// Подсказки дня: голодание, недельный обзор, банк калорий.
    ///
    /// Взвешивание отсюда уехало под кольцо: это не напоминание в хвосте, а
    /// первое дело дня, из которого считается всё остальное.
    ///
    /// Своей строкой под первым экраном, а не внутри него.
    ///
    /// Они приходят и уходят — сегодня висит «взвесься», завтра банк, а
    /// послезавтра ничего, — и пока они стояли в блоке фиксированной высоты,
    /// каждая отнимала место у кольца: в день без еды, где подсказок больше
    /// всего, знак садился вдвое и выглядел карликом. Теперь состав первого
    /// экрана постоянный — полоска, кольцо, шесть плиток, — и кольцо всегда
    /// одного размера. Подсказки же никуда не делись: они сразу под ним, в
    /// одном движении прокрутки.
    /// Действующие ожидания между мясным и молочным — пусто, пока кашрут
    /// выключен. Спрашиваем настройки здесь, а не в хранилище: дневник не
    /// должен знать, какой у человека обычай.
    ///
    /// На экране их нет: ответ на «можно ли уже» живёт в островке и на
    /// экране блокировки, то есть там, где этот вопрос и задают — не открывая
    /// приложение. Своя строка под кольцом дублировала бы его и отнимала у
    /// знака высоту ради того, что и так перед глазами.
    private var kosherWaits: [KosherWait] {
        let settings = KosherSettings.shared
        guard settings.isEnabled else { return [] }
        return store.kosherWaits(custom: settings.custom)
    }

    /// Островок — вслед за дневником.
    ///
    /// Зовётся при появлении экрана и после каждой записи: Живую активность
    /// разрешено заводить, только пока приложение на экране, а запись еды —
    /// ровно такой момент.
    private func syncKosherActivity() {
        KosherActivity.sync(waits: kosherWaits, enabled: KosherSettings.shared.isEnabled)
    }

    /// Пора ли сказать, что копий дневника нет.
    private var needsBackupReminder: Bool {
        BackupService.needsReminder(isConfigured: BackupService.shared.isConfigured,
                                    daysOfDiary: store.entriesByDay.count)
    }

    @ViewBuilder
    var dayHints: some View {
        VStack(spacing: 16) {
            // Копий нет, а дневнику уже есть что терять.
            //
            // Выше всего остального, и это единственная подсказка не про еду:
            // остальные советуют, а эта предупреждает. Синхронизации у
            // приложения нет, контейнер удаляется вместе с ним, и выбранная
            // папка — единственное, что стоит между годом записей и пустым
            // экраном. Уходит навсегда, как только папка выбрана.
            if needsBackupReminder {
                NavigationLink {
                    SettingsView(store: store)
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "externaldrive.badge.exclamationmark")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Копий дневника нет")
                                .font(.app(.subheadline, weight: .semibold))
                            Text("Он живёт только на этом телефоне. Выбери папку — копия будет обновляться сама.")
                                .font(.app(.caption))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.app(.caption))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 2)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("backupMissing")
            }

            // Не пора ли подъесть — первой строкой.
            //
            // Это единственная подсказка, которая говорит остановиться, а не
            // сделать: остальные зовут взвеситься, доесть кастрюлю, свериться
            // с неделей. В «Профиле», под сном и пульсом, она попадалась на
            // глаза тому, кто и так следит, — а нужна тому, кто просто живёт
            // по норме и не видит, что норма перестала работать.
            if let advice = store.recoveryAdvice() {
                Button { showingPlan = true } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: advice.verdict == .dietBreak
                              ? "pause.circle" : "arrow.up.forward.circle")
                            .foregroundStyle(ProgressRing.kcalColors[0])
                        Text(verbatim: advice.text)
                            .font(.app(.subheadline))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 2)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("recoveryAdvice")
            }

            // Отмеченный день голодания — не строка в настройках, а
            // состояние сегодняшнего дня: пустой дневник в такой день
            // должен читаться как «так и задумано», а не как провал.
            // Голодание сегодня или в ближайшие три дня: подсказка к
            // месту — за пару дней про кофе, накануне про соль и воду,
            // в сам день про выход. Вся памятка — по нажатию.
            //
            // Выше недели: голодание — про сегодня и ближайшие дни,
            // а неделя про прошедшие. Внизу экрана, под неделей и
            // банком, подсказка про выход из поста попадалась на
            // глаза последней, когда она нужнее всего.
            if let hint = store.fastingHint() {
                FastingStrip(hint: hint) { showingFasting = true }
            }

            // Недельный обзор зовёт только когда есть о чём говорить:
            // прошла неделя с прошлого раза, и расчёт разошёлся с нормой
            // заметнее полусотни килокалорий. Без повода строки нет.
            if store.isPremium, store.reviewIsDue, let proposal = store.proposedGoal {
                Button { showingPlan = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "calendar.badge.clock")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Недельный обзор")
                                .font(.app(.subheadline, weight: .medium))
                            Text(verbatim: String(format: String(localized: "%lld ккал"), proposal))
                                .font(.app(.caption))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.app(.caption))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 2)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("weeklyReviewDue")
            }

            if store.calorieBankBonus != 0 {
                Button { showingBankInfo = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: store.calorieBankBonus > 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                            .foregroundStyle(store.calorieBankBonus > 0 ? .green : .orange)
                        Text(store.calorieBankBonus > 0
                             ? "+\(store.calorieBankBonus) ккал из недели"
                             : "\(store.calorieBankBonus) ккал из недели")
                            .foregroundStyle(.secondary)
                    }
                    .font(.app(.caption))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingBankInfo) {
                    CalorieBankPopover(
                        bonus: store.calorieBankBonus,
                        baseGoal: store.todayGoal,
                        adaptedGoal: store.adaptedTodayGoal
                    )
                    .presentationCompactAdaptation(.popover)
                }
            }
            // Замка «Банк калорий» здесь больше нет: в центре первого экрана
            // новый человек видел платную функцию, смысла которой ещё не знал,
            // и приложение выглядело закрытым. Про банк рассказывают экран
            // плана и экран оплаты — там, где о нём уже спрашивают.

            // Совет дня — одно сообщение на основе данных пользователя.
            if let advice = dailyAdvice, advice != .none {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(advice.title)
                            .font(.app(.subheadline, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text(advice.body)
                            .font(.app(.caption))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 2)
                .accessibilityIdentifier("dailyAdvice")
            }

        }
    }

    /// Строка про сваренное: что именно и что с этим делать.
    /// Съеденное за день: приёмы пищи по порядку, в каждом свои строки.
    @ViewBuilder
    var diarySections: some View {
        if store.todayEntries.isEmpty, let usual = store.usualMealNow() {
            // В пустой день вместо пустоты — то, что обычно едят в этот час,
            // и запись одним касанием. Значок лотка ничего не предлагал, а
            // день, который человек начинает с привычного завтрака, не должен
            // начинаться с поиска.
            Section {
                UsualMealOffer(usual: usual,
                               period: MealPeriod.period(for: Date())) {
                    _ = MealReminders.logUsualMeal(period: MealPeriod.period(for: Date()), store: store)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
            }
        } else if store.todayEntries.isEmpty {
        Section {
            // Пустой лоток и есть сообщение: подпись «пока ничего не
            // добавлено» повторяла его словами, а читать её было незачем.
            Image(systemName: "tray")
                .font(.app(.largeTitle))
                .foregroundStyle(.secondary)
                .accessibilityLabel("Пока ничего не добавлено")
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
            .listRowBackground(Color.clear)
        }
        .listSectionSeparator(.hidden)
        } else {
        ForEach(store.groupedTodayEntries, id: \.period) { group in
            Section {
                ForEach(group.entries) { entry in
                    NavigationLink(value: entry) {
                        EntryRow(entry: entry,
                                 micros: store.notableMicronutrients(for: entry),
                                 offersVitamins: store.offersVitamins(named: entry.composition.map(\.name)),
                                 partTraits: { store.foodNamed($0)?.traits ?? [] })
                    }
                    // Копия первой: на полном свайпе срабатывает
                    // первая кнопка, а повторить съеденное просят
                    // чаще, чем дописать в него забытое.
                    .swipeActions(edge: .leading) {
                        Button {
                            // Копия получает время «сейчас», а секции
                            // отсортированы по последней записи — значит
                            // приём пищи переезжает в начало списка.
                            // Без явной анимации это происходит рывком:
                            // половина экрана переставляется за кадр,
                            // и понять, что произошло, невозможно.
                            // Явной транзакцией, а не `withAnimation`:
                            // мутация стора уезжает в наблюдение, и
                            // из обработчика свайпа анимация до
                            // списка доходила не всегда — строка
                            // появлялась рывком.
                            var transaction = Transaction(animation: .snappy)
                            transaction.disablesAnimations = false
                            withTransaction(transaction) {
                                // Вместе с составом: приём из пяти
                                // продуктов, скопированный одной
                                // строкой без начинки, теряет и
                                // разбор дня по категориям, и
                                // возможность дополнить его потом.
                                store.add(name: entry.name, calories: entry.calories,
                                          macros: entry.macros, grams: entry.grams,
                                          components: entry.components)
                            }
                            // И показываем, куда она встала: копия
                            // получает время «сейчас» и уходит в
                            // текущий приём, а он может быть в
                            // другом конце дневника.
                            // Самая свежая запись — последняя:
                            // день теперь идёт по порядку.
                            copiedEntryID = store.todayEntries.max { $0.date < $1.date }?.id
                        } label: {
                            Image(systemName: "plus.square.on.square")
                        }
                        .tint(.blue)
                        .accessibilityIdentifier("copyEntry")
                        .accessibilityLabel("Повторить приём")
                        // Дополнить — это правка того же приёма, а не
                        // добавление нового: приём пищи хранится одной
                        // строкой с итогами, поэтому он становится
                        // первой строкой черновика, а новое досыпается.
                        // Значок карандаша об этом и говорит; плюс
                        // читался как «добавить ещё один приём».
                        Button {
                            appendingTo = entry
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .tint(.indigo)
                        .accessibilityLabel("Дополнить приём")
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            store.delete(entry: entry)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("Удалить")
                    }
                }
            } header: {
                // Справа время приёма, а не его калории.
                //
                // У приёма из одной записи число повторялось дважды подряд —
                // в заголовке и в самой строке. Время же из строки ушло сюда:
                // во сколько ел — свойство приёма, а не куска еды.
                HStack(alignment: .firstTextBaseline) {
                    Text(LocalizedStringKey(group.period.rawValue))
                        .font(.app(.subheadline, weight: .semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(verbatim: MealPeriod.time(of: group.entries))
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .textCase(nil)
            }
        }
        }
    }
}

/// Шаги капсулой в тулбаре, напротив плюса.
///
/// Раньше это была целая карточка между макросами и неделей. На шаги смотрят
/// мельком — хватит числа и кольца размером с кнопку, — а место на экране
/// нужнее кольцу, карточкам и неделе. Строка тулбара после того, как убрали
/// заголовок, всё равно пустовала.
private struct StepsChip: View {
    var store: StepStore
    var onTap: () -> Void

    @AppStorage(AppAccent.defaultsKey) private var appAccent = AppAccent.system.rawValue

    private var progress: Double {
        guard store.stepGoal > 0 else { return 0 }
        return min(Double(store.stepsToday) / Double(store.stepGoal), 1.0)
    }

    // Цвет акцента, выбранный в настройках: кольцо шагов у него единственное
    // без своего смысла у цвета. Цель взята — зелёным, как «в норме» везде.
    //
    // Акцент берётся через `@AppStorage`, а не прямым чтением `UserDefaults`:
    // обычное чтение SwiftUI не отслеживает, и пешеход оставался прежнего
    // цвета до тех пор, пока экран не пересоберут целиком — потянув список
    // вниз. Цвет менялся, а значок об этом не знал.
    private var tint: Color {
        progress >= 1 ? ProgressRing.kcalColors[0]
                      : (AppAccent(rawValue: appAccent) ?? .system)
                            .color(focus: AppAccent.storedFocusMacro)
    }

    var body: some View {
        Button {
            // Без доступа к «Здоровью» считать нечего — нажатие просит доступ.
            if store.isAuthorized { onTap() } else { store.requestAuthorization() }
        } label: {
            HStack(spacing: 7) {
                if store.isAuthorized {
                    // Пешеход и число — без кольца вокруг.
                    //
                    // Кольцо шагов стояло в двух точках от кольца калорий, и
                    // два кольца в шапке читались как одно целое с главным.
                    // Долю от цели оно к тому же показывало тремя точками
                    // линии: угадать по ней число нельзя, а само число стоит
                    // рядом. Цвет остался — зелёный, когда цель взята.
                    Image(systemName: "figure.walk")
                        .font(.app(size: 17, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(height: 32)
                    // Число обычным цветом: в цвете акцента кольцо и пешеход,
                    // а цифра читается лучше нейтральной.
                    //
                    // Кеглем мельче подписи и целиком: когда в шапку уезжает
                    // кольцо, пилюле становится тесно, и «2,350» обрезалось
                    // до «2,3». Урезанное число хуже, чем мелкое: мелкое
                    // читается, а урезанное врёт.
                    Text(store.stepsToday.formatted())
                        .font(.app(.footnote, weight: .semibold))
                        .monospacedDigit()
                        .fixedSize()
                        .foregroundStyle(Color.primary)
                } else {
                    // Без доступа — один пешеход, без подписи. Слово рядом со
                    // значком не добавляло смысла, зато отнимало ширину у
                    // даты в шапке и обрезалось само: «Ste…». Что это такое,
                    // пешеход говорит и молча, а для голоса есть подпись
                    // доступности ниже.
                    Image(systemName: "figure.walk")
                        .font(.app(.subheadline, weight: .medium))
                        .frame(height: 32)
                }
            }
            .foregroundStyle(store.isAuthorized ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .padding(.leading, 2)
            .padding(.trailing, 6)
        }
        // Своим стилем, а не системным: у кнопки в шапке подсветка нажатия
        // повторяет форму стеклянной подложки, а подложку здесь сняли — и
        // вместо неё под пальцем проступал прямоугольник по размеру надписи.
        .buttonStyle(.plain)
        .contentShape(.capsule)
        .accessibilityLabel(store.isAuthorized
            ? Text(verbatim: store.stepsToday.formatted() + " " + String(localized: "шагов из \(store.stepGoal.formatted())"))
            : Text("Подключить шаги"))
        .accessibilityIdentifier("stepsChip")
    }
}

private struct CalorieBankPopover: View {
    let bonus: Int
    let baseGoal: Int
    let adaptedGoal: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Недельный баланс")
                .font(.app(.headline))
            Text(bonus > 0
                 ? "На этой неделе ты сэкономил калории — они распределены по оставшимся дням."
                 : "На этой неделе был перерасход — норма сегодня снижена.")
                .font(.app(.caption))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 8) {
                HStack {
                    Text("Базовая норма")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(baseGoal) ккал")
                }
                HStack {
                    Text("Из банка недели")
                        .foregroundStyle(bonus > 0 ? .green : .orange)
                    Spacer()
                    Text(bonus > 0 ? "+\(bonus)" : "\(bonus)")
                        .foregroundStyle(bonus > 0 ? .green : .orange)
                        .fontWeight(.medium)
                }
                Divider()
                HStack {
                    Text("Итого сегодня")
                        .fontWeight(.semibold)
                    Spacer()
                    Text("\(adaptedGoal) ккал")
                        .fontWeight(.semibold)
                }
            }
            .font(.app(.caption))
        }
        .padding(.horizontal)
        .padding(.vertical, 25)
        .frame(minWidth: 240)
    }
}

#Preview {
    let container = try! ModelContainer(
        for: FoodEntry.self, FoodItem.self, WeightEntry.self, GoalRecord.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    ContentView(store: CalorieStore(context: container.mainContext), stepStore: StepStore())
}

/// Насколько список стянут вниз прямо сейчас.
///
/// Отдельным наблюдаемым объектом, а не состоянием экрана: писать его будет
/// «Сегодня», а читать — только кольцо, и тогда кадр жеста перерисовывает
/// кольцо, а не весь экран.
@Observable
final class RingPull {
    var offset: CGFloat = 0
}

/// Кольцо, которое поворачивается за пальцем, пока список тянут вниз.
///
/// Своей вьюхой, а не частью «Сегодня», ради одного: положение пальца меняется
/// на каждом кадре жеста, и пока это состояние лежало в `ContentView`, каждый
/// кадр перестраивал весь экран — кольцо, карточку макросов, полоски приёмов,
/// голодания, плана и недели. Полоска недели и расписание приёмов считаются
/// заново примерно за миллисекунду, и на жесте это чувствовалось подлагиванием.
/// Теперь на кадр перерисовывается только кольцо.
private struct PullableRing: View {
    let consumed: Int
    let goal: Int
    let macros: Macros
    let proteinTarget: Double?
    let fatTarget: Double?
    let carbsTarget: Double?
    let spinTicket: Int
    let pull: RingPull
    var onOpen: () -> Void
    /// Кольцо ушло под шапку — там его подменяет миниатюра.
    var onAway: (Bool) -> Void = { _ in }
    /// Появление при запуске: кольцо подхватывает знак заставки.
    var entrance: RingEntrance = .none
    /// Экран закрыт листом — геометрия врёт, и слушать её нельзя.
    var isCovered: Bool = false

    /// Доросло ли кольцо до своего размера.
    @State private var grown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Размер, с которого кольцо начинается: тот, на котором заставка
    /// закончила. Считается из её чисел, чтобы два движения сошлись, даже
    /// если знак на заставке когда-нибудь станет другого размера.
    private static let splashScale = BrandLockup.markSize * BrandLockup.exitScale / ProgressRing.fullSize

    /// Кольцо ещё в размере знака заставки.
    private var atSplashSize: Bool {
        switch entrance {
        case .none:    return false
        case .waiting: return true
        case .grow:    return !grown
        }
    }

    @State private var isAway = false
    /// Насколько кольцо уже ушло под шапку, 0…1.
    ///
    /// Нужно ради одного: знак не должен исчезать рывком. Пока он виден
    /// целиком — это кольцо дня; когда уезжает — он на глазах сжимается до
    /// размера миниатюры, которая его там и подхватывает. Так два кольца
    /// читаются как одно, переехавшее в шапку, а не как подмена.
    @State private var away: CGFloat = 0

    /// Ниже этой линии кольцо ещё видно из-под шапки.
    ///
    /// Шапка с двумя строками заголовка и строка состояния над ней — около ста
    /// сорока точек. Считать точно неоткуда: глобальная система координат про
    /// безопасные области ничего не знает, а ошибка в десяток точек меняет
    /// только момент подмены, не её саму.
    private static let barBottom: CGFloat = 140

    var body: some View {
        GeometryReader { geometry in
            // Кольцо адаптивно: 55% ширины экрана, минимум 220, максимум 320 точек.
            // На маленьких экранах (SE) — 220, на больших (Pro Max) — до 320.
            let ringSize = min(max(geometry.size.width * 0.55, 220), 320)
            ProgressRing(
                consumed: consumed,
                goal: goal,
                macros: macros,
                proteinTarget: proteinTarget,
                fatTarget: fatTarget,
                carbsTarget: carbsTarget,
                spinTicket: spinTicket,
                pullAngle: Double(pull.offset) * 1.4,
                onOpen: onOpen,
                fills: true
            )
            .frame(width: ringSize, height: ringSize)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top)
        }
        // Вырастает на месте знака заставки — и ровно пока та уходит.
        //
        // Той же кривой и за то же время: знак подрастает и тает, кольцо с
        // его размера растёт и проявляется, и на экране это одно движение.
        // Пружина здесь не годится, какой бы живой ни была: она длится
        // дольше ухода, и кольцо доезжало уже по пустому экрану.
        .scaleEffect(atSplashSize ? Self.splashScale : 1)
        .opacity(atSplashSize ? 0 : 1)
        .onChange(of: entrance) { _, phase in
            guard phase == .grow, !grown else { return }
            // «Уменьшение движения» заставку и так выключает; проверка здесь
            // на случай, если её включили, пока приложение работает.
            if reduceMotion {
                grown = true
            } else {
                withAnimation(.easeOut(duration: BrandLockup.exitDuration)) { grown = true }
            }
        }
        // Сжимается к верхней кромке, а не к центру: знак будто втягивается
        // в шапку, куда и уезжает. До трети роста, дальше — миниатюра.
        .scaleEffect(1 - 0.34 * away, anchor: .top)
        .opacity(1 - 0.35 * away)
        // Покой — первое положение, которое увидели.
        .background {
            GeometryReader { geometry in
                Color.clear
                    .onChange(of: geometry.frame(in: .global).minY, initial: true) { _, y in
                        guard !isCovered else { return }
                        let height = max(geometry.size.height, 1)
                        // Доля ухода: ноль, пока низ кольца ниже шапки;
                        // единица, когда оно скрылось целиком.
                        let hidden = (Self.barBottom - y) / height
                        away = min(max(hidden, 0), 1)
                        let away = y + geometry.size.height < Self.barBottom
                        if away != isAway {
                            isAway = away
                            onAway(away)
                        }
                    }
            }
        }
    }
}
