import WidgetKit
import SwiftUI

private let appGroup = "group.calories.shared"

/// Числа за сегодня — только если записаны сегодня.
///
/// Приложение пишет съеденное, когда его открывают. Ночью никто его не
/// открывает, и после полуночи виджет показывал вчерашний день целиком. Если
/// записи за сегодня ещё нет, съеденное — ноль, а цели остаются вчерашними:
/// новую норму знает только приложение.
private func isToday(_ key: String, in defaults: UserDefaults?) -> Bool {
    guard let day = defaults?.object(forKey: key) as? Date else { return false }
    return Calendar.current.isDateInToday(day)
}

/// Расписание виджета: текущая запись и обнулённая в полночь, чтобы новый день
/// начинался с нуля, даже если до следующего обновления ещё далеко.
private func timeline<Entry: TimelineEntry>(now: Entry, midnight: Entry) -> Timeline<Entry> {
    let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
    return Timeline(entries: [now, midnight], policy: .after(next))
}

private var nextMidnight: Date {
    Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date())
}

// MARK: - Calories Widget

struct CaloriesEntry: TimelineEntry {
    let date: Date
    let consumed: Int
    let goal: Int
    let protein: Double
    let fat: Double
    let carbs: Double
    let proteinTarget: Double
    let fatTarget: Double
    let carbsTarget: Double

    var progress: Double {
        guard goal > 0 else { return 0 }
        return min(Double(consumed) / Double(goal), 1.0)
    }
    var remaining: Int { max(goal - consumed, 0) }

    /// Тот же знак, что на «Сегодня»: три дуги макросов, калории — числом.
    /// Отдельной раскладки «калории половиной круга» больше нет ни здесь, ни
    /// в приложении.
    var segments: [WidgetRingSegment] {
        WidgetRingLayout.mark(protein: protein, fat: fat, carbs: carbs,
                              proteinTarget: proteinTarget, fatTarget: fatTarget, carbsTarget: carbsTarget)
    }
}

struct CaloriesProvider: TimelineProvider {
    func placeholder(in context: Context) -> CaloriesEntry {
        CaloriesEntry(date: Date(), consumed: 1500, goal: 2400, protein: 110, fat: 45, carbs: 160,
                      proteinTarget: 160, fatTarget: 64, carbsTarget: 250)
    }

    func getSnapshot(in context: Context, completion: @escaping (CaloriesEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CaloriesEntry>) -> Void) {
        completion(timeline(now: loadEntry(), midnight: loadEntry(at: nextMidnight, fresh: true)))
    }

    private func loadEntry(at date: Date = Date(), fresh: Bool = false) -> CaloriesEntry {
        let defaults = UserDefaults(suiteName: appGroup)
        let current = !fresh && isToday("widget_day", in: defaults)
        let rawGoal = defaults?.integer(forKey: "widget_goal_today") ?? 0
        return CaloriesEntry(
            date: date,
            consumed: current ? defaults?.integer(forKey: "widget_consumed_today") ?? 0 : 0,
            goal: rawGoal > 0 ? rawGoal : 2000,
            protein: current ? defaults?.double(forKey: "widget_protein") ?? 0 : 0,
            fat: current ? defaults?.double(forKey: "widget_fat") ?? 0 : 0,
            carbs: current ? defaults?.double(forKey: "widget_carbs") ?? 0 : 0,
            proteinTarget: defaults?.double(forKey: "widget_protein_target") ?? 0,
            fatTarget: defaults?.double(forKey: "widget_fat_target") ?? 0,
            carbsTarget: defaults?.double(forKey: "widget_carbs_target") ?? 0
        )
    }
}

