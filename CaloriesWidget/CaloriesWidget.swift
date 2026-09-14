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

    var segments: [WidgetRingSegment] {
        WidgetRingLayout.today(consumed: consumed, goal: goal, protein: protein, fat: fat, carbs: carbs,
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

    /// То же кольцо, одним цветом: форма узнаётся и без цвета.
    private var circularView: some View {
        ZStack {
            WidgetRing(segments: entry.segments, lineWidth: 5, rotation: -40)
            Text(verbatim: "\(entry.remaining)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
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

    private func ringWithRemaining(lineWidth: CGFloat, number: CGFloat) -> some View {
        ZStack {
            WidgetRing(segments: entry.segments, lineWidth: lineWidth, rotation: -40)
            VStack(spacing: 0) {
                Text(verbatim: "\(entry.remaining)")
                    .font(.system(size: number, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text("Остаток")
                    .font(.system(size: number * 0.38, weight: .semibold))
                    .foregroundStyle(WidgetPalette.kcal[0])
            }
            .padding(lineWidth * 1.6)
        }
    }

    private var smallView: some View {
        ringWithRemaining(lineWidth: 11, number: 26)
            .padding(-2)
            .containerBackground(for: .widget) { WidgetPalette.graphite }
    }

    private var mediumView: some View {
        HStack(spacing: 18) {
            ringWithRemaining(lineWidth: 10, number: 22)
                .frame(width: 118, height: 118)

            VStack(alignment: .leading, spacing: 7) {
                statRow(letter: "ккал", color: WidgetPalette.kcal[0], value: entry.consumed, target: Double(entry.goal))
                statRow(letter: "Б", color: WidgetPalette.protein[0], value: Int(entry.protein.rounded()), target: entry.proteinTarget)
                statRow(letter: "Ж", color: WidgetPalette.fat[0], value: Int(entry.fat.rounded()), target: entry.fatTarget)
                statRow(letter: "У", color: WidgetPalette.carbs[0], value: Int(entry.carbs.rounded()), target: entry.carbsTarget)
            }
            Spacer(minLength: 0)
        }
        .containerBackground(for: .widget) { WidgetPalette.graphite }
    }

    /// Подпись — `LocalizedStringKey`, а не `String`: у `Text` инициализатор
    /// со строкой ничего не локализует, и подпись показывалась по-русски
    /// на любом языке системы.
    private func statRow(letter: LocalizedStringKey, color: Color, value: Int, target: Double) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(letter)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 30, alignment: .leading)
            Text(verbatim: "\(value)")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
            if target > 0 {
                Text(verbatim: "/ \(Int(target.rounded()))")
                    .font(.system(size: 11, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.45))
            }
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

    var progress: Double {
        guard goal > 0 else { return 0 }
        return min(Double(steps) / Double(goal), 1.0)
    }
}

struct StepsProvider: TimelineProvider {
    func placeholder(in context: Context) -> StepsEntry {
        StepsEntry(date: Date(), steps: 6500, goal: 10_000, distanceKm: 4.8)
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
        return StepsEntry(date: date,
                          steps: current ? defaults?.integer(forKey: "widget_steps_today") ?? 0 : 0,
                          goal: goal,
                          distanceKm: current ? defaults?.double(forKey: "widget_distance_km") ?? 0 : 0)
    }
}

struct StepsWidgetEntryView: View {
    var entry: StepsEntry
    @Environment(\.widgetFamily) var family
    @Environment(\.widgetRenderingMode) var renderingMode

    private let ringColors: [Color] = WidgetPalette.steps
    /// Графит, как у иконки и кольца калорий: виджеты одного приложения
    /// не должны быть разноцветными плашками.
    private var bg: LinearGradient { WidgetPalette.graphite }

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

    private var smallView: some View {
        ZStack {
            WidgetRing(segments: stepsSegment, lineWidth: 11)

            VStack(spacing: 2) {
                Text(entry.steps.formatted())
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
                Text("шагов")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                    .textCase(.uppercase)
                    .tracking(0.5)
            }
        }
        .containerBackground(for: .widget) { bg }
    }

    private var mediumView: some View {
        HStack(spacing: 18) {
            ZStack {
                WidgetRing(segments: stepsSegment, lineWidth: 9)

                VStack(spacing: 2) {
                    Text(entry.steps.formatted())
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.5)
                    Text("шагов")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                        .textCase(.uppercase)
                        .tracking(0.5)
                }
            }
            .frame(width: 88, height: 88)

            VStack(alignment: .leading, spacing: 0) {
                Text("Шаги")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.bottom, 8)

                statRow(label: "Пройдено", value: entry.steps.formatted())
                Spacer().frame(height: 5)
                statRow(label: "Цель", value: entry.goal.formatted())
                if entry.distanceKm > 0 {
                    Spacer().frame(height: 5)
                    statRow(label: "Дистанция", value: String(format: "%.1f \(String(localized: "км"))", entry.distanceKm))
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(WidgetEngraving.channel(thickness: 4, mode: renderingMode))
                            .frame(height: 4)
                        Capsule()
                            .fill(LinearGradient(colors: ringColors, startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * entry.progress, height: 4)
                            .shadow(color: ringColors[1].opacity(0.3), radius: 3)
                    }
                }
                .frame(height: 4)
                .padding(.top, 10)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .containerBackground(for: .widget) { bg }
    }

    /// Подпись — `LocalizedStringKey`, а не `String`: у `Text` инициализатор
    /// со строкой ничего не локализует, и «Съедено» показывалось по-русски
    /// на любом языке системы. Заметно это только на неродном языке, поэтому
    /// и прожило так долго.
    private func statRow(label: LocalizedStringKey, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
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
}

struct MacrosProvider: TimelineProvider {
    func placeholder(in context: Context) -> MacrosEntry {
        MacrosEntry(date: Date(), protein: 120, fat: 40, carbs: 250,
                    proteinTarget: 160, fatTarget: 60, carbsTarget: 300)
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
            carbsTarget: defaults?.double(forKey: "widget_carbs_target") ?? 0
        )
    }
}

struct MacrosWidgetEntryView: View {
    var entry: MacrosEntry
    @Environment(\.widgetFamily) var family
    @Environment(\.widgetRenderingMode) var renderingMode

    private var bg: LinearGradient { WidgetPalette.graphite }

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
        case .systemSmall: markView
        case .accessoryCircular: circularView
        case .accessoryRectangular: rectangularView
        case .accessoryInline: inlineView
        default: homeView
        }
    }

    // MARK: Знак

    /// Маленький — знак приложения «С», только живой: каждая дуга залита по
    /// своему макросу. В середине белок — у того, кто держит макросы, это
    /// обязательство, а остальное — остаток.
    private var markView: some View {
        ZStack {
            WidgetRing(segments: WidgetRingLayout.mark(
                protein: entry.protein, fat: entry.fat, carbs: entry.carbs,
                proteinTarget: entry.proteinTarget, fatTarget: entry.fatTarget, carbsTarget: entry.carbsTarget),
                       lineWidth: 11, fillsFromEnd: true)
            VStack(spacing: 0) {
                Text(verbatim: "\(Int(entry.protein.rounded()))")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
                if entry.proteinTarget > 0 {
                    Text(verbatim: "/ \(Int(entry.proteinTarget.rounded()))")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.45))
                }
                Text("Б")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(WidgetPalette.protein[0])
            }
            .padding(18)
        }
        .padding(-2)
        .containerBackground(for: .widget) { bg }
    }

    // MARK: Домашний экран

    private var homeView: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(macros, id: \.id) { macro in
                row(macro)
            }
        }
        .padding(.vertical, 2)
        .containerBackground(for: .widget) { bg }
    }

    private func row(_ macro: Macro) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(macro.letter)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(macro.color)
                Text(verbatim: "\(Int(macro.value.rounded()))")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                if macro.hasTarget {
                    Text(verbatim: "/ \(Int(macro.target.rounded()))")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                        .monospacedDigit()
                }
                Spacer(minLength: 0)
            }
            if macro.hasTarget {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(WidgetEngraving.channel(thickness: 5, mode: renderingMode))
                        Capsule()
                            .fill(macro.color)
                            .frame(width: geometry.size.width * macro.share)
                            .shadow(color: macro.color.opacity(0.3), radius: 3)
                    }
                }
                .frame(height: 5)
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
