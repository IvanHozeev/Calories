import SwiftUI
import WidgetKit

struct RootView: View {
    var store: CalorieStore
    var stepStore: StepStore
    @State private var selectedTab = 0
    @AppStorage("onboarding_completed") private var onboardingCompleted = false
    @AppStorage("app_theme") private var appTheme = AppTheme.system.rawValue

    var body: some View {
        TabView(selection: $selectedTab) {
            ContentView(store: store, stepStore: stepStore)
                .tabItem { Label("Сегодня", systemImage: "book.fill") }
                .tag(0)

            NavigationStack {
                ProgressDashboardView(store: store)
            }
            .tabItem { Label("Прогресс", systemImage: "chart.line.uptrend.xyaxis") }
            .tag(1)

            NavigationStack {
                MyFoodView(store: store)
            }
            .tabItem { Label("Еда", systemImage: "fork.knife") }
            .tag(2)
        }
        .fullScreenCover(isPresented: Binding(
            get: { !onboardingCompleted },
            set: { _ in }
        )) {
            OnboardingView(store: store)
        }
        .preferredColorScheme(AppTheme(rawValue: appTheme)?.colorScheme)
        .onChange(of: store.consumedToday) { _, _ in
            WidgetCenter.shared.reloadTimelines(ofKind: "CaloriesWidget")
        }
        .onChange(of: store.adaptedTodayGoal) { _, _ in
            WidgetCenter.shared.reloadTimelines(ofKind: "CaloriesWidget")
        }
    }
}