/// Кольцо «Сегодня» на домашнем экране и блокировке.
///
/// Раньше это было одно оранжевое кольцо калорий на коричневом фоне — чужое
/// приложению. Теперь виджет — то же кольцо, что на главном экране: калории на
/// половину круга, макросы делят вторую по граммам целей, в графите иконки.
struct CaloriesWidgetEntryView: View {
    var entry: CaloriesEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemMedium: mediumView
        case .accessoryCircular: circularView
        case .accessoryRectangular: rectangularView
        case .accessoryInline: inlineView
        default: smallView
        }
    }

    // MARK: - Экран блокировки
    //
    // Системные семейства рисуются одним цветом поверх обоев, поэтому здесь нет
    // ни градиентов, ни заливок из большого виджета: всё, что можно, — форма,
    // толщина и акцент. Показываем «осталось», а не «съедено»: на блокировке
    // смотрят, чтобы решить, есть ли ещё запас или уже нет.

    /// Тот же знак, одним цветом: форма узнаётся и без цвета.
    private var circularView: some View {
        ZStack {
            WidgetRing(segments: entry.segments, lineWidth: 5)
            Text(verbatim: "\(entry.remaining)")
                .font(.system(size: 13, weight: .semibold))
                .minimumScaleFactor(0.5)
                .padding(8)
        }
        .containerBackground(.clear, for: .widget)
    }

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "fork.knife")
                    .font(.caption)
                Text(verbatim: "\(entry.remaining) \(String(localized: "ккал"))")
                    .font(.headline)
            }
            .widgetAccentable()
            Text(verbatim: "\(entry.consumed) / \(entry.goal)")
                .font(.caption2)
            Gauge(value: entry.progress) { EmptyView() }
                .gaugeStyle(.accessoryLinearCapacity)
        }
        .containerBackground(.clear, for: .widget)
    }

    private var inlineView: some View {
        // Одна строка и один значок — больше система здесь не покажет.
        Label {
            Text(verbatim: "\(entry.remaining) \(String(localized: "ккал"))")
        } icon: {
            Image(systemName: "flame.fill")
        }
        .containerBackground(.clear, for: .widget)
    }

    // MARK: - Домашний экран

    private func ringWithRemaining(lineWidth: CGFloat, number: CGFloat,
                                   label: LocalizedStringKey = "Остаток") -> some View {
        ZStack {
            WidgetRing(segments: entry.segments, lineWidth: lineWidth)
            VStack(spacing: 0) {
                Text(verbatim: "\(entry.remaining)")
                    .font(.system(size: number, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text(label)
                    .font(.system(size: number * 0.4))
                    .foregroundStyle(.secondary)
            }
            .padding(lineWidth * 1.6)
        }
    }

    /// Малый: кольцо с остатком и под ним строка «съедено из». Остаток отвечает
    /// на «сколько ещё можно», а строка — откуда он взялся.
    private var smallView: some View {
        VStack(spacing: 4) {
            ringWithRemaining(lineWidth: 11, number: 24, label: "осталось")
            Text(verbatim: String(format: String(localized: "съедено %1$lld из %2$lld"),
                                  entry.consumed, entry.goal))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .containerBackground(for: .widget) { WidgetPalette.surface }
    }

    /// Ближайший приём из расписания — строкой под макросами. nil, когда
    /// расписание выключено или приложение ещё не рассказало о нём.
    private var nextMeal: MealSlotSnapshot? {
        MealFeed.shown(at: entry.date, in: MealFeed.slots())
    }

    private var mediumView: some View {
        // Кольцо на сорок процентов ширины и не выше самого виджета: размер
        // берём от него, а не числом в точках — средний виджет на разных
        // айфонах разной ширины.
        GeometryReader { geometry in
            let side = min(geometry.size.height, geometry.size.width * 0.42)
            HStack(spacing: 16) {
                ringWithRemaining(lineWidth: side * 0.11, number: side * 0.2, label: "осталось")
                    .frame(width: side, height: side)

                VStack(alignment: .leading, spacing: 9) {
                    Text(verbatim: String(format: String(localized: "съедено %1$lld из %2$lld ккал"),
                                          entry.consumed, entry.goal))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    VStack(spacing: 6) {
                        macroLine("Белки", color: WidgetPalette.protein[0], value: entry.protein, target: entry.proteinTarget)
                        macroLine("Жиры", color: WidgetPalette.fat[0], value: entry.fat, target: entry.fatTarget)
                        macroLine("Углеводы", color: WidgetPalette.carbs[0], value: entry.carbs, target: entry.carbsTarget)
                    }

                    if let meal = nextMeal {
                        mealLine(meal)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .containerBackground(for: .widget) { WidgetPalette.surface }
    }

    /// Строка макроса: точка цвета, название, число цветом и норма.
    ///
    /// Название — словом, а не буквой: в среднем виджете места хватает, и
    /// «Белки» читается без расшифровки.
    private func macroLine(_ name: LocalizedStringKey, color: Color, value: Double, target: Double) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(name)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(verbatim: "\(Int(value.rounded()))")
                .fontWeight(.bold)
                .foregroundStyle(color)
            if target > 0 {
                Text(verbatim: "/ \(Int(target.rounded()))")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 13))
        .monospacedDigit()
    }

    /// «Ужин до 20:30 · 640 ккал» под чертой: что дальше по расписанию.
    private func mealLine(_ meal: MealSlotSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle()
                .fill(.secondary.opacity(0.25))
                .frame(height: 1)
            HStack(spacing: 6) {
                Image(systemName: "fork.knife")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(verbatim: String(localized: String.LocalizationValue(meal.period)))
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                Text(verbatim: meal.calories > 0
                     ? String(format: String(localized: "до %@ · %lld ккал"),
                              (meal.isCurrent ? meal.end : meal.time).formatted(date: .omitted, time: .shortened),
                              meal.calories)
                     : (meal.isCurrent ? meal.end : meal.time).formatted(date: .omitted, time: .shortened))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .font(.system(size: 12))
            .monospacedDigit()
        }
    }
}

struct CaloriesWidget: Widget {
    let kind = "CaloriesWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CaloriesProvider()) { entry in
            CaloriesWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Калории")
        .description("Прогресс по калориям за день.")
        .supportedFamilies([.systemSmall, .systemMedium,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Steps Widget

struct StepsEntry: TimelineEntry {
    let date: Date
    let steps: Int
    let goal: Int
    let distanceKm: Double
    /// Семь дней, последний — сегодня. Пусто, пока приложение не отдало неделю.
    var week: [Int] = []

    var progress: Double {
        guard goal > 0 else { return 0 }
        return min(Double(steps) / Double(goal), 1.0)
    }

    /// Неделя, сдвинутая к дате записи: после полуночи приложение могли не
    /// открывать, и «последний» столбик в ней — ещё вчерашний. Сдвигаем влево
    /// на пройденные дни, дописываем нули, а сегодняшний — текущими шагами.
    static func alignedWeek(_ stored: [Int], storedDay: Date?, now: Date, todaySteps: Int) -> [Int] {
        guard stored.count == 7, let storedDay else { return [] }
        let calendar = Calendar.current
        let gap = calendar.dateComponents([.day], from: calendar.startOfDay(for: storedDay),
                                          to: calendar.startOfDay(for: now)).day ?? 0
        var week = stored
        if gap > 0 {
            week = Array(stored.dropFirst(min(gap, 7))) + Array(repeating: 0, count: min(gap, 7))
        }
        week[6] = todaySteps
        return week
    }
}

struct StepsProvider: TimelineProvider {
    func placeholder(in context: Context) -> StepsEntry {
        StepsEntry(date: Date(), steps: 6500, goal: 10_000, distanceKm: 4.8,
                          week: [8200, 10_400, 5200, 7800, 9100, 4900, 6500])
    }

    func getSnapshot(in context: Context, completion: @escaping (StepsEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StepsEntry>) -> Void) {
        completion(timeline(now: loadEntry(), midnight: loadEntry(at: nextMidnight, fresh: true)))
    }

    private func loadEntry(at date: Date = Date(), fresh: Bool = false) -> StepsEntry {
        let defaults = UserDefaults(suiteName: appGroup)
        let current = !fresh && isToday("widget_steps_day", in: defaults)
        let rawGoal = defaults?.integer(forKey: "widget_step_goal") ?? 0
        let goal = rawGoal > 0 ? rawGoal : 10_000
        let steps = current ? defaults?.integer(forKey: "widget_steps_today") ?? 0 : 0
        return StepsEntry(date: date,
                          steps: steps,
                          goal: goal,
                          distanceKm: current ? defaults?.double(forKey: "widget_distance_km") ?? 0 : 0,
                          week: StepsEntry.alignedWeek(defaults?.array(forKey: "widget_steps_week") as? [Int] ?? [],
                                                       storedDay: defaults?.object(forKey: "widget_steps_week_day") as? Date,
                                                       now: date, todaySteps: steps))
    }
}

struct StepsWidgetEntryView: View {
    var entry: StepsEntry
    @Environment(\.widgetFamily) var family
    @Environment(\.widgetRenderingMode) var renderingMode

    private var ringColors: [Color] { WidgetPalette.steps }
    /// То же поле, что у остальных виджетов и иконки: виджеты одного
    /// приложения не должны быть разноцветными плашками.
    private var bg: LinearGradient { WidgetPalette.surface }

    private var stepsSegment: [WidgetRingSegment] {
        [WidgetRingSegment(id: "steps", start: 0, end: 359.9, progress: entry.progress, colors: ringColors)]
    }

    var body: some View {
        switch family {
        case .systemMedium: mediumView
        case .accessoryCircular: circularView
        case .accessoryRectangular: rectangularView
        case .accessoryInline: inlineView
        default: smallView
        }
    }

    // MARK: - Экран блокировки

    private var circularView: some View {
        Gauge(value: entry.progress) {
            Image(systemName: "figure.walk")
        } currentValueLabel: {
            // Без разрядных пробелов и без сокращений: «6,5 тыс.» в круг не влезает
            // никаким кеглем, а «6500» — те же четыре знака, что и у калорий.
            Text(verbatim: entry.steps.formatted(.number.grouping(.never)))
                .minimumScaleFactor(0.4)
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .containerBackground(.clear, for: .widget)
    }

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "figure.walk")
                    .font(.caption)
                Text(verbatim: "\(entry.steps.formatted()) \(String(localized: "шагов"))")
                    .font(.headline)
            }
            .widgetAccentable()
            Text(verbatim: "\(String(localized: "из")) \(entry.goal.formatted())")
                .font(.caption2)
            Gauge(value: entry.progress) { EmptyView() }
                .gaugeStyle(.accessoryLinearCapacity)
        }
        .containerBackground(.clear, for: .widget)
    }

    private var inlineView: some View {
        Label {
            Text(verbatim: "\(entry.steps.formatted()) \(String(localized: "шагов"))")
        } icon: {
            Image(systemName: "figure.walk")
        }
        .containerBackground(.clear, for: .widget)
    }

    /// «из 8 000 · 4,6 км» — цель и, когда дистанция известна, она же.
    private var goalLine: String {
        let goal = entry.goal.formatted()
        guard entry.distanceKm > 0 else {
            return String(format: String(localized: "из %@"), goal)
        }
        return String(format: String(localized: "из %1$@ · %2$@ км"), goal,
                      entry.distanceKm.formatted(.number.precision(.fractionLength(1))))
    }

    /// Левая колонка: подпись, число, цель и полоска. Малый виджет — это она
    /// одна, средний — она плюс неделя столбиками.
    private var stepsColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "figure.walk")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ringColors[0])
                Text("Шаги")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.steps.formatted())
                    .font(.system(size: 34, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text(verbatim: goalLine)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
            WidgetBar(share: entry.progress, color: ringColors[0], height: 6)
        }
    }

    private var smallView: some View {
        stepsColumn
            .containerBackground(for: .widget) { bg }
    }

    private var mediumView: some View {
        HStack(alignment: .top, spacing: 16) {
            stepsColumn
                .frame(width: 140)
            weekChart
        }
        .containerBackground(for: .widget) { bg }
    }

    /// Неделя столбиками: день, в который цель взята, — цветом калорий, остальные
    /// — приглушённым акцентом, сегодня — акцентом целиком. Пунктир — цель.
    private var weekChart: some View {
        let week = entry.week.isEmpty ? Array(repeating: 0, count: 7) : entry.week
        let top = Double(max(week.max() ?? 0, Int(Double(entry.goal) * 1.2), 1))
        let calendar = Calendar.current
        return GeometryReader { geometry in
            let labelHeight: CGFloat = 16
            let chart = geometry.size.height - labelHeight
            let gap: CGFloat = 8
            let barWidth = (geometry.size.width - gap * 6) / 7
            ZStack(alignment: .topLeading) {
                // Цель — пунктиром на своей высоте.
                Path { path in
                    let y = chart * (1 - Double(entry.goal) / top)
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                }
                .stroke(Color.secondary.opacity(0.6),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [4, 5]))

                ForEach(0..<7, id: \.self) { index in
                    let steps = week[index]
                    let isToday = index == 6
                    let reached = steps >= entry.goal
                    let height = max(chart * Double(steps) / top, 4)
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(reached ? WidgetPalette.kcal[0] : ringColors[0].opacity(isToday ? 1 : 0.45))
                            .frame(width: barWidth, height: height)
                        let day = calendar.date(byAdding: .day, value: index - 6, to: entry.date) ?? entry.date
                        Text(day.formatted(.dateTime.weekday(.abbreviated)))
                            .font(.system(size: 10, weight: isToday ? .bold : .regular))
                            .foregroundStyle(isToday ? Color.primary : Color.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .frame(width: barWidth + gap, height: labelHeight)
                    }
                    .frame(width: barWidth + gap, height: geometry.size.height)
                    .offset(x: CGFloat(index) * (barWidth + gap) - gap / 2)
                }
            }
        }
    }

    /// Подпись — `LocalizedStringKey`, а не `String`: у `Text` инициализатор
    /// со строкой ничего не локализует, и «Съедено» показывалось по-русски
    /// на любом языке системы. Заметно это только на неродном языке, поэтому
    /// и прожило так долго.
    private func statRow(label: LocalizedStringKey, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
    }
}

