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
/// Один день в полоске и в сетке месяца.
///
/// Типом, а не кортежем: к дате, записям и попаданию в норму добавилась сама
/// норма, и кортеж из четырёх полей читался уже хуже, чем выглядел.
struct DayMark: Identifiable {
    let date: Date
    let hasEntries: Bool
    let onGoal: Bool
    /// Норма этого дня — та, что действовала в нём.
    let goal: Int

    var id: Date { date }
}

struct WeekStrip: View {
    /// Недели от давней к текущей, по семь дней в каждой.
    let weeks: [[DayMark]]
    var onSelect: (Date) -> Void
    var onShowAll: () -> Void
    /// Итог недели — то, ради чего полоску и читают: семь кружков человек
    /// иначе складывает в голове сам.
    var onShowWeek: (() -> Void)? = nil

    private let calendar = Calendar.current

    /// Показывать ли нормы под числами.
    ///
    /// Только когда дни отличаются: у человека без циклирования и брейков под
    /// всеми семью стоит одно и то же число, и семь одинаковых цифр — это не
    /// сведения, а шум. Решается один раз на всю полоску, а не на каждую
    /// неделю: иначе её высота прыгала бы при листании.
    private var showsGoals: Bool {
        weeks.contains { Set($0.map(\.goal)).count > 1 }
    }

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
                .frame(height: showsGoals ? 56 : 44)

                Button(action: onShowAll) {
                    Image(systemName: "calendar")
                        .font(.app(.subheadline))
                        .foregroundStyle(.tertiary)
                        .frame(width: 30, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Все дни")
                .accessibilityIdentifier("allDays")

                if let onShowWeek {
                    Button(action: onShowWeek) {
                        Image(systemName: "chart.bar.doc.horizontal")
                            .font(.app(.subheadline))
                            .foregroundStyle(.tertiary)
                            .frame(width: 30, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Итог недели")
                    .accessibilityIdentifier("openWeekReview")
                }
        }
    }

    /// Тихо, как шапка недели в Календаре: цвет — только точка под числом.
    /// Залитые кружки над кольцом давали ряд из семи цветных пятен тех же
    /// зелёного и оранжевого, что в кольце, и спорили с ним за внимание.
    private func dayCell(_ day: DayMark) -> some View {
        let isToday = calendar.isDateInToday(day.date)
        let dot: Color = day.onGoal ? ProgressRing.kcalColors[0] : (day.hasEntries ? .orange : .clear)
        return Button {
            onSelect(day.date)
        } label: {
            VStack(spacing: 2) {
                Text(day.date.formatted(.dateTime.weekday(.narrow)))
                    .font(.app(.caption2))
                    .foregroundStyle(.tertiary)
                Text(verbatim: "\(calendar.component(.day, from: day.date))")
                    .font(.app(.subheadline, weight: isToday ? .bold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(isToday ? .primary : .secondary)
                // Норма дня прямо под числом: тогда видно, что завтра рефид,
                // а в понедельник брейк, — не открывая план. И видно, с какой
                // нормой прожит вчерашний день: она у каждого дня своя.
                if showsGoals {
                    // Не мельче подписи дня недели и не бледнее её: десятым
                    // кеглем в третьей ступени серого число не читалось вовсе,
                    // а оно здесь — то, ради чего строку и добавили.
                    Text(verbatim: "\(day.goal)")
                        .font(.app(.caption, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Circle()
                    .fill(dot)
                    .frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity, minHeight: showsGoals ? 56 : 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Сегодняшний день и так на экране.
        .disabled(isToday)
        .accessibilityIdentifier("weekDay-\(calendar.component(.day, from: day.date))")
    }
}
