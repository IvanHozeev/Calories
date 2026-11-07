import SwiftUI
import WidgetKit

struct RootView: View {
    var store: CalorieStore
    var stepStore: StepStore
    var purchases: PurchaseService
    @State private var selectedTab = 0
    private let quickActions = QuickActionRouter.shared
    @AppStorage("onboarding_completed") private var onboardingCompleted = false
    @AppStorage("app_theme") private var appTheme = AppTheme.system.rawValue
    @AppStorage("app_font") private var appFont = AppFont.system.rawValue
    @AppStorage("app_text_size") private var appTextSize = AppTextSize.normal.rawValue
    @AppStorage(AppAccent.defaultsKey) private var appAccent = AppAccent.system.rawValue
    @Environment(\.scenePhase) private var scenePhase
    /// Лаунч-скрин статичен — анимировать его iOS не даёт. Поэтому поверх первого
    /// кадра лежит его точная копия, которая продолжает знак движением и тает.
    /// Не показываем при «Уменьшении движения» — анимация ради анимации там
    /// как раз то, от чего человек просил избавить, — и когда её выключили
    /// настройкой (так делают UI-тесты: заставка перехватывала первые нажатия).
    @State private var showingSplash = !UIAccessibility.isReduceMotionEnabled
        && UserDefaults.standard.object(forKey: "show_launch_splash") as? Bool ?? true
    /// Кольцо дня продолжает знак заставки: ждёт под ней и вырастает, когда
    /// она уходит. Без заставки расти неоткуда — кольцо сразу на месте.
    @State private var ringEntrance: RingEntrance = !UIAccessibility.isReduceMotionEnabled
        && UserDefaults.standard.object(forKey: "show_launch_splash") as? Bool ?? true
        ? .waiting : .none

    /// Вкладки отдельным свойством: вместе с модификаторами тела компилятор
    /// перестаёт справляться с выражением и валит сборку по таймауту.
    private var tabs: some View {
        TabView(selection: $selectedTab) {
            // Кольцо тоже парой: выбранная вкладка — дуги залитые,
            // невыбранная — полые, один их контур. Системным символам такую
            // пару даёт сама система, нашему рисунку её пришлось нарисовать —
            // обе формы делает `Tools/brand_assets.swift` из одних и тех же
            // дуг, поэтому они совпадают по габаритам и перетекают без рывка.
            Tab(value: 0) {
                ContentView(store: store, stepStore: stepStore, ringEntrance: ringEntrance)
            } label: {
                Label("Сегодня", image: selectedTab == 0 ? "TodayTab" : "TodayTabOutline")
            }

            // Выбранная вкладка — залитым начертанием, невыбранная —
            // контурным. Это та самая пара, ради которой система играет
            // переход между символами: одно перетекает в другое само, и
            // выглядит это как в её собственных приложениях. Со значком
            // в одном начертании анимации нет вовсе — не потому, что мы её
            // не попросили, а потому, что перетекать не во что.
            Tab(value: 1) {
                NavigationStack {
                    ProfileView(store: store)
                }
            } label: {
                Label("Профиль", systemImage: selectedTab == 1 ? "face.dashed.fill" : "face.dashed")
            }

            // Поиск — системной ролью, а не обычной вкладкой: тогда система
            // сама ставит его отдельно справа и превращает таббар в строку
            // поиска, когда его открывают. Внутри — прежний экран «Еда»: свои
            // продукты, блюда и база с фильтром по категориям.
            // «Рацион», а не «Поиск»: за вкладкой лежит весь список еды —
            // свои продукты, блюда и база, — а поиск по ним лишь один из
            // способов её найти. Экран внутри назывался так с самого начала,
            // и вкладка с ним спорила.
            Tab(value: 3, role: .search) {
                NavigationStack {
                    MyFoodView(store: store)
                }
            } label: {
                Label("Рацион", systemImage: selectedTab == 3 ? "fork.knife.circle.fill" : "fork.knife.circle")
            }
        }
        // Один цвет на всё приложение, выбранный в настройках.
        // Цвет спрашиваем с оглядкой на день: при выборе «По макросу» он ведёт
        // к тому, что ещё не закрыто.
        .tint((AppAccent(rawValue: appAccent) ?? .system).color(focus: store.focusMacro))
        .fullScreenCover(isPresented: Binding(
            get: { !onboardingCompleted },
            set: { _ in }
        )) {
            OnboardingView(store: store, stepStore: stepStore)
        }
        .overlay {
            if showingSplash {
                SplashView(onLeaving: { ringEntrance = .grow }) {
                    showingSplash = false
                }
                    // Касания проходят насквозь: заставка — украшение, а не
                    // экран, и ждать её конца, чтобы нажать, человек не должен.
                    .allowsHitTesting(false)
            }
        }
    }

