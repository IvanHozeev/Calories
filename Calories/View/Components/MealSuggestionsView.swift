import SwiftUI

/// Подсказки еды под черновиком приёма пищи: «Как обычно», пока приём пуст,
/// и «Обычно вместе», когда в нём что-то есть.
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

    /// Стоит ли сказать, что в приёме мясное с молочным.
    private var showsMixingWarning: Bool {
        let settings = KosherSettings.shared
        guard settings.isEnabled, settings.warnsMixing else { return false }
        return store.isKosherMixed(draft: draftItems)
    }

    var body: some View {
        // Подбора к остатку приёма («Полдник: 162 ккал») здесь больше нет.
        // Он показывался, только когда в приёме уже что-то есть, — и ровно
        // тогда спорил с «Обычно вместе»: два списка догадок о том, что
        // доложить, а нужен один, построенный на том, что уже в тарелке.
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
                micros: store.notableMicronutrients(forParts: item.parts.map { ($0.name, $0.grams) }),
                offersVitamins: store.offersVitamins(named: item.parts.map(\.name)),
                parts: item.parts.map {
                    .init(name: $0.name,
                          macros: Macros(protein: $0.protein, fat: $0.fat, carbs: $0.carbs),
                          grams: $0.grams,
                          traits: store.foodNamed($0.name)?.traits ?? [])
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


}
