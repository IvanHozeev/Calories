import SwiftUI
import WidgetKit

struct RootView: View {
    var store: CalorieStore
    var stepStore: StepStore
    @State private var selectedTab = 0
    @AppStorage("onboarding_completed") private var onboardingCompleted = false

    var body: some View {
        TabView(selection: $selectedTab) {
            ContentView(store: store, stepStore: stepStore)
                .tabItem { Label("Сегодня", systemImage: "book.fill") }
                .tag(0)

            NavigationStack {
                ProfileView(store: store)
            }
            .tabItem { Label("Профиль", systemImage: "person.fill") }
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
        .onChange(of: store.consumedToday) { _, _ in
            WidgetCenter.shared.reloadTimelines(ofKind: "CaloriesWidget")
        }
        .onChange(of: store.adaptedTodayGoal) { _, _ in
            WidgetCenter.shared.reloadTimelines(ofKind: "CaloriesWidget")
        }
    }
}