    var body: some View {
        tabs
        .environment(purchases)
        // Меню на иконке пересобираем на каждом подъёме: камера в нём появляется
        // только вместе с ключом, а его вводят прямо во время работы приложения.
        .task {
            quickActions.refreshShortcutItems()
            // Бандл могли купить в GymLogger, пока нас тут не было.
            store.refreshSharedEntitlements()
            store.refreshGymState()
        }
        .onChange(of: quickActions.pending) { _, action in
            guard action != nil else { return }
            // Онбординг висит фулскрин-кавером поверх табов. Подниматься из-под него
            // некуда, поэтому до его конца нажатие на иконке просто теряем.
            guard onboardingCompleted else {
                quickActions.pending = nil
                return
            }
            selectedTab = 0
        }
        // Всё «сегодняшнее» лежит в кэшах стора и после полуночи устаревает молча.
        // Ловим оба случая: приложение подняли из фона и сутки сменились прямо на экране.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                store.refreshIfDayChanged()
                store.refreshSharedEntitlements()
                store.refreshGymState()
                stepStore.fetchAll()
                quickActions.refreshShortcutItems()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            store.refreshIfDayChanged()
        }
        .preferredColorScheme(AppTheme(rawValue: appTheme)?.colorScheme)
        // Начертание задаётся один раз на корне и наследуется всем деревом,
        // поэтому размеры и Dynamic Type нигде не приходится трогать.
        // У подключённого шрифта системного дизайна нет, и применять его
        // нельзя: `.fontDesign` подменяет им любой свой шрифт в дереве.
        .fontDesign((AppFont(rawValue: appFont) ?? .system).design)
        // Шапку рисует UIKit, и начертание с корня до неё не доходит: его
        // приходится отдавать ей отдельно — при запуске и после каждой смены.
        .task(id: appFont) { NavigationBarFont.apply() }
        .task(id: appTextSize) { NavigationBarFont.apply() }
        // Смена начертания меняет ширину каждой строки, а значит и всю раскладку.
        // Без анимации интерфейс перескакивает; с ней текст переезжает плавно.
        .animation(.easeInOut(duration: 0.25), value: appFont)
        // Анимации на смену размера здесь нет намеренно: наложенная на весь корень,
        // она гоняет транзакцию по всему дереву вместе со стеком навигации, и экран
        // выбрасывало назад прямо во время перетаскивания ползунка.
        .modifier(AppTextSizeModifier(size: AppTextSize(rawValue: appTextSize) ?? .normal))
        // Макросы тоже: виджет макросов обновлялся только по своему
        // пятнадцатиминутному расписанию и отставал от записанной еды.
        .onChange(of: store.consumedToday) { _, _ in
            WidgetCenter.shared.reloadTimelines(ofKind: "CaloriesWidget")
            WidgetCenter.shared.reloadTimelines(ofKind: "MacrosWidget")
            // И приём пищи: съеденное меняет то, сколько осталось на ближайший.
            WidgetCenter.shared.reloadTimelines(ofKind: "CaloriesMealWidget")
        }
        .onChange(of: store.adaptedTodayGoal) { _, _ in
            WidgetCenter.shared.reloadTimelines(ofKind: "CaloriesWidget")
            WidgetCenter.shared.reloadTimelines(ofKind: "MacrosWidget")
            WidgetCenter.shared.reloadTimelines(ofKind: "CaloriesMealWidget")
        }
        // Первый запуск новой сборки: виджет мог нарисоваться раньше, чем
        // приложение впервые выложило расписание, и так и остался бы с пустым
        // ответом до полуночи.
        .task {
            store.publishMealsToWidget()
            WidgetCenter.shared.reloadTimelines(ofKind: "CaloriesMealWidget")
        }
        // Цвет акцента виджету шагов: он в своём процессе и настроек
        // приложения не видит, поэтому выбор кладётся в общие настройки группы.
        .onChange(of: appAccent, initial: true) { _, accent in
            UserDefaults(suiteName: CalorieStore.appGroup)?.set(accent, forKey: "widget_accent")
            WidgetCenter.shared.reloadTimelines(ofKind: "StepsWidget")
        }
    }
}
