import ActivityKit
import WidgetKit
import SwiftUI

/// «Можно ли уже» — ответ без открывания приложения.
///
/// Каждое число здесь система рисует сама из одной даты: `Text(timerInterval:)`
/// считает вниз по своим часам, поэтому запись делается один раз и остаётся
/// верной с закрытым приложением. Ничего не обновляется и ничего не тикает.
struct KosherWaitLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: KosherWaitAttributes.self) { context in
            lockScreen(context.attributes, state: context.state)
                .activityBackgroundTint(.black.opacity(0.55))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let look = Look(blocked: context.attributes.blocked)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(look.title)
                            .font(.caption2.weight(.black))
                            .kerning(0.8)
                            .foregroundStyle(look.tint)
                        countdown(to: context.state.until)
                            .font(.title3.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                    }
                    .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    // Причина отсчёта, а не просто его конец: «после мясного в
                    // 19:35» объясняет число, которое иначе принимают на веру.
                    Text(look.caption(since: context.attributes.since))
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.trailing, 6)
                }
            } compactLeading: {
                Image(systemName: look.symbol)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(look.tint)
            } compactTrailing: {
                // Часы и минуты без секунд: шесть часов ожидания — это
                // «5:59:42», и в компактную часть островка оно не влезает.
                Text(timerInterval: Date()...context.state.until,
                     countsDown: true, showsHours: true)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(look.tint)
                    .frame(maxWidth: 58)
            } minimal: {
                Image(systemName: look.symbol)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(look.tint)
            }
            .keylineTint(look.tint)
        }
    }

    private func lockScreen(_ attributes: KosherWaitAttributes,
                            state: KosherWaitAttributes.ContentState) -> some View {
        let look = Look(blocked: attributes.blocked)
        return HStack(spacing: 14) {
            Image(systemName: look.symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(look.tint)
                .frame(width: 44, height: 44)
                .background(look.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 0) {
                Text(look.title)
                    .font(.caption2.weight(.black))
                    .kerning(0.8)
                    .foregroundStyle(look.tint)
                countdown(to: state.until)
                    .font(.title2.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }

            Spacer(minLength: 0)

            Text(look.caption(since: attributes.since))
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// Отсчёт системы: без обновлений, до секунды, с закрытым приложением.
    private func countdown(to date: Date) -> Text {
        Text(timerInterval: Date()...date, countsDown: true)
    }
}

/// Как выглядит ожидание: чего ждём — то и подписано.
///
/// Своя таблица у виджета, а не `KosherStatus` из приложения: модель живёт в
/// другом таргете, и тащить её сюда ради двух слов значит тащить за ней
/// каталог продуктов.
private struct Look {
    let blocked: String

    var isMeat: Bool { blocked == KosherWaitAttributes.meat }

    var title: String {
        isMeat ? String(localized: "Мясное") : String(localized: "Молочное")
    }

    var symbol: String { isMeat ? "fork.knife" : "drop" }

    var tint: Color { isMeat ? .orange : .cyan }

    func caption(since: Date) -> String {
        let time = since.formatted(date: .omitted, time: .shortened)
        return isMeat
            ? String(format: String(localized: "после молочного в %@"), time)
            : String(format: String(localized: "после мясного в %@"), time)
    }
}
