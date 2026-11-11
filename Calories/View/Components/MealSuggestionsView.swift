import SwiftUI

/// Подсказки еды под чёрновиком приёма пищи: «Как обычно», «Обычно вместе» и
/// подбор к остатку калорий.
///
/// Вынесен из AddEntryView: не зависит от состояния экрана, кроме черновика
/// и выбранных продуктов.
struct MealSuggestionsView: View {
    let store: CalorieStore
    @Binding var draftItems: [MealItem]
    /// Кладёт продукты в черновик — для «как обычно» и подбора к остатку.
    var onAdd: ([MealItem]) -> Void
    /// Открывает экран порции для пары «обычно вместе».
    var onOpenPair: (MealPairs.Suggestion) -> Void
    /// Прокрутить список наверх после добавления.
    var onScrollToTop: () -> Void

    /// Сколько осталось до цели ближайшего приёма.
    private var mealRemaining: Int {
        guard MealScheduleSettings.shared.isEnabled else { return 0 }
        guard let next = MealSchedule.nextSlot(store.todaySlots) else { return 0 }
        return max(0, next.calories - draftItems.reduce(0) { $0 + $1.calories })
    }

    private var suggestions: [MealSuggestions.Candidate] {
        store.mealSuggestions(remaining: mealRemaining)
    }

    /// Приёмы, которые человек собирает снова и снова, — целиком.
    private var usual: [UsualMeal.Suggestion] {
        store.usualMeals(period: nextMealPeriod ?? MealPeriod.period(for: Date()))
    }

    /// Что человек обычно кладёт вместе с тем, что уже в приёме.
    private var pairs: [MealPairs.Suggestion] {
        store.pairSuggestions(draft: draftItems.map(\.name))
    }

    /// Какой приём сейчас ближайший — его именем и подписаны подсказки.
    private var nextMealPeriod: MealPeriod? {
        guard MealScheduleSettings.shared.isEnabled else { return nil }
        return MealSchedule.nextSlot(store.todaySlots)?.period
    }

    /// Заголовок подсказок: какой это приём и сколько на него осталось.
    private var suggestionsTitle: String {
        guard let period = nextMealPeriod else {
            return String(format: String(localized: "Осталось %lld ккал"), mealRemaining)
        }
        return String(format: String(localized: "%1$@: %2$lld ккал"),
                      String(localized: String.LocalizationValue(period.rawValue)), mealRemaining)
    }

    /// Стоит ли сказать, что в приёме мясное с молочным.
    private var showsMixingWarning: Bool {
        let settings = KosherSettings.shared
        guard settings.isEnabled, settings.warnsMixing else { return false }
        return store.isKosherMixed(draft: draftItems)
    }

    var body: some View {
        // Подсказка под остаток приёма — только когда приём уже begun.
        if !draftItems.isEmpty, !suggestions.isEmpty {
            Section {
                ForEach(suggestions) { item in
                    suggestionRow(item)
                        .contentShape(Rectangle())
                        .onTapGesture { addSuggestion(item) }
                }
            } header: {
                Text(verbatim: suggestionsTitle)
            }
        }

        // Пока приём пуст — целиком из «как обычно».
        if draftItems.isEmpty, !usual.isEmpty {
            Section {
                ForEach(usual) { item in
                    usualRow(item)
                        .contentShape(Rectangle())
                        .onTapGesture { addUsual(item) }
                }
            } header: {
                Text("Как обычно")
            }
        }

        // Обычно вместе — только если в приёме уже что-то есть.
        if !draftItems.isEmpty, !pairs.isEmpty {
            Section {
                ForEach(pairs) { item in
                    pairRow(item)
                        .contentShape(Rectangle())
                        .onTapGesture { openPair(item) }
                }
            } header: {
                Text("Обычно вместе")
            }
        }

        // Предупреждение о смешивании мясного с молочным.
        if showsMixingWarning {
            Label("Мясное с молочным в одной тарелке", systemImage: "exclamationmark.triangle")
                .font(.app(.caption))
                .foregroundStyle(.orange)
                .padding(.vertical, 2)
                .accessibilityIdentifier("kosherMixing")
        }
    }

    /// Строка подсказки: что взять и сколько.
    private func suggestionRow(_ item: MealSuggestions.Candidate) -> some View {
        FoodRow(name: item.name,
                calories: item.calories,
                portion: item.parts.compactMap { part in
                    part.grams.map { String(format: "%.0f \(String(localized: "г"))", $0) }
                }.joined(separator: " · "),
                macros: item.macros)
    }

    /// Кладёт в черновик то, что обычно идёт вместе.
    private func addUsual(_ item: UsualMeal.Suggestion) {
        withAnimation(.snappy) {
            draftItems.append(contentsOf: item.parts.map {
                MealItem(name: $0.name, calories: $0.calories,
                         macros: Macros(protein: $0.protein, fat: $0.fat, carbs: $0.carbs),
                         grams: $0.grams)
            })
        }
        onScrollToTop()
    }

    /// Строка «как обычно»: состав перечислен, цена — общая.
    /// Каждая часть приёма красится в цвет своего доминирующего макроса.
    private func usualRow(_ item: UsualMeal.Suggestion) -> some View {
        FoodRow(name: item.parts.map(\.name).joined(separator: ", "),
                calories: item.calories,
                portion: String(format: String(localized: "%lld позиции"), item.parts.count),
                macros: item.macros,
                detail: String(format: String(localized: "%lld раз"), item.times),
                parts: item.parts.map {
                    .init(name: $0.name,
                          macros: Macros(protein: $0.protein, fat: $0.fat, carbs: $0.carbs),
                          grams: $0.grams)
                })
    }

    /// Открывает подсказку экраном порции — тем же, каким открывается любой
    /// продукт.
    private func openPair(_ item: MealPairs.Suggestion) {
        onOpenPair(item)
    }

    /// Строка «обычно вместе» — та же FoodRow, что и везде.
    private func pairRow(_ item: MealPairs.Suggestion) -> some View {
        let grams = item.grams ?? 100
        return FoodRow(
            name: item.name,
            calories: item.calories,
            portion: String(format: "%.0f \(String(localized: "г"))", grams),
            macros: item.macros,
            micros: store.notableMicronutrients(forFoodNamed: item.name, grams: grams),
            traits: store.foodNamed(item.name)?.traits ?? []
        )
    }

    /// Кладёт подсказку в черновик — уже с подобранным весом.
    private func addSuggestion(_ item: MealSuggestions.Candidate) {
        withAnimation(.snappy) {
            draftItems.append(contentsOf: item.parts.map {
                MealItem(name: $0.name, calories: $0.calories, macros: $0.macros, grams: $0.grams)
            })
        }
        onScrollToTop()
    }

}
