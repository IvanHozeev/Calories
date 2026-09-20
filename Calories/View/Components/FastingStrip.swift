import SwiftUI

/// Подсказка перед голоданием и в его день — стеклянной плашкой под планом.
///
/// Памятка «до и после» раньше жила в настройках, и открывали её, когда уже
/// поздно: совет снижать кофе нужен за два-три дня, а не в сам пост. Плашка
/// показывает тот совет, который к месту сегодня, а вся памятка — по нажатию.
struct FastingStrip: View {
    let hint: FastingHint
    var onOpen: () -> Void

    private var title: String {
        // Пост идёт — говорим, сколько осталось: это единственное, что в этот
        // момент интересно.
        if let left = hint.remaining() {
            let hours = Int(left / 3600)
            let minutes = Int(left.truncatingRemainder(dividingBy: 3600) / 60)
            return hours > 0
                ? String(format: String(localized: "Пост идёт · осталось %1$lld ч %2$lld мин"), hours, minutes)
                : String(format: String(localized: "Пост идёт · осталось %lld мин"), minutes)
        }
        if hint.daysUntil == 0, let start = hint.interval?.start, start > Date() {
            return String(format: String(localized: "Голодание сегодня в %@"),
                          start.formatted(date: .omitted, time: .shortened))
        }
        switch hint.daysUntil {
        case 0: return String(localized: "Сегодня голодание")
        case 1: return String(localized: "Завтра голодание")
        default: return String(format: String(localized: "Голодание через %lld дн."), hint.daysUntil)
        }
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: hint.daysUntil == 0 ? "moon.stars.fill" : "moon.stars")
                    .font(.app(.subheadline))
                    .foregroundStyle(.indigo)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text(verbatim: title)
                            .font(.app(.subheadline, weight: .semibold))
                        Text(verbatim: "· \(hint.kind.title)")
                            .font(.app(.caption))
                            .foregroundStyle(.secondary)
                    }
                    if let interval = hint.interval, hint.isRunning() {
                        Text(verbatim: String(format: String(localized: "До %@ — потом выход"),
                                              interval.end.formatted(date: .omitted, time: .shortened)))
                            .font(.app(.caption))
                            .foregroundStyle(.secondary)
                    } else if hint.daysUntil == 1 {
                        // Про поднятую норму говорим прямо: цифра в кольце
                        // сегодня другая, и человек должен знать почему.
                        Text("Норма сегодня выше — заправить гликоген перед постом")
                            .font(.app(.caption))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if let item = hint.items.first {
                        Text(verbatim: item.text)
                            .font(.app(.caption))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.app(.caption2, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .liquidGlass(in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("fastingCard")
    }
}
