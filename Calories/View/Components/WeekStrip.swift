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
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 0) {
                ForEach(days, id: \.date) { day in
                    dayCell(day)
                        .frame(maxWidth: .infinity)
                }
                Button(action: onShowAll) {
                    Image(systemName: "calendar")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
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

    /// Тихо, как шапка недели в Календаре: цвет — только точка под числом.
    /// Залитые кружки над кольцом давали ряд из семи цветных пятен тех же
    /// зелёного и оранжевого, что в кольце, и спорили с ним за внимание.
    private func dayCell(_ day: (date: Date, hasEntries: Bool, onGoal: Bool)) -> some View {
        let isToday = calendar.isDateInToday(day.date)
        let dot: Color = day.onGoal ? .green : (day.hasEntries ? .orange : .clear)
        return Button {
            onSelect(day.date)
        } label: {
            VStack(spacing: 2) {
                Text(day.date.formatted(.dateTime.weekday(.narrow)))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(verbatim: "\(calendar.component(.day, from: day.date))")
                    .font(.subheadline.weight(isToday ? .bold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(isToday ? .primary : .secondary)
                Circle()
                    .fill(dot)
                    .frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Сегодняшний день и так на экране.
        .disabled(isToday)
        .accessibilityIdentifier("weekDay-\(calendar.component(.day, from: day.date))")
    }
}
