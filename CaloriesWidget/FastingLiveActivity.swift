import ActivityKit
import WidgetKit
import SwiftUI

/// «Пост идёт» — сколько до выхода, без открывания приложения.
///
/// Устроено так же, как ожидание кашрута: отсчёт и полоску система рисует из
/// двух дат, запись делается один раз. Когда срок вышел, система помечает её
/// устаревшей, и плашка сама меняется на «Пост закончился».
struct FastingLiveActivity: Widget {
    private static let tint = WidgetPalette.carbs[0]

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FastingAttributes.self) { context in
            lockScreen(context.attributes, state: context.state, isOver: context.isStale)
                .activityBackgroundTint(Color(red: 0.11, green: 0.11, blue: 0.118))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let attributes = context.attributes
            let state = context.state
            let isOver = context.isStale
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    header(attributes, isOver: isOver)
                        .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if !isOver {
                        timer(state.until)
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(Self.tint)
                            .padding(.trailing, 6)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if !isOver {
                        progressAndFooter(attributes, state: state)
                            .padding(.horizontal, 6)
                    }
                }
            } compactLeading: {
                Image(systemName: isOver ? "checkmark" : "moon.stars.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Self.tint)
            } compactTrailing: {
                if isOver {
                    Text("Выход")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Self.tint)
                } else {
                    Text(timerInterval: FastingAttributes.countdownRange(now: Date(), until: state.until),
                         countsDown: true, showsHours: true)
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Self.tint)
                        .frame(maxWidth: 58)
                }
            } minimal: {
                if isOver {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Self.tint)
                } else {
                    ProgressView(timerInterval: Self.progressRange(attributes, state), countsDown: false) {
                        EmptyView()
                    } currentValueLabel: {
                        Image(systemName: "moon.stars.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Self.tint)
                    }
                    .progressViewStyle(.circular)
                    .tint(Self.tint)
                }
            }
            .keylineTint(Self.tint)
        }
    }

    private static func progressRange(_ attributes: FastingAttributes,
                                      _ state: FastingAttributes.ContentState) -> ClosedRange<Date> {
        attributes.startedAt...max(state.until, attributes.startedAt)
    }

    /// Вид поста словом: «Сухое · с 18:12».
    private func kindLine(_ attributes: FastingAttributes) -> String {
        let kind: String
        switch attributes.kind {
        case FastingAttributes.dry: kind = String(localized: "Сухое")
        case FastingAttributes.daytime: kind = String(localized: "До темноты")
        default: kind = String(localized: "На воде")
        }
        return String(format: String(localized: "%1$@ · с %2$@"), kind,
                      attributes.startedAt.formatted(date: .omitted, time: .shortened))
    }

    private func header(_ attributes: FastingAttributes, isOver: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: isOver ? "checkmark" : "moon.stars.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Self.tint)
                .frame(width: 40, height: 40)
                .background(Self.tint.opacity(0.2), in: Circle())
            VStack(alignment: .leading, spacing: 0) {
                Text(isOver ? "Пост закончился" : "Пост идёт")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(verbatim: isOver ? String(localized: "сначала вода, потом лёгкая еда")
                                      : kindLine(attributes))
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.6))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
    }

    /// Отсчёт справа: своей ширины и не шире — `Text(timerInterval:)` сам тянется
    /// на всё свободное место и отнимает его у подписи.
    private func timer(_ until: Date) -> some View {
        Text(timerInterval: FastingAttributes.countdownRange(now: Date(), until: until),
             countsDown: true, showsHours: true)
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
            .lineLimit(1)
            .frame(width: 118, alignment: .trailing)
    }

    private func progressAndFooter(_ attributes: FastingAttributes,
                                   state: FastingAttributes.ContentState) -> some View {
        VStack(spacing: 8) {
            ProgressView(timerInterval: Self.progressRange(attributes, state), countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .tint(Self.tint)
            HStack {
                Text(verbatim: String(format: String(localized: "выход в %@"),
                                      state.until.formatted(date: .omitted, time: .shortened)))
                Spacer(minLength: 8)
                Text("сначала вода, потом лёгкая еда")
            }
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.6))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
    }

    private func lockScreen(_ attributes: FastingAttributes,
                            state: FastingAttributes.ContentState,
                            isOver: Bool) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                header(attributes, isOver: isOver)
                    .layoutPriority(1)
                Spacer(minLength: 0)
                if !isOver {
                    timer(state.until)
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            if !isOver {
                progressAndFooter(attributes, state: state)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }
}
