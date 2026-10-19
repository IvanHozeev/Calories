import SwiftUI
import SwiftData

struct ContentView: View {
    var store: CalorieStore
    var stepStore: StepStore
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
    @State private var showingActivity = false
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
    /// Крупное кольцо уехало под шапку — в шапке его подменяет миниатюра.
    @State private var ringIsAway = false
    /// Высота списка и то, сколько у него снизу занято таббаром. Из этих
    /// двух считается, сколько места осталось кольцу.
    @State private var listHeight: CGFloat = 0
    @State private var listBottomInset: CGFloat = 0

    /// Высота первого экрана: ровно видимая часть списка.
    ///
    /// Полоска и плитки берут своё, остаток достаётся кольцу — поэтому блок
    /// кончается у таббара, а дневник начинается со следующего экрана.
    /// Нижняя граница не для красоты: на маленьком экране с крупным шрифтом
    /// без неё кольцо схлопнулось бы в точку.
    private var summaryHeight: CGFloat {
        max(listHeight - listBottomInset - 8, 420)
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
        case .meal, .camera:
            entryAction = action
            showingAdd = true
        }
    }

    /// Копия, к которой надо прокрутить список. Сбрасывается сразу после
    /// прокрутки: это событие, а не состояние.
    @State private var copiedEntryID: UUID?

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
                        // Ровно видимая часть списка: только так кольцу
                        // достаётся весь остаток. С «не меньше» список
                        // считает высоту блока по содержимому, и кольцо
                        // получает свой минимум вместо свободного места.
                        .frame(height: summaryHeight)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 16, trailing: 16))
                }
                .listSectionSeparator(.hidden)

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

                // Стекло — только строкам дневника.
                //
                // На списке целиком оно побеждало прозрачный фон, заданный
                // строке: первый экран получал белую плашку во всю свою
                // высоту, и в светлой теме под плитками торчал её край.
                diarySections
                    .glassRow()
            }
            .listStyle(.insetGrouped)
            .scrollIndicators(.hidden)
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
            .navigationDestination(isPresented: $showingPlan) {
                PlanView(store: store)
            }
            .navigationTitle("Сегодня")
            // Какое именно сегодня. «Сегодня» — слово без числа, а записи
            // в приложении о днях, и день недели с датой человек держит
            // в голове сам ровно до первого раза, когда ошибётся.
            .navigationSubtitle(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))
            // Крупным, но в самой шапке: большой заголовок над содержимым
            // уезжает прокруткой, а «Сегодня» с датой нужны и после неё.
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar {
                // Объединяем миниатюру кольца и меню плюса в один слот тулбара,
                // чтобы они управляли общим пространством и анимировались вместе.
                ToolbarItem(placement: .topBarTrailing) {
                    HStack {
                        if ringIsAway {
                            ProgressRing(
                                consumed: store.consumedToday,
                                goal: store.adaptedTodayGoal,
                                macros: store.macrosToday,
                                proteinTarget: store.proteinTarget,
                                fatTarget: store.fatTarget,
                                carbsTarget: store.carbsTarget,
                                miniature: 32,
                                onOpen: {
                                    entryAction = nil
                                    showingAdd = true
                                }
                            )
                            .accessibilityHidden(true)
                            .transition(.scale(scale: 0.2).combined(with: .opacity))
                        }
                        
                        Menu {
                            if GeminiVisionService.isConfigured {
                                Button {
                                    entryAction = .camera
                                    showingAdd = true
                                } label: {
                                    Label("Снять еду", systemImage: "camera")
                                }
                            }
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
                                Label("Новое блюдо", systemImage: "frying.pan")
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
                            listHeight = height
                        }
                        // Таббар вычитаем по безопасной области, а не числом:
                        // высота списка приходит вместе с местом под ним, и
                        // без этого последний ряд плиток уезжал под таббар.
                        .onChange(of: geometry.safeAreaInsets.bottom, initial: true) { _, inset in
                            listBottomInset = inset
                        }
                }
            }
            .fullScreenCover(isPresented: $showingAdd, onDismiss: { entryAction = nil }) {
                AddEntryView(store: store, initialAction: entryAction,
                             onFinish: { showingAdd = false })
            }
            .fullScreenCover(item: $appendingTo) { entry in
                AddEntryView(store: store, appendingTo: entry,
                             onFinish: { appendingTo = nil })
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
                    .presentationDetents([.height(300)])
                case .newFood:
                    NewFoodSheet(store: store)
                        .presentationDetents([.large])
                case .newDish:
                    NewDishSheet(store: store)
                        .presentationDetents([.large])
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
            .navigationDestination(isPresented: $showingActivity) {
                ActivityView(store: store)
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
            }
            }
        }
    }
}

