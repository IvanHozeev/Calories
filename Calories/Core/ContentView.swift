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
    /// Где кольцо стоит, когда список в покое, и насколько его сейчас стянули вниз.
    @State private var ringRestingY: CGFloat?
    @State private var ringPull: CGFloat = 0

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
    /// Съеденное на момент, когда экран был виден. От него кольцо наливается,
    /// когда возвращаешься с добавленной едой.
    /// Цифры, на которых держим кольцо и полоски, пока открыт экран добавления.
    @State private var ringPinned: RingValues?
    /// Показывать ли заливку на выходе: ничего не добавили — отпускаем молча.
    @State private var ringRevealOnRelease = true
    @State private var mealSchedule = MealScheduleSettings()
    @State private var showingMealSchedule = false
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

    /// Открыт ли поверх «Сегодня» экран добавления: пока он открыт, съеденное
    /// меняется не на глазах, и базовую отметку трогать нельзя — иначе
    /// наливаться будет не от чего.
    private var isAddingFood: Bool {
        showingAdd || appendingTo != nil || todaySheet != nil
    }

    /// День по приёмам: окна, их калории и что уже съедено.
    private var todaySlots: [MealSchedule.Slot] {
        let now = Date()
        return MealSchedule.slots(.init(
            wake: mealSchedule.today(mealSchedule.wake, now: now),
            sleep: mealSchedule.today(mealSchedule.sleep, now: now),
            mealCount: mealSchedule.count,
            dailyGoal: store.adaptedTodayGoal,
            entries: store.todayEntries.map { (date: $0.date, calories: $0.calories) },
            now: now
        ))
    }

    /// Отпустить кольцо: если за время, пока экран был сверху, еды прибавилось,
    /// оно нальётся до новых цифр, иначе просто отпустится.
    private func releaseRing() {
        guard let pinned = ringPinned else { return }
        ringRevealOnRelease = RingValues(consumed: store.consumedToday, macros: store.macrosToday) != pinned
        ringPinned = nil
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 24) {
                        ProgressRing(
                            consumed: store.consumedToday,
                            goal: store.adaptedTodayGoal,
                            macros: store.macrosToday,
                            proteinTarget: store.proteinTarget,
                            fatTarget: store.fatTarget,
                            carbsTarget: store.carbsTarget,
                            spinTicket: ringSpinTicket,
                            pullAngle: Double(ringPull) * 1.4,
                            pinned: ringPinned,
                            revealOnRelease: ringRevealOnRelease,
                            onOpen: {
                                entryAction = nil
                                showingAdd = true
                            }
                        )
                        .padding(.top)
                        // Следим, насколько список стянут вниз: кольцо поворачивается
                        // за пальцем. Покой — первое положение, которое увидели.
                        .background {
                            GeometryReader { geometry in
                                Color.clear
                                    .onChange(of: geometry.frame(in: .global).minY, initial: true) { _, y in
                                        guard let resting = ringRestingY else {
                                            ringRestingY = y
                                            return
                                        }
                                        ringPull = max(0, y - resting)
                                    }
                            }
                        }

                        MacrosCard(
                            macros: store.macrosToday,
                            proteinTarget: store.proteinTarget,
                            fatTarget: store.fatTarget,
                            carbsTarget: store.carbsTarget,
                            weightKg: store.weightKg,
                            onOpen: { showingDayNutrition = true },
                            pinned: ringPinned?.macros,
                            revealOnRelease: ringRevealOnRelease
                        )
                        
                        // Строка вместо карточки: план виден и открывается,
                        // но не занимает полэкрана. Подробности — на его
                        // собственном экране, куда ведёт и она, и кольцо.
                        PlanStrip(
                            store: store,
                            onOpenPlan: { showingPlan = true },
                            onShowPaywall: { showingPaywall = true }
                        )

                        // Расписание приёмов — сразу под планом: план говорит,
                        // сколько есть за день, расписание — сколько прямо сейчас.
                        if mealSchedule.isEnabled, !todaySlots.isEmpty {
                            MealScheduleStrip(slots: todaySlots) { showingMealSchedule = true }
                        }

                        // Неделя — под планом: сегодня в кольце, план объясняет его
                        // норму, прошедшие дни следом. Над кольцом она первой ловила
                        // взгляд, хотя прошлые дни открывают изредка.
                        WeekStrip(weeks: store.weekStripWeeks(),
                                  onSelect: { selectedHistoryDay = $0 },
                                  onShowAll: { showingActivity = true })

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

                        // Единственный вход в план. Раньше их было два: компактная строка
                        // здесь и карточка на «Прогрессе» — с разным видом и разным
                        // содержанием, хотя вели в одно место.
                        // Отмеченный день голодания — не строка в настройках, а
                        // состояние сегодняшнего дня: пустой дневник в такой день
                        // должен читаться как «так и задумано», а не как провал.
                        // Голодание сегодня или в ближайшие три дня: подсказка к
                        // месту — за пару дней про кофе, накануне про соль и воду,
                        // в сам день про выход. Вся памятка — по нажатию.
                        if let hint = store.fastingHint() {
                            FastingStrip(hint: hint) { showingFasting = true }
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 16, trailing: 16))
                }
                .listSectionSeparator(.hidden)

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
                                             icons: store.foodCategories(forEntryNamed: entry.name).map(\.icon),
                                             micros: store.notableMicronutrients(for: entry))
                                }
                                // Дополнение первым: к приёму пищи добавляют чаще,
                                // чем копируют его целиком, а первая кнопка — та,
                                // что срабатывает на полном свайпе.
                                .swipeActions(edge: .leading) {
                                    // Дополнить, а не переписать: приём пищи хранится
                                    // одной строкой с итогами, разобрать его обратно
                                    // на продукты нельзя — поэтому он становится
                                    // первой строкой черновика, а новое досыпается.
                                    Button {
                                        appendingTo = entry
                                    } label: {
                                        Image(systemName: "plus.circle")
                                    }
                                    .tint(.indigo)
                                    Button {
                                        // Копия получает время «сейчас», а секции
                                        // отсортированы по последней записи — значит
                                        // приём пищи переезжает в начало списка.
                                        // Без явной анимации это происходит рывком:
                                        // половина экрана переставляется за кадр,
                                        // и понять, что произошло, невозможно.
                                        withAnimation(.snappy) {
                                            store.add(name: entry.name, calories: entry.calories,
                                                      macros: entry.macros, grams: entry.grams)
                                        }
                                    } label: {
                                        Image(systemName: "plus.square.on.square")
                                    }
                                    .tint(.blue)
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
                            // Итог по приёму пищи прямо в заголовке — иначе, чтобы понять,
                            // во сколько обошёлся обед, приходится складывать строки глазами.
                            // Тихо, как подписи недели и макросов: название
                            // приёма пищи — главное, итог рядом мельче.
                            HStack(alignment: .firstTextBaseline) {
                                Text(LocalizedStringKey(group.period.rawValue))
                                    .font(.app(.subheadline, weight: .semibold))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text(verbatim: "\(group.entries.reduce(0) { $0 + $1.calories }) \(String(localized: "ккал"))")
                                    .font(.app(.caption))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            .textCase(nil)
                        }
                    }
                }
            }
            .glassRow()
            .listStyle(.insetGrouped)
            .scrollIndicators(.hidden)
            // Отметка снимается в момент открытия добавления, а не по ходу дела:
            // запись еды и закрытие листа прилетают одной перерисовкой, и
            // отметка, идущая за съеденным, успевала стать новой раньше, чем
            // кольцо успевало от неё налиться.
            // Держим кольцо с момента открытия добавления: еда записывается,
            // пока экран сверху, и кольцо под ним успевало дойти до новых цифр.
            .onChange(of: isAddingFood) { _, adding in
                if adding {
                    ringPinned = RingValues(consumed: store.consumedToday, macros: store.macrosToday)
                } else {
                    releaseRing()
                }
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
            // Без заголовка: большой «Сегодня» спорил за внимание с кольцом,
            // а вкладка и так подписана в таббаре.
            .navigationBarTitleDisplayMode(.inline)
            .hiddenNavigationTitle()
            .toolbar {
                // Без общей стеклянной подложки: в строке остаются сами
                // элементы — кольцо шагов и плюс, — а не две пилюли над кольцом.
                ToolbarItem(placement: .topBarLeading) {
                    StepsChip(store: stepStore) { showingSteps = true }
                }
                .withoutSharedBackground()
                ToolbarItem(placement: .topBarTrailing) {
                    // Способы добавить еду выбираются здесь, до входа в лист.
                    // Раньше это меню жило внутри самого листа: чтобы отсканировать
                    // штрихкод, надо было сперва открыть экран добавления, а потом
                    // искать там ещё один плюс — два шага там, где нужен один.
                    // Сверху то, что избавляет от ручного ввода: штрихкод, когда
                    // есть упаковка, фото — когда её нет.
                    Menu {
                        if GeminiVisionService.isConfigured {
                            Button {
                                entryAction = .camera
                                showingAdd = true
                            } label: {
                                Label("Снять еду", systemImage: "camera")
                            }
                        }
                        // Сканер сразу, без экрана приёма пищи под ним: штрихкод
                        // сканируют, когда упаковка в руках, и записывают её же.
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
                        // Переехали сюда из плюса на экране приёма пищи: всё, чем
                        // что-то записывают, собрано в одном меню.
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
                        // Вес и замеры тут же: плюс на «Сегодня» отвечает на вопрос
                        // «записать сегодняшнее», а тело — такая же запись, как еда.
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
                        // Голодание — тоже отметка дня, а не настройка: его ставят
                        // на конкретную дату, и искать это в настройках не станут.
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
                .withoutSharedBackground()
            }
            .fullScreenCover(isPresented: $showingAdd, onDismiss: { entryAction = nil }) {
                AddEntryView(store: store, initialAction: entryAction,
                             onFinish: { showingAdd = false })
            }
            .fullScreenCover(item: $appendingTo) { entry in
                AddEntryView(store: store, appendingTo: entry,
                             onFinish: { appendingTo = nil })
            }
            .sheet(isPresented: $showingMealSchedule) {
                MealScheduleSheet(entries: store.todayEntries.map { (date: $0.date, calories: $0.calories) },
                                  dailyGoal: store.adaptedTodayGoal,
                                  settings: mealSchedule)
                    .presentationDetents([.large])
            }
            .sheet(item: $todaySheet) { sheet in
                switch sheet {
                case .weight:
                    AddWeightView(store: store)
                        .presentationDetents([.height(320)])
                case .quickCalories:
                    QuickCaloriesSheet { calories in
                        store.add(name: String(localized: "Приём пищи"), calories: calories)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        todaySheet = nil
                    }
                    .presentationDetents([.height(260)])
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
            .sheet(isPresented: $showingPaywall) {
                PaywallView(store: store)
            }
            // Действие с иконки может прилететь и до появления экрана (холодный
            // старт), и во время работы — забираем его в обоих случаях.
            .task { consumeQuickAction(quickActions.pending) }
            .onChange(of: quickActions.pending) { _, action in consumeQuickAction(action) }
            .onChange(of: store.consumedToday) { oldValue, newValue in
                let goal = store.adaptedTodayGoal
                if oldValue < goal && newValue >= goal {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
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
    private var tint: Color { progress >= 1 ? ProgressRing.kcalColors[0] : AppAccent.current.color }

    var body: some View {
        Button {
            // Без доступа к «Здоровью» считать нечего — нажатие просит доступ.
            if store.isAuthorized { onTap() } else { store.requestAuthorization() }
        } label: {
            HStack(spacing: 7) {
                if store.isAuthorized {
                    // Кольцо во всю высоту кнопки и пешеход внутри: одно число
                    // без значка не читалось как шаги.
                    ZStack {
                        Circle()
                            .stroke(tint.opacity(0.2), lineWidth: 3)
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.easeOut, value: progress)
                        Image(systemName: "figure.walk")
                            .font(.app(size: 15, weight: .semibold))
                            .foregroundStyle(tint)
                    }
                    .frame(width: 32, height: 32)
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
