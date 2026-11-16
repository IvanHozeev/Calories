import SwiftUI

/// Питание: расписание приёмов, кашрут, посты и праздники.
///
/// В профиле, а не в настройках приложения: это про режим человека, как
/// подъём и отбой, а не про то, как приложение выглядит и куда кладёт копии.
struct NutritionSection: View {
    var store: CalorieStore
    @Binding var draft: ProfileDraft
    @Binding var openPicker: ProfilePicker?
    let measurement: BodyMeasurement?

    var body: some View {
        Section {
            // Нормы белка и жира — первыми строками, как в макете: это самое
            // частое, ради чего сюда заходят после расчёта. Каждая ведёт на
            // свой экран с колесом, итогом и остатком на углеводы.
            NavigationLink {
                ProteinTargetScreen(store: store, draft: $draft, openPicker: $openPicker,
                                    measurement: measurement)
            } label: {
                macroLabel("Белки", color: MacroKind.protein.color,
                           perKg: Double(draft.activeProteinTenths) / 10,
                           grams: draft.profile.proteinTargetGrams(from: measurement))
            }
            .accessibilityIdentifier("openProteinTarget")

            NavigationLink {
                FatTargetScreen(store: store, draft: $draft, openPicker: $openPicker,
                                measurement: measurement)
            } label: {
                macroLabel("Жиры", color: MacroKind.fat.color,
                           perKg: Double(draft.fatTenths) / 10,
                           grams: draft.profile.fatTargetGrams)
            }
            .accessibilityIdentifier("openFatTarget")

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
                settingLabel(systemImage: "circle.lefthalf.filled") {
                    HStack {
                        Text("Кашрут")
                        Spacer()
                        Text(verbatim: kosherSummary)
                            .font(.app(.subheadline))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .accessibilityIdentifier("openKosher")

            // Посты и праздники — рядом с кашрутом: та же тема, и включает
            // её тот же человек. Выключено по умолчанию: обычаи различаются.
            Toggle(isOn: Binding(get: { KosherSettings.shared.observesCalendar },
                                 set: { KosherSettings.shared.observesCalendar = $0 })) {
                // Звезда Давида знаком, а не символом системы: в SF Symbols её
                // нет, а полумесяц со звёздами читается чужим символом.
                settingLabel("Посты и праздники", glyph: "\u{2721}\u{FE0E}")
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

    /// Белок и жир одной строкой: точка цвета макроса, подпись, «1,7 г/кг · 136 г».
    private func macroLabel(_ title: LocalizedStringKey, color: Color,
                            perKg: Double, grams: Double) -> some View {
        HStack(spacing: 12) {
            // Точка в колонке значков: у макроса нет символа, а цвет — его
            // имя на всём остальном экране.
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
                .frame(width: 22)
            Text(title)
                .foregroundStyle(Color.primary)
            Spacer()
            Text(verbatim: String(format: "%.1f \(String(localized: "г/кг")) · %d \(String(localized: "г"))",
                                  perKg, Int(grams.rounded())))
                .font(.app(.subheadline))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    /// Что сейчас выбрано в кашруте: выдержка после мясного или «Выкл.».
    private var kosherSummary: String {
        let settings = KosherSettings.shared
        guard settings.isEnabled else { return String(localized: "Выкл.") }
        return String(format: String(localized: "%lld ч после мясного"), settings.afterMeat / 60)
    }
}