extension ContentView {
    /// Время приёма пищи: когда ел. Если записей несколько — от первой до
    /// последней, потому что приём редко укладывается в минуту.
    static func mealTime(_ entries: [FoodEntry]) -> String {
        let dates = entries.map(\.date).sorted()
        guard let first = dates.first, let last = dates.last else { return "" }
        let time = Date.FormatStyle.dateTime.hour().minute()
        let start = first.formatted(time)
        let end = last.formatted(time)
        return start == end ? start : "\(start) – \(end)"
    }
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
                      onSelect: { selectedHistoryDay = $0 },
                      onShowAll: { showingActivity = true })

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
                onAway: { ringIsAway = $0 }
            )
            // Кольцу — весь остаток: высоту блока задаёт экран, полоска и
            // плитки берут своё, остальное кольцу. Так не нужно знать ни
            // высоту полоски, ни число рядов — они меняются, а это нет.
            //
            // Но не меньше своего минимума: знак с крупным числом внутри —
            // главное на экране, и уступать место подсказке он не должен.
            // Если всё вместе не влезло, блок станет выше экрана, и дневник
            // начнётся чуть ниже — это дешевле раздавленного кольца.
            .frame(minHeight: 240, maxHeight: .infinity)
            // Немного воздуха сверху и снизу: знак берёт не весь остаток, а
            // остаток минус поля. Диаметр считается по меньшей стороне, так
            // что эти четырнадцать точек с каждой стороны и есть «чуть
            // поменьше» — и заодно кольцо перестаёт упираться в плитки.
            .padding(.vertical, 14)

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
                                      dailyGoal: store.adaptedTodayGoal) {
                        showingMealSchedule = true
                    }
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
                weightKg: store.weightKg,
                onOpen: { showingDayNutrition = true },
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
        if store.fastingHint() != nil { return true }
        if store.reviewIsDue, store.proposedGoal != nil { return true }
        if store.calorieBankBonus != 0 { return true }
        if !store.isPremium, store.plan == nil { return true }
        if store.profile == nil { return true }
        return !store.hasWeighedToday
    }

    /// Подсказки дня: голодание, недельный обзор, банк калорий, напоминание
    /// взвеситься.
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
    @ViewBuilder
    var dayHints: some View {
        VStack(spacing: 16) {
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
            if store.reviewIsDue, let proposal = store.proposedGoal {
                Button { showingActivity = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "calendar.badge.clock")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Недельный обзор")
                                .font(.app(.subheadline, weight: .medium))
                            Text(verbatim: String(format: String(localized: "Расчёт предлагает %lld ккал в день"), proposal))
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
            } else if !store.isPremium && store.plan == nil {
                Button { showingPaywall = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(.secondary)
                        Text("Банк калорий")
                            .foregroundStyle(.secondary)
                    }
                    .font(.app(.caption))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
            }

            if store.profile == nil {
                NavigationLink {
                    SettingsView(store: store)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "person.crop.circle.badge.questionmark")
                            .font(.app(.footnote))
                        Text("Заполните профиль, чтобы рассчитать цель")
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
            } else if !store.hasWeighedToday {
                Button {
                    todaySheet = .weight
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "scalemass")
                            .font(.app(.footnote))
                        Text("Не забудь взвеситься сегодня")
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
            }
        }
    }

    /// Съеденное за день: приёмы пищи по порядку, в каждом свои строки.
    @ViewBuilder
    var diarySections: some View {
        if store.todayEntries.isEmpty {
        Section {
            VStack(spacing: 8) {
                Image(systemName: "tray")
                    .font(.app(.largeTitle))
                    .foregroundStyle(.secondary)
                Text("Пока ничего не добавлено")
                    .foregroundStyle(.secondary)
            }
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
                                 micros: store.notableMicronutrients(for: entry))
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
                        .accessibilityLabel("Повторить")
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
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            store.delete(entry: entry)
                        } label: {
                            Image(systemName: "trash")
                        }
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
                    Text(verbatim: Self.mealTime(group.entries))
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

    private var progress: Double {
        guard store.stepGoal > 0 else { return 0 }
        return min(Double(store.stepsToday) / Double(store.stepGoal), 1.0)
    }

    // Цвет акцента, выбранный в настройках: кольцо шагов у него единственное
    // без своего смысла у цвета. Цель взята — зелёным, как «в норме» везде.
    private var tint: Color {
        progress >= 1 ? ProgressRing.kcalColors[0]
                      : AppAccent.current.color(focus: AppAccent.storedFocusMacro)
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
                    Text(store.stepsToday.formatted())
                        .font(.app(.subheadline, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.primary)
                } else {
                    Image(systemName: "figure.walk")
                        .font(.app(.subheadline, weight: .medium))
                    Text("Шаги")
                        .font(.app(.subheadline))
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

    /// Где кольцо стоит, когда список в покое.
    @State private var restingY: CGFloat?
    @State private var isAway = false

    /// Ниже этой линии кольцо ещё видно из-под шапки.
    ///
    /// Шапка с двумя строками заголовка и строка состояния над ней — около ста
    /// сорока точек. Считать точно неоткуда: глобальная система координат про
    /// безопасные области ничего не знает, а ошибка в десяток точек меняет
    /// только момент подмены, не её саму.
    private static let barBottom: CGFloat = 140

    var body: some View {
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
        .padding(.top)
        // Покой — первое положение, которое увидели.
        .background {
            GeometryReader { geometry in
                Color.clear
                    .onChange(of: geometry.frame(in: .global).minY, initial: true) { _, y in
                        let away = y + geometry.size.height < Self.barBottom
                        if away != isAway {
                            isAway = away
                            onAway(away)
                        }
                        guard let resting = restingY else {
                            restingY = y
                            return
                        }
                        pull.offset = max(0, y - resting)
                    }
            }
        }
    }
}
