import SwiftUI

/// Последние семь дней полоской под кольцом «Сегодня».
///
/// Вместо огонька в тулбаре и отдельного экрана активности. Туда заходили ради
/// одного — посмотреть вчерашний день, — а доходили через серию, награды и
/// неделю макросов. Теперь прошедший день в одно нажатие прямо с главного
/// экрана, а полная история — за кнопкой в конце полоски.
///
/// Именно окна по семь дней до сегодня, а не недели с понедельника: в понедельник
/// календарная неделя начиналась бы с пустого сегодня, и вчера в ней не было бы.
/// Прошлые недели — свайпом вправо.
struct WeekStrip: View {
    /// Недели от давней к текущей, по семь дней в каждой.
    let weeks: [[(date: Date, hasEntries: Bool, onGoal: Bool)]]
    var onSelect: (Date) -> Void
    var onShowAll: () -> Void

    private let calendar = Calendar.current

    var body: some View {
        HStack(spacing: 0) {
                // Листается целыми неделями: свободный скролл вставал бы
                // посередине и резал неделю пополам. Открывается на текущей.
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        ForEach(weeks.indices, id: \.self) { index in
                            HStack(spacing: 0) {
                                ForEach(weeks[index], id: \.date) { day in
                                    dayCell(day)
                                }
                            }
                            .containerRelativeFrame(.horizontal)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollIndicators(.hidden)
                .defaultScrollAnchor(.trailing)
                .frame(height: 44)

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
    }

    /// Тихо, как шапка недели в Календаре: цвет — только точка под числом.
    /// Залитые кружки над кольцом давали ряд из семи цветных пятен тех же
    /// зелёного и оранжевого, что в кольце, и спорили с ним за внимание.
    private func dayCell(_ day: (date: Date, hasEntries: Bool, onGoal: Bool)) -> some View {
        let isToday = calendar.isDateInToday(day.date)
        let dot: Color = day.onGoal ? ProgressRing.kcalColors[0] : (day.hasEntries ? .orange : .clear)
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
