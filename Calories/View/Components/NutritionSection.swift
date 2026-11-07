import SwiftUI
import SwiftData

/// Секция питания: переход к расписанию приёмов и кашруту.
struct NutritionSection: View {
    let todayEntries: [FoodEntry]
    let adaptedTodayGoal: Int
    let store: CalorieStore

    var body: some View {
        Section("Питание") {
            NavigationLink {
                MealScheduleSheet(
                    entries: todayEntries.map { (date: $0.date, calories: $0.calories) },
                    dailyGoal: adaptedTodayGoal,
                    settings: .shared,
                    store: store,
                    isEmbedded: true
                )
            } label: {
                Label("Приёмы пищи", systemImage: "clock")
            }
            .accessibilityIdentifier("openMealSchedule")

            // Кашрут здесь же, по той же причине, что и расписание: это про то,
            // как человек ест, а не про то, как приложение выглядит. Своим
            // экраном, а не строками прямо тут: обычай выбирают однажды.
            NavigationLink {
                KosherView()
            } label: {
                Label("Кашрут", systemImage: "circle.lefthalf.filled")
            }
            .accessibilityIdentifier("openKosher")
        }
    }
}
