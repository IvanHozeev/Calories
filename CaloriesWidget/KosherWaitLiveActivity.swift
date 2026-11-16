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
                // Графитовая плашка макета, а не прозрачное стекло: на
                // блокировке она читается над любыми обоями.
                .activityBackgroundTint(Color(red: 0.11, green: 0.11, blue: 0.118))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let look = Look(blocked: context.attributes.blocked)
            let attributes = context.attributes
            let state = context.state
            return DynamicIsland {
                // Развёрнутый остров — та же плашка, что на блокировке: значок
                // с названием и причиной слева, отсчёт справа, ниже полоска
                // и две подписи.
                DynamicIslandExpandedRegion(.leading) {
                    header(look, attributes: attributes)
                        .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    countdown(to: state.until, showsHours: true)
                        .font(.system(size: 28, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(look.tint)
                        .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    progressAndFooter(look, attributes: attributes, state: state)
                        .padding(.horizontal, 6)
                }
            } compactLeading: {
                Image(systemName: look.symbol)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(look.tint)
            } compactTrailing: {
                // Часы и минуты без секунд: шесть часов ожидания — это
                // «5:59:42», и в компактную часть островка оно не влезает.
                countdown(to: state.until, showsHours: true)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(look.tint)
                    .frame(maxWidth: 58)
            } minimal: {
                // Кольцо прошедшего ожидания со значком внутри: по нему видно,
                // сколько уже прошло, и без числа.
                ProgressView(timerInterval: Self.progressRange(attributes, state), countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    Image(systemName: look.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(look.tint)
                }
                .progressViewStyle(.circular)
                .tint(look.tint)
            }
            .keylineTint(look.tint)
        }
    }

    /// От того, что съели, до конца ожидания: по этому отрезку идёт полоска.
    private static func progressRange(_ attributes: KosherWaitAttributes,
                                      _ state: KosherWaitAttributes.ContentState) -> ClosedRange<Date> {
        attributes.since...max(state.until, attributes.since)
    }

    /// Значок, название и причина: «Мясное / после мясного в 13:20».
    private func header(_ look: Look, attributes: KosherWaitAttributes) -> some View {
        HStack(spacing: 12) {
            Image(systemName: look.symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(look.tint)
                .frame(width: 40, height: 40)
                .background(look.tint.opacity(0.2), in: Circle())
            VStack(alignment: .leading, spacing: 0) {
                Text(look.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                // Причина отсчёта, а не просто его конец: «после мясного в
                // 13:20» объясняет число, которое иначе принимают на веру.
                Text(look.caption(since: attributes.since))
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.6))
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
    }

    /// Полоска прошедшего ожидания и две подписи под ней: сколько ждать
    /// всего и когда можно другое.
    private func progressAndFooter(_ look: Look, attributes: KosherWaitAttributes,
                                   state: KosherWaitAttributes.ContentState) -> some View {
        VStack(spacing: 8) {
            ProgressView(timerInterval: Self.progressRange(attributes, state), countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .tint(look.tint)
            HStack {
                Text(look.waitCaption(since: attributes.since, until: state.until))
                Spacer(minLength: 8)
                Text(look.releaseCaption(at: state.until))
            }
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.6))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
    }

    private func lockScreen(_ attributes: KosherWaitAttributes,
                            state: KosherWaitAttributes.ContentState) -> some View {
        let look = Look(blocked: attributes.blocked)
        return VStack(spacing: 12) {
            HStack(spacing: 12) {
                header(look, attributes: attributes)
                Spacer(minLength: 8)
                countdown(to: state.until, showsHours: true)
                    .font(.system(size: 32, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            progressAndFooter(look, attributes: attributes, state: state)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    /// Отсчёт системы: без обновлений, до секунды, с закрытым приложением.
    ///
    /// Диапазон берём у `KosherWaitAttributes`: он следит, чтобы конец не
    /// оказался раньше начала — на этом расширение падало после каждого
    /// истёкшего ожидания.
    private func countdown(to date: Date, showsHours: Bool = false) -> Text {
        Text(timerInterval: KosherWaitAttributes.countdownRange(now: Date(), until: date),
             countsDown: true, showsHours: showsHours)
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

    /// Цвет жиров для мясного и белков для молочного — те же, что в кольце
    /// приложения: активность узнаётся по палитре, а не по системному оранжевому.
    var tint: Color { isMeat ? WidgetPalette.fat[0] : WidgetPalette.protein[0] }

    /// «ждать 6 ч»: сколько длится ожидание целиком.
    func waitCaption(since: Date, until: Date) -> String {
        let hours = max(1, Int((until.timeIntervalSince(since) / 3600).rounded()))
        return String(format: String(localized: "ждать %lld ч"), hours)
    }

    /// «молочное можно в 19:20»: когда ожидание кончится и что тогда можно.
    func releaseCaption(at date: Date) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        return String(format: isMeat ? String(localized: "молочное можно в %@")
                                     : String(localized: "мясное можно в %@"), time)
    }

    func caption(since: Date) -> String {
        let time = since.formatted(date: .omitted, time: .shortened)
        return isMeat
            ? String(format: String(localized: "после молочного в %@"), time)
            : String(format: String(localized: "после мясного в %@"), time)
    }
}
