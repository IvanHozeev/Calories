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
    /// Сколько съедено. Нужно, чтобы отличить недобор от попадания: «не
    /// больше нормы» одинаково верно и для дня в цель, и для дня на тысяче.
    var consumed: Int = 0
    /// День ещё идёт — судить рано.
    var isToday: Bool = false

    var id: Date { date }

    /// Чем кончился день.
    enum Verdict {
        /// Записей нет.
        case empty
        /// Идёт прямо сейчас.
        case running
        /// Съедено в норму.
        case onGoal
        /// Заметно меньше нормы — на дефиците это дыра, а не успех.
        case under
        /// Перебор.
        case over
    }

    /// Насколько можно недобрать, чтобы это считалось попаданием.
    ///
    /// Десятая часть нормы: промахнуться на двести килокалорий из двух с
    /// половиной тысяч — обычная жизнь, а тысяча вместо двух с половиной —
    /// не «уложился», сколько бы знак «меньше» ни был формально верен.
    static let undershootShare = 0.1

    var verdict: Verdict {
        guard hasEntries else { return .empty }
        // Сегодня приговора нет: день не кончился, и зелёная точка с утра
        // означала бы лишь то, что человек ещё не успел съесть норму.
        if isToday { return .running }
        if !onGoal { return .over }
        return Double(consumed) < Double(goal) * (1 - Self.undershootShare) ? .under : .onGoal
    }
}

struct WeekStrip: View {
    /// Недели от давней к текущей, по семь дней в каждой.
    let weeks: [[DayMark]]
    var onSelect: (Date) -> Void
    /// История: итог недели и все прошедшие дни.
    var onShowAll: () -> Void

    private let calendar = Calendar.current

    /// Высота полоски.
    ///
    /// Считается от кегля, а не задана числом: со строкой нормы в ячейке four
    /// строки — день недели, число, норма и точка, — и при крупном системном
    /// шрифте фиксированная высота срезала бы нижнюю, то есть точку. Она и
    /// срезалась: при обычном кегле пятьдесят шесть точек на всё это уже
    /// не хватало.
    @ScaledMetric(relativeTo: .subheadline) private var tallRow: CGFloat = 66
    @ScaledMetric(relativeTo: .subheadline) private var shortRow: CGFloat = 44

    private var rowHeight: CGFloat { showsEaten ? tallRow : shortRow }

    /// Показывать ли числа под днями.
    ///
    /// Под числом дня стоит съеденное, а не норма.
    ///
    /// Норма там была сведениями о плане, а не о прожитом дне: она одинакова
    /// у всех дней без циклирования, а главное — не отвечает на вопрос, с
    /// которым на полоску и смотрят. «Сколько я тогда съел» — отвечает, и
    /// вместе с точкой-вердиктом над ним день читается целиком.
    ///
    /// Решается один раз на всю полоску, а не на каждую неделю: иначе её
    /// высота прыгала бы при листании.
    private var showsEaten: Bool {
        weeks.contains { week in week.contains { $0.hasEntries } }
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
                .frame(height: rowHeight)

                Button(action: onShowAll) {
                    Image(systemName: "calendar")
                        .font(.app(.subheadline))
                        .foregroundStyle(.tertiary)
                        .frame(width: 30, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("История")
                .accessibilityIdentifier("allDays")
        }
    }

    /// Точка дня.
    ///
    /// Цвет — только у законченного дня, и только у двух исходов: попал в
    /// норму и перебрал. Идущий день и недобор рисуются кольцом: сегодня
    /// судить рано — зелёная точка с утра означала бы лишь то, что человек ещё
    /// не успел съесть норму, — а тысяча из двух с половиной это не «уложился»,
    /// хотя формально и «не больше нормы».
    @ViewBuilder
    private func dayDot(_ verdict: DayMark.Verdict) -> some View {
        switch verdict {
        case .empty:
            Circle().fill(.clear).frame(width: 5, height: 5)
        case .running:
            Circle().stroke(Color.secondary, lineWidth: 1).frame(width: 5, height: 5)
        case .onGoal:
            Circle().fill(ProgressRing.kcalColors[0]).frame(width: 5, height: 5)
        case .under:
            Circle().stroke(ProgressRing.kcalColors[0], lineWidth: 1).frame(width: 5, height: 5)
        case .over:
            // Свой красный из палитры кольца, а не системный: системный тут
            // кричал, а этот — тот же цвет, которым перебор нарисован в самом
            // кольце. Один перебор — один цвет на всё приложение.
            Circle().fill(ProgressRing.overColors[0]).frame(width: 5, height: 5)
        }
    }

    /// Тихо, как шапка недели в Календаре: цвет — только точка под числом.
    /// Залитые кружки над кольцом давали ряд из семи цветных пятен тех же
    /// зелёного и оранжевого, что в кольце, и спорили с ним за внимание.
    private func dayCell(_ day: DayMark) -> some View {
        let isToday = calendar.isDateInToday(day.date)
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
                // Точка сразу под числом дня, а норма под ней: вердикт
                // относится к дню, а не к норме, и стоять он должен рядом
                // с тем, о чём говорит.
                dayDot(day.verdict)
                if showsEaten {
                    // Не мельче подписи дня недели и не бледнее её: десятым
                    // кеглем в третьей ступени серого число не читалось вовсе,
                    // а оно здесь — то, ради чего строку и добавили.
                    //
                    // У дня без записей места под число не отнимаем, но и
                    // нуля не пишем: пустой день и день на нуле — разные вещи.
                    Text(verbatim: day.hasEntries ? "\(day.consumed)" : " ")
                        .font(.app(.caption, weight: .medium))
                        .monospacedDigit()
                        // Зелёным, цветом калорий: это съеденное, то же самое,
                        // что крупно стоит в кольце на «Сегодня». Серым оно
                        // читалось как подпись к числу дня, а не как число.
                        //
                        // День с перебором — красным, вместе с точкой под
                        // числом: тогда перебор виден по самому числу, а не
                        // по пятну под ним, которое ещё надо соотнести.
                        .foregroundStyle(day.verdict == .over ? ProgressRing.overColors[0] : ProgressRing.kcalColors[0])
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(maxWidth: .infinity, minHeight: rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Сегодняшний день и так на экране.
        .disabled(isToday)
        .accessibilityIdentifier("weekDay-\(calendar.component(.day, from: day.date))")
    }
}
