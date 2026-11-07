import SwiftUI

/// Строка подсказки о сваренной партии: доесть сегодня или приготовить заново.
///
/// Вынесена из `ContentView.summaryCards` — не зависит от состояния экрана
    /// кроме замыкания на открытие блюда.
struct BatchHintRow: View {
    let dish: Dish
    let advice: DishBatch.Advice
    var onOpen: () -> Void

    private var text: String {
        switch advice {
        case .spoiled:
            String(format: String(localized: "%@ — четвёртый день, лучше не есть"), dish.name)
        case let .eatToday(servings):
            if let servings, servings >= 0.5 {
                String(format: String(localized: "%1$@ — доесть сегодня, осталось %2$@ порции"),
                       dish.name, String(format: "%.1f", servings))
            } else {
                String(format: String(localized: "%@ — доесть сегодня"), dish.name)
            }
        case let .cookAgain(runsOut):
            String(format: String(localized: "%1$@ кончится %2$@ — пора готовить"),
                   dish.name, runsOut.formatted(.dateTime.day().month(.abbreviated)))
        }
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
