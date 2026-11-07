import SwiftUI

/// Строка подсказки о сваренной партии: доесть сегодня или приготовить заново.
///
/// Вынесена из `ContentView.summaryCards` — не зависит от состояния экрана
    /// кроме замыкания на открытие блюда.
struct BatchHintRow: View {
    let dish: Dish
    let state: DishBatch.State
    let advice: DishBatch.Advice
    var onOpen: () -> Void

    /// Название и сколько осталось — больше в строке ничего.
    ///
    /// Раньше она объясняла: «кончится 8 нояб. — пора готовить». Вывод
    /// человек делает сам и быстрее, чем читает фразу; ему нужно только
    /// число порций. Срочность при этом не потерялась — её несёт цвет:
    /// испорченное красным, последний день оранжевым, запас спокойным.
    private var text: String {
        switch advice {
        case .spoiled:
            String(format: String(localized: "%@ — четвёртый день, лучше не есть"), dish.name)
        case .eatToday, .cookAgain:
            remaining(dish.name, state.remainingServings)
        }
    }

    /// «Паста — осталось 2 порции». Меньше порции — граммами: «осталось
    /// 0 порций» звучит как «ничего нет», хотя на тарелку ещё хватит.
    private func remaining(_ name: String, _ servings: Double?) -> String {
        guard let servings, servings >= 1 else {
            let grams = String(format: "%.0f \(String(localized: "г"))", state.remainingGrams)
            return String(format: String(localized: "%1$@ — осталось %2$@"), name, grams)
        }
        return String(format: String(localized: "%1$@ — осталось %2$@"),
                      name, String.localizedStringWithFormat(
                          String(localized: "%lld порции"), Int(servings)))
    }

    private var color: Color {
        switch advice {
        case .spoiled: ProgressRing.overColors[0]
        case .eatToday: .orange
        case .cookAgain: MacroKind.carbs.color
        }
    }

    var body: some View {
        Button {
            onOpen()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "takeoutbag.and.cup.and.straw")
                    .font(.app(.footnote))
                Text(verbatim: text)
                    .font(.app(.caption))
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.app(.caption2))
            }
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(color.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("batchHint")
    }
}
