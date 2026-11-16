import SwiftUI

/// Строка главной подсказки под кольцом.
///
/// Вид у всех подсказок один: значок источника, заголовок и, если есть,
/// пояснение. Раньше совет дня и сигнал «пора подъесть» были двумя строками
/// разного вида, и глаз сравнивал оформление, а не смысл.
struct DayHintRow: View {
    let hint: DayHint
    /// nil — у подсказки нет действия, строка не нажимается.

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Group {
                // Подсказки календаря — звездой Давида: в SF Symbols её нет,
                // поэтому знаком, тем же, что у переключателя в профиле.
                if hint.source == .calendar {
                    Text(verbatim: "\u{2721}\u{FE0E}")
                } else {
                    Image(systemName: symbol)
                }
            }
            .font(.app(.subheadline))
            .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: hint.title)
                    .font(.app(.subheadline, weight: hint.detail == nil ? .regular : .semibold))
                    .foregroundStyle(hint.detail == nil ? .secondary : .primary)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = hint.detail {
                    Text(verbatim: detail)
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        // Одним элементом: без этого имя наследовали значок, заголовок и
        // пояснение по отдельности, и VoiceOver читал подсказку тремя кусками.
        // Тап, нажатие и имя для тестов — у карточки вокруг (`HintCard`).
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch hint.source {
        case .recovery: return hint.action == .openPlan ? "pause.circle" : "arrow.up.forward.circle"
        case .fasting: return "moon.stars"
        case .weeklyReview: return "calendar.badge.clock"
        case .batch: return "frying.pan"
        case .backup: return "externaldrive.badge.exclamationmark"
        case .weightExplainer, .weighIn: return "scalemass"
        case .measurements: return "ruler"
        case .calendar: return "calendar"
        case .dailyAdvice: return "lightbulb.fill"
        }
    }

    /// Цвет калорий, а не оранжевый: оранжевый — цвет жиров, и подсказка
    /// читалась ещё одним макросом.
    private var tint: Color { ProgressRing.kcalColors[0] }
}
