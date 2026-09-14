import SwiftUI

/// Последние семь дней полоской над кольцом «Сегодня».
///
/// Вместо огонька в тулбаре и отдельного экрана активности. Туда заходили ради
/// одного — посмотреть вчерашний день, — а доходили через серию, награды и
/// неделю макросов. Теперь прошедший день в одно нажатие прямо с главного
/// экрана, а полная история — за кнопкой в конце полоски.
///
/// Именно семь последних дней, а не неделя с понедельника: в понедельник
/// календарная неделя начиналась бы с пустого сегодня, и вчера в ней не было бы.
struct WeekStrip: View {
    let days: [(date: Date, hasEntries: Bool, onGoal: Bool)]
    let streak: Int
    var onSelect: (Date) -> Void
    var onShowAll: () -> Void

    private let calendar = Calendar.current

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                ForEach(days, id: \.date) { day in
                    dayCell(day)
                        .frame(maxWidth: .infinity)
                }
                Button(action: onShowAll) {
                    Image(systemName: "calendar")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(width: 34, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Все дни")
                .accessibilityIdentifier("allDays")
            }
            if streak > 1 {
                Text(String(format: String(localized: "Серия %lld дн. в норме"), streak))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
        }
    }

    private func dayCell(_ day: (date: Date, hasEntries: Bool, onGoal: Bool)) -> some View {
        let isToday = calendar.isDateInToday(day.date)
        let fill: Color = day.onGoal ? .green : (day.hasEntries ? .orange : .clear)
        return Button {
            onSelect(day.date)
        } label: {
            VStack(spacing: 3) {
                Text(day.date.formatted(.dateTime.weekday(.narrow)))
                    .font(.caption2)
                    .foregroundStyle(isToday ? .primary : .secondary)
                ZStack {
                    Circle()
                        .fill(day.hasEntries ? AnyShapeStyle(fill.opacity(0.22)) : AnyShapeStyle(.channel(thickness: 6)))
                    if isToday {
                        Circle().strokeBorder(Color.primary.opacity(0.6), lineWidth: 1.5)
                    }
                    Text(verbatim: "\(calendar.component(.day, from: day.date))")
                        .font(.caption.weight(isToday ? .bold : .medium))
                        .monospacedDigit()
                        .foregroundStyle(day.hasEntries ? fill : .secondary)
                }
                .frame(width: 32, height: 32)
            }
        }
        .buttonStyle(.plain)
        // Сегодняшний день и так на экране.
        .disabled(isToday)
        .accessibilityIdentifier("weekDay-\(calendar.component(.day, from: day.date))")
    }
}
