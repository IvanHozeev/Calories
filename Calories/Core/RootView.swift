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

    /// Вкладки отдельным свойством: вместе с модификаторами тела компилятор
    /// перестаёт справляться с выражением и валит сборку по таймауту.
    private var tabs: some View {
        TabView(selection: $selectedTab) {
            Tab("Сегодня", image: "TodayTab", value: 0) {
                ContentView(store: store, stepStore: stepStore)
            }

            Tab("Профиль", systemImage: "person.crop.circle", value: 1) {
                NavigationStack {
                    BodyView(store: store)
                }
            }

            // Своя вкладка, а не шестерёнка в тулбаре «Профиля»: после ухода
            // «Еды» внизу осталось две вкладки, а в настройки ходят сами по себе.
            Tab("Настройки", systemImage: "gearshape", value: 2) {
                NavigationStack {
                    SettingsView(store: store)
                        // Как на остальных вкладках: название и так в таббаре.
                        // Здесь, а не в самом экране: с «Сегодня» в него заходят
                        // переходом, и там заголовок нужен.
                        .navigationBarTitleDisplayMode(.inline)
                        .hiddenNavigationTitle()
                }
            }

            // Поиск — системной ролью, а не обычной вкладкой: тогда система
            // сама ставит его отдельно справа и превращает таббар в строку
            // поиска, когда его открывают. Внутри — прежний экран «Еда»: свои
            // продукты, блюда и база с фильтром по категориям.
            Tab("Поиск", systemImage: "magnifyingglass", value: 3, role: .search) {
                NavigationStack {
                    MyFoodView(store: store)
                }
            }
        }
        // Один цвет на всё приложение, выбранный в настройках.
        .tint((AppAccent(rawValue: appAccent) ?? .system).color)
        .fullScreenCover(isPresented: Binding(
            get: { !onboardingCompleted },
            set: { _ in }
        )) {
            OnboardingView(store: store, stepStore: stepStore)
        }
        .overlay {
            if showingSplash {
                SplashView { showingSplash = false }
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
        .task { quickActions.refreshShortcutItems() }
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
        }
        .onChange(of: store.adaptedTodayGoal) { _, _ in
            WidgetCenter.shared.reloadTimelines(ofKind: "CaloriesWidget")
            WidgetCenter.shared.reloadTimelines(ofKind: "MacrosWidget")
        }
        // Цвет акцента виджету шагов: он в своём процессе и настроек
        // приложения не видит, поэтому выбор кладётся в общие настройки группы.
        .onChange(of: appAccent, initial: true) { _, accent in
            UserDefaults(suiteName: CalorieStore.appGroup)?.set(accent, forKey: "widget_accent")
            WidgetCenter.shared.reloadTimelines(ofKind: "StepsWidget")
        }
    }
}
