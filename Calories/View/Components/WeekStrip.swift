import SwiftUI

/// Последние семь дней полоской под кольцом «Сегодня».
///
/// Вместо огонька в тулбаре и отдельного экрана активности. Туда заходили ради
/// одного — посмотреть вчерашний день, — а доходили через серию, награды и
/// неделю макросов. Теперь прошедший день в одно нажатие прямо с главного
/// экрана. Отдельного экрана истории больше нет: дальние дни — свайпом.
///
/// Именно окна по семь дней до сегодня, а не недели с понедельника: в понедельник
/// календарная неделя начиналась бы с пустого сегодня, и вчера в ней не было бы.
/// Прошлые недели — свайпом вправо.
/// Один день в полоске.
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
    nonisolated static let undershootShare = 0.1

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

    private let calendar = Calendar.current

    /// Высота полоски: подпись дня и кольцо с числом.
    ///
    /// Считается от кегля, а не задана числом: при крупном системном шрифте
    /// подпись растёт, и фиксированная высота срезала бы нижний край кольца.
    @ScaledMetric(relativeTo: .caption2) private var rowHeight: CGFloat = 58

    var body: some View {
        // Листается целыми неделями: свободный скролл вставал бы посередине
        // и резал неделю пополам. Открывается на текущей.
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
    }

    /// Сокращение дня недели с заглавной: «Пн», «Вт», «Ср».
    ///
    /// В русском Foundation отдаёт его строчным, и в ряду из семи подписей
    /// это читается обрывками слов, а не столбцами.
    private static func weekdayLabel(_ date: Date) -> String {
        let text = date.formatted(.dateTime.weekday(.abbreviated))
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    /// Один день: подпись и кольцо с числом внутри.
    ///
    /// Дуга кольца — сколько нормы съедено, и этого достаточно, чтобы день
    /// читался целиком. Раньше под числом стояли калории, а под ними знак
    /// «>» или «<»: три строки на день и ряд цифр, которые приходилось
    /// сравнивать с нормой в уме. Дуга сравнивает сама: полная — норма
    /// набрана, малиновая — мимо неё, короткая — недобор.
    private func dayCell(_ day: DayMark) -> some View {
        let isToday = calendar.isDateInToday(day.date)
        let number = calendar.component(.day, from: day.date)
        return Button {
            onSelect(day.date)
        } label: {
            VStack(spacing: 4) {
                // Две буквы, а не одна: «В» в русском — и вторник, и
                // воскресенье, «С» — среда и суббота, «П» — понедельник и
                // пятница. Узкая форма даёт ровно их, и половина полоски
                // читается гаданием по порядку. Сокращённая различает все
                // семь.
                Text(verbatim: Self.weekdayLabel(day.date))
                    .font(.app(.caption2, weight: isToday ? .bold : .regular))
                    .foregroundStyle(isToday ? .primary : .secondary)
                DayRing(day: day, number: number, isToday: isToday)
            }
            .frame(maxWidth: .infinity, minHeight: rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Сегодняшний день и так на экране.
        .disabled(isToday)
        .accessibilityLabel(Text(verbatim: accessibilityText(day, number: number)))
        .accessibilityIdentifier("weekDay-\(number)")
    }

    /// Дугу голосом не прочитать: число, съеденное и промах — словами.
    private func accessibilityText(_ day: DayMark, number: Int) -> String {
        var text = "\(Self.weekdayLabel(day.date)) \(number)"
        if day.hasEntries {
            text += ", " + String(format: String(localized: "%lld ккал"), day.consumed)
        }
        switch day.verdict {
        case .over:
            text += ", " + String(format: String(localized: "Перебор на %lld ккал"), day.consumed - day.goal)
        case .under:
            text += ", " + String(format: String(localized: "Недобор на %lld ккал"), day.goal - day.consumed)
        default:
            break
        }
        return text
    }
}

/// Кольцо дня в полоске недели.
///
/// Та же форма, что у главного кольца: окружность с раскрытием сверху, цвет
/// калорий, а мимо нормы — тот же красный, которым перебор нарисован в самом
/// кольце. Дорожка — цвет дуги, приглушённый, как под макросами.
private struct DayRing: View {
    let day: DayMark
    let number: Int
    let isToday: Bool

    /// Доля окружности под дугу: 360° минус раскрытие в 84°, как у главного кольца.
    private static let arcShare = 0.766
    /// Раскрытие сверху: кольцо повёрнуто на 8°, как и главное.
    private static let turn: Double = 8
    private static let lineWidth: CGFloat = 4.5
    private static let size: CGFloat = 36

    private var share: Double {
        guard day.goal > 0, day.hasEntries else { return 0 }
        return min(Double(day.consumed) / Double(day.goal), 1)
    }

    /// Сколько сверх нормы, в долях нормы, не больше четверти.
    private var excess: Double {
        guard day.goal > 0, day.verdict == .over else { return 0 }
        return min(max(Double(day.consumed - day.goal) / Double(day.goal), 0), 0.25)
    }

    /// Мимо нормы в любую сторону — малиновым: недобор на дефиците такая же
    /// дыра, как перебор, и цветом нормы он читался бы как успех. Сторону
    /// видно по дуге: недобор короткий, у перебора тёмный конец.
    private var color: Color {
        switch day.verdict {
        case .over, .under: return ProgressRing.overColors[0]
        default: return ProgressRing.kcalColors[0]
        }
    }

    var body: some View {
        ZStack {
            if isToday {
                Circle()
                    .fill(Color(.secondarySystemGroupedBackground))
                    .shadow(color: .black.opacity(0.10), radius: 5, y: 2)
            }
            DayRingArcs(share: share, excess: excess, color: color,
                        overColor: ProgressRing.overColors[1],
                        arcShare: Self.arcShare, lineWidth: Self.lineWidth,
                        turn: Self.turn)
                // Поле под толщину и тень: Canvas обрезает всё, что выходит за
                // рамку, а кольцо рисует тень за её пределами. Тот же приём, что
                // у большого кольца: поле добавляется и тут же снимается.
                .padding(-Self.lineWidth)
                .padding(Self.lineWidth / 2)
            Text(verbatim: "\(number)")
                .font(.app(.caption, weight: isToday ? .bold : .semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .dynamicTypeSize(...DynamicTypeSize.xLarge)
        }
        .frame(width: Self.size, height: Self.size)
        .animation(.spring(response: 0.65, dampingFraction: 0.85), value: share)
    }
}

/// Дуги кольца недели с тем же объёмом, что у большого кольца и у иконки:
/// рецепт вынесен в `RubberArcRecipe`, здесь — только геометрия и цвета.
///
/// Дорожка плоская, как и у большого кольца: пустая часть не должна выглядеть
/// вещью. Доли отдаются системе как числа, поэтому пружина по `share` растит
/// дугу, а не перескакивает.
private struct DayRingArcs: View, Animatable {
    var share: Double
    var excess: Double
    let color: Color
    let overColor: Color
    let arcShare: Double
    let lineWidth: CGFloat
    /// Раскрытие сверху — то же, что у главного кольца.
    let turn: Double

    @Environment(\.colorScheme) private var scheme

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(share, excess) }
        set { share = newValue.first; excess = newValue.second }
    }

    var body: some View {
        Canvas { context, size in
            let lw = lineWidth
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            // Поле под тень больше рамки кольца на толщину дуги с каждой
            // стороны — радиус считается от рамки, а не от поля.
            let radius = (min(size.width, size.height) - 2 * lw) / 2
            let style = StrokeStyle(lineWidth: lw, lineCap: .round)

            /// Дуга от раскрытия по часовой, внутри рамки кольца.
            func arc(_ end: Double) -> Path {
                Path { p in
                    p.addArc(center: centre, radius: radius,
                             startAngle: .degrees(turn),
                             endAngle: .degrees(turn + 360 * max(0, min(end, 1))),
                             clockwise: false)
                }
            }
            func shift(_ dx: CGFloat, _ dy: CGFloat) -> CGSize {
                RubberArcRecipe.offset(dx, dy, compensating: turn)
            }

            // Дорожка — плоская, цветом дуги, приглушённым, как под макросами.
            context.stroke(arc(arcShare), with: .color(color.opacity(0.18)), style: style)

            var arcs: [(path: Path, colour: Color)] = []
            if share > 0 { arcs.append((path: arc(arcShare * share), colour: color)) }
            // Перебор — короткой тёмной дугой в начале красной: ровно насколько
            // вышло за норму, и вторым в списке, чтобы лицо легло поверх.
            if excess > 0 { arcs.append((path: arc(arcShare * excess), colour: overColor)) }
            guard !arcs.isEmpty else { return }

            let field = CGRect(x: -lw * 4, y: -lw * 4,
                               width: size.width + lw * 8, height: size.height + lw * 8)
            RubberArcRecipe.draw(&context, arcs: arcs, lineWidth: lw, style: style,
                                 field: field, centre: centre, radius: radius,
                                 dark: scheme == .dark, shift: shift)
        }
    }
}
