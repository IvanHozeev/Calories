import SwiftUI

/// Питание: расписание приёмов, кашрут, посты и праздники.
///
/// В профиле, а не в настройках приложения: это про режим человека, как
/// подъём и отбой, а не про то, как приложение выглядит и куда кладёт копии.
struct NutritionSection: View {
    var store: CalorieStore

    var body: some View {
        Section {
            NavigationLink {
                MealScheduleSheet(
                    entries: store.todayEntries.map { (date: $0.date, calories: $0.calories) },
                    dailyGoal: store.adaptedTodayGoal,
                    settings: .shared,
                    store: store,
                    isEmbedded: true
                )
            } label: {
                settingLabel("Приёмы пищи", systemImage: "clock")
            }
            .accessibilityIdentifier("openMealSchedule")

            // Кашрут здесь же, по той же причине, что и расписание: это про то,
            // как человек ест, а не про то, как приложение выглядит. Своим
            // экраном, а не строками прямо тут: обычай выбирают однажды.
            NavigationLink {
                KosherView()
            } label: {
                settingLabel("Кашрут", systemImage: "circle.lefthalf.filled")
            }
            .accessibilityIdentifier("openKosher")

            // Посты и праздники — рядом с кашрутом: та же тема, и включает
            // её тот же человек. Выключено по умолчанию: обычаи различаются.
            Toggle(isOn: Binding(get: { KosherSettings.shared.observesCalendar },
                                 set: { KosherSettings.shared.observesCalendar = $0 })) {
                settingLabel("Посты и праздники", systemImage: "moon.stars")
            }
            .accessibilityIdentifier("observesJewishCalendar")
        } header: {
            // Заголовок отдельным блоком, а не строкой в `Section("…")`:
            // так к нему можно привесить слежение, по которому имя секции
            // переезжает в шапку при прокрутке.
            Text("Питание")
                .tracksSectionHead(String(localized: "Питание"))
        } footer: {
            explain("Посты и праздники еврейского календаря: за три дня до поста приложение предложит его отметить, в неделю праздника — перенести на него рефид. Само оно ничего не отмечает.").map { Text($0) }
        }
    }
}
