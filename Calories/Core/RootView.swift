import SwiftUI
import WidgetKit

struct RootView: View {
    var store: CalorieStore
    var stepStore: StepStore
    var purchases: PurchaseService
    @State private var selectedTab = 0
    @AppStorage("onboarding_completed") private var onboardingCompleted = false
    @AppStorage("app_theme") private var appTheme = AppTheme.system.rawValue
    @AppStorage("app_font") private var appFont = AppFont.system.rawValue
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $selectedTab) {
            ContentView(store: store, stepStore: stepStore)
                .tabItem { Label("Сегодня", systemImage: "book.fill") }
                .tag(0)

            NavigationStack {
                MyFoodView(store: store)
            }
            .tabItem { Label("Еда", systemImage: "fork.knife") }
            .tag(1)

            NavigationStack {
                BodyView(store: store)
            }
            .tabItem { Label("Тело", systemImage: "figure.arms.open") }
            .tag(2)
        }
        .fullScreenCover(isPresented: Binding(
            get: { !onboardingCompleted },
            set: { _ in }
        )) {
            OnboardingView(store: store)
        }
        .environment(purchases)
        // Всё «сегодняшнее» лежит в кэшах стора и после полуночи устаревает молча.
        // Ловим оба случая: приложение подняли из фона и сутки сменились прямо на экране.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                store.refreshIfDayChanged()
                stepStore.fetchAll()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            store.refreshIfDayChanged()
        }
        .preferredColorScheme(AppTheme(rawValue: appTheme)?.colorScheme)
        // Начертание задаётся один раз на корне и наследуется всем деревом,
        // поэтому размеры и Dynamic Type нигде не приходится трогать.
        .fontDesign(AppFont(rawValue: appFont)?.design ?? .default)
        .onChange(of: store.consumedToday) { _, _ in
            WidgetCenter.shared.reloadTimelines(ofKind: "CaloriesWidget")
        }
        .onChange(of: store.adaptedTodayGoal) { _, _ in
            WidgetCenter.shared.reloadTimelines(ofKind: "CaloriesWidget")
        }
    }
}