struct StepsWidget: Widget {
    let kind = "StepsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StepsProvider()) { entry in
            StepsWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Шаги")
        .description("Количество шагов за день.")
        .supportedFamilies([.systemSmall, .systemMedium,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Macros Widget

/// Белки, жиры и углеводы за день.
///
/// Отдельный виджет, а не строка в калорийном: кольцо калорий отвечает на
/// «сколько ещё можно», а макросы — на «чем именно добирать». Для того, кто
/// держит белок, второй вопрос важнее первого, и держать его за одним нажатием
/// от экрана — смысл виджета.
struct MacrosEntry: TimelineEntry {
    let date: Date
    let protein: Double
    let fat: Double
    let carbs: Double
    let proteinTarget: Double
    let fatTarget: Double
    let carbsTarget: Double
    /// Клетчатка за день и её норма — строка под тремя макросами среднего
    /// виджета. Ноль у съеденного — «неизвестно», а не «не ел».
    var fiber: Double = 0
    var fiberTarget: Double = 0
}

struct MacrosProvider: TimelineProvider {
    func placeholder(in context: Context) -> MacrosEntry {
        MacrosEntry(date: Date(), protein: 120, fat: 40, carbs: 250,
                    proteinTarget: 160, fatTarget: 60, carbsTarget: 300,
                    fiber: 19, fiberTarget: 28)
    }

    func getSnapshot(in context: Context, completion: @escaping (MacrosEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MacrosEntry>) -> Void) {
        completion(timeline(now: loadEntry(), midnight: loadEntry(at: nextMidnight, fresh: true)))
    }

    private func loadEntry(at date: Date = Date(), fresh: Bool = false) -> MacrosEntry {
        let defaults = UserDefaults(suiteName: appGroup)
        let current = !fresh && isToday("widget_day", in: defaults)
        return MacrosEntry(
            date: date,
            protein: current ? defaults?.double(forKey: "widget_protein") ?? 0 : 0,
            fat: current ? defaults?.double(forKey: "widget_fat") ?? 0 : 0,
            carbs: current ? defaults?.double(forKey: "widget_carbs") ?? 0 : 0,
            proteinTarget: defaults?.double(forKey: "widget_protein_target") ?? 0,
            fatTarget: defaults?.double(forKey: "widget_fat_target") ?? 0,
            carbsTarget: defaults?.double(forKey: "widget_carbs_target") ?? 0,
            fiber: current ? defaults?.double(forKey: "widget_fiber") ?? 0 : 0,
            fiberTarget: defaults?.double(forKey: "widget_fiber_target") ?? 0
        )
    }
}

struct MacrosWidgetEntryView: View {
    var entry: MacrosEntry
    @Environment(\.widgetFamily) var family
    @Environment(\.widgetRenderingMode) var renderingMode

    private var bg: LinearGradient { WidgetPalette.surface }

    private struct Macro {
        /// Ключ для `ForEach` — русская буква как она записана в коде.
        /// Отдельно от подписи: подпись переводится, а идентификатор строки
        /// списка меняться от языка не должен.
        let id: String
        /// Подпись — ключ локализации: на английском это P/F/C, на иврите свои
        /// буквы. Раньше здесь была голая строка, и виджет показывал БЖУ
        /// на любом языке системы.
        let letter: LocalizedStringKey
        let value: Double
        let target: Double
        let color: Color
        /// Ноль означает «цели нет»: показываем факт, но не рисуем шкалу, чтобы
        /// пустая полоска не читалась как полный недобор.
        var hasTarget: Bool { target > 0 }
        var share: Double { target > 0 ? min(value / target, 1) : 0 }
    }

    private var macros: [Macro] {
        [
            Macro(id: "Б", letter: "Б", value: entry.protein, target: entry.proteinTarget, color: WidgetPalette.protein[0]),
            Macro(id: "Ж", letter: "Ж", value: entry.fat, target: entry.fatTarget, color: WidgetPalette.fat[0]),
            Macro(id: "У", letter: "У", value: entry.carbs, target: entry.carbsTarget, color: WidgetPalette.carbs[0])
        ]
    }

    var body: some View {
        switch family {
        case .systemSmall: smallView
        case .accessoryCircular: circularView
        case .accessoryRectangular: rectangularView
        case .accessoryInline: inlineView
        default: homeView
        }
    }

    // MARK: Домашний экран

    /// Подпись макроса — словом: на малом и среднем виджете места хватает, а
    /// буква «Б» без расшифровки читается только теми, кто её уже знает.
    private func title(_ macro: Macro) -> LocalizedStringKey {
        switch macro.id {
        case "Б": return "Белки"
        case "Ж": return "Жиры"
        default: return "Углеводы"
        }
    }

    /// Малый: три строки — точка и название, число цветом с нормой, полоска.
    private var smallView: some View {
        VStack(alignment: .leading, spacing: 13) {
            ForEach(macros, id: \.id) { macro in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline) {
                        HStack(spacing: 6) {
                            Circle().fill(macro.color).frame(width: 7, height: 7)
                            Text(title(macro))
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        HStack(spacing: 3) {
                            Text(verbatim: "\(Int(macro.value.rounded()))")
                                .fontWeight(.bold)
                                .foregroundStyle(macro.color)
                            if macro.hasTarget {
                                Text(verbatim: "/ \(Int(macro.target.rounded()))")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.system(size: 13))
                        .monospacedDigit()
                    }
                    if macro.hasTarget {
                        WidgetBar(share: macro.share, color: macro.color, height: 5)
                    }
                }
            }
        }
        .containerBackground(for: .widget) { bg }
    }

    /// Средний: три колонки — название, крупное число цветом, «из N г» и полоска;
    /// под чертой клетчатка с полоской.
    private var homeView: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(macros, id: \.id) { macro in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Circle().fill(macro.color).frame(width: 7, height: 7)
                            Text(title(macro))
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        Text(verbatim: "\(Int(macro.value.rounded()))")
                            .font(.system(size: 28, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(macro.color)
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                        if macro.hasTarget {
                            Text(verbatim: String(format: String(localized: "из %lld г"),
                                                  Int(macro.target.rounded())))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                            WidgetBar(share: macro.share, color: macro.color, height: 5)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Spacer(minLength: 6)
            fiberLine
        }
        .containerBackground(for: .widget) { bg }
    }

    /// Клетчатка под чертой. Без нормы или пока про день неизвестно — прочерк,
    /// а не «0 г»: ноль значил бы «не ел», а мы просто не знаем.
    @ViewBuilder
    private var fiberLine: some View {
        if entry.fiberTarget > 0 {
            VStack(spacing: 8) {
                Rectangle()
                    .fill(.secondary.opacity(0.25))
                    .frame(height: 1)
                HStack(spacing: 10) {
                    Text("Клетчатка")
                        .foregroundStyle(.secondary)
                    WidgetBar(share: min(entry.fiber / entry.fiberTarget, 1),
                              color: WidgetPalette.carbs[0], height: 5)
                    HStack(spacing: 3) {
                        Text(verbatim: entry.fiber > 0 ? "\(Int(entry.fiber.rounded()))" : "—")
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                        Text(verbatim: String(format: String(localized: "/ %lld г"),
                                              Int(entry.fiberTarget.rounded())))
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.system(size: 12))
                .monospacedDigit()
            }
        }
    }

    // MARK: Экран блокировки

    /// Белок: у того, кто следит за макросами, это обязательство, а углеводы —
    /// остаток. На круге помещается одно число, и это оно.
    private var circularView: some View {
        Gauge(value: macros[0].share) {
            Text("Б")
        } currentValueLabel: {
            Text(verbatim: "\(Int(entry.protein.rounded()))")
                .minimumScaleFactor(0.6)
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .containerBackground(.clear, for: .widget)
    }

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(macros, id: \.id) { macro in
                HStack(spacing: 4) {
                    Text(macro.letter)
                        .font(.caption2.weight(.bold))
                    Text(verbatim: "\(Int(macro.value.rounded()))")
                        .font(.caption2)
                        .monospacedDigit()
                    if macro.hasTarget {
                        Text(verbatim: "/ \(Int(macro.target.rounded()))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .widgetAccentable()
        .containerBackground(.clear, for: .widget)
    }

    private var inlineView: some View {
        Text(verbatim: "\(String(localized: "Б")) \(Int(entry.protein.rounded())) · \(String(localized: "Ж")) \(Int(entry.fat.rounded())) · \(String(localized: "У")) \(Int(entry.carbs.rounded()))")
            .containerBackground(.clear, for: .widget)
    }
}

struct MacrosWidget: Widget {
    let kind = "MacrosWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MacrosProvider()) { entry in
            MacrosWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Белки, жиры, углеводы")
        .description("Макросы за день и насколько закрыты нормы.")
        .supportedFamilies([.systemSmall, .systemMedium,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

/// Тонкая полоска прогресса, как под плашкой макросов в приложении: дорожка
/// того же цвета, приглушённая, без канавки и свечения.
struct WidgetBar: View {
    let share: Double
    let color: Color
    var height: CGFloat = 3
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(renderingMode == .fullColor ? color.opacity(0.22) : Color.white.opacity(0.25))
                Capsule()
                    .fill(renderingMode == .fullColor ? color : Color.white)
                    .frame(width: geometry.size.width * share)
                    .widgetAccentable()
            }
        }
        .frame(height: height)
    }
}
