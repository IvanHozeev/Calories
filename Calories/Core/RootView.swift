import SwiftUI

struct RootView: View {
    @ObservedObject var store: CalorieStore
    @ObservedObject var stepStore: StepStore
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            ContentView(store: store)
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

            StepsView(store: stepStore)
                .tabItem { Label("Шаги", systemImage: "figure.walk") }
                .tag(3)
        }
    }
}
