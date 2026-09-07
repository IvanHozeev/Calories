import WidgetKit
import SwiftUI

private let appGroup = "group.calories.shared"

// MARK: - Calories Widget

struct CaloriesEntry: TimelineEntry {
    let date: Date
    let consumed: Int
    let goal: Int

    var progress: Double {
        guard goal > 0 else { return 0 }
        return min(Double(consumed) / Double(goal), 1.0)
    }
    var remaining: Int { max(goal - consumed, 0) }
}

struct CaloriesProvider: TimelineProvider {
    func placeholder(in context: Context) -> CaloriesEntry {
        CaloriesEntry(date: Date(), consumed: 1500, goal: 2000)
    }

    func getSnapshot(in context: Context, completion: @escaping (CaloriesEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CaloriesEntry>) -> Void) {
        let entry = loadEntry()
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func loadEntry() -> CaloriesEntry {
        let defaults = UserDefaults(suiteName: appGroup)
        let consumed = defaults?.integer(forKey: "widget_consumed_today") ?? 0
        let rawGoal = defaults?.integer(forKey: "widget_goal_today") ?? 0
        let goal = rawGoal > 0 ? rawGoal : 2000
        return CaloriesEntry(date: Date(), consumed: consumed, goal: goal)
    }
}

struct CaloriesWidgetEntryView: View {
    var entry: CaloriesEntry
    @Environment(\.widgetFamily) var family

    private let ringColors: [Color] = [.orange, Color(red: 1, green: 0.75, blue: 0)]
    private let bg = LinearGradient(
        colors: [Color(red: 0.18, green: 0.07, blue: 0.00), Color(red: 0.10, green: 0.04, blue: 0.00)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

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

    private var circularView: some View {
        Gauge(value: entry.progress) {
            Image(systemName: "flame.fill")
        } currentValueLabel: {
            Text(verbatim: "\(entry.remaining)")
                .minimumScaleFactor(0.4)
        }
        .gaugeStyle(.accessoryCircularCapacity)
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

    private var smallView: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 6)
            Circle()
                .trim(from: 0, to: entry.progress)
                .stroke(
                    LinearGradient(colors: ringColors, startPoint: .topLeading, endPoint: .bottomTrailing),
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: .orange.opacity(0.5), radius: 6)

            VStack(spacing: 2) {
                Text("\(entry.consumed)")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
                Text("ккал")
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
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: entry.progress)
                    .stroke(
                        LinearGradient(colors: ringColors, startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: .orange.opacity(0.5), radius: 5)

                VStack(spacing: 2) {
                    Text("\(entry.consumed)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.5)
                    Text("ккал")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                        .textCase(.uppercase)
                        .tracking(0.5)
                }
            }
            .frame(width: 88, height: 88)

            VStack(alignment: .leading, spacing: 0) {
                Text("Калории")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.bottom, 8)

                statRow(label: "Съедено", value: "\(entry.consumed) ккал")
                Spacer().frame(height: 5)
                statRow(label: "Цель", value: "\(entry.goal) ккал")
                Spacer().frame(height: 5)
                statRow(label: "Остаток", value: "\(entry.remaining) ккал")

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.1))
                            .frame(height: 4)
                        Capsule()
                            .fill(LinearGradient(colors: ringColors, startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * entry.progress, height: 4)
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

    private func statRow(label: String, value: String) -> some View {
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
        let entry = loadEntry()
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func loadEntry() -> StepsEntry {
        let defaults = UserDefaults(suiteName: appGroup)
        let steps = defaults?.integer(forKey: "widget_steps_today") ?? 0
        let rawGoal = defaults?.integer(forKey: "widget_step_goal") ?? 0
        let goal = rawGoal > 0 ? rawGoal : 10_000
        let distanceKm = defaults?.double(forKey: "widget_distance_km") ?? 0
        return StepsEntry(date: Date(), steps: steps, goal: goal, distanceKm: distanceKm)
    }
}

struct StepsWidgetEntryView: View {
    var entry: StepsEntry
    @Environment(\.widgetFamily) var family

    private let ringColors: [Color] = [Color(red: 0.2, green: 0.6, blue: 1.0), .cyan]
    private let bg = LinearGradient(
        colors: [Color(red: 0.03, green: 0.08, blue: 0.22), Color(red: 0.01, green: 0.04, blue: 0.14)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

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
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 6)
            Circle()
                .trim(from: 0, to: entry.progress)
                .stroke(
                    LinearGradient(colors: ringColors, startPoint: .topLeading, endPoint: .bottomTrailing),
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: .blue.opacity(0.6), radius: 6)

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
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: entry.progress)
                    .stroke(
                        LinearGradient(colors: ringColors, startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: .blue.opacity(0.6), radius: 5)

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
                    statRow(label: "Дистанция", value: String(format: "%.1f км", entry.distanceKm))
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.1))
                            .frame(height: 4)
                        Capsule()
                            .fill(LinearGradient(colors: ringColors, startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * entry.progress, height: 4)
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

    private func statRow(label: String, value: String) -> some View {
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
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        completion(Timeline(entries: [loadEntry()], policy: .after(next)))
    }

    private func loadEntry() -> MacrosEntry {
        let defaults = UserDefaults(suiteName: appGroup)
        return MacrosEntry(
            date: Date(),
            protein: defaults?.double(forKey: "widget_protein") ?? 0,
            fat: defaults?.double(forKey: "widget_fat") ?? 0,
            carbs: defaults?.double(forKey: "widget_carbs") ?? 0,
            proteinTarget: defaults?.double(forKey: "widget_protein_target") ?? 0,
            fatTarget: defaults?.double(forKey: "widget_fat_target") ?? 0,
            carbsTarget: defaults?.double(forKey: "widget_carbs_target") ?? 0
        )
    }
}

struct MacrosWidgetEntryView: View {
    var entry: MacrosEntry
    @Environment(\.widgetFamily) var family

    private let bg = LinearGradient(
        colors: [Color(red: 0.06, green: 0.09, blue: 0.18), Color(red: 0.03, green: 0.05, blue: 0.10)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    private struct Macro {
        let letter: String
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
            Macro(letter: "Б", value: entry.protein, target: entry.proteinTarget, color: .blue),
            Macro(letter: "Ж", value: entry.fat, target: entry.fatTarget, color: .orange),
            Macro(letter: "У", value: entry.carbs, target: entry.carbsTarget, color: .purple)
        ]
    }

    var body: some View {
        switch family {
        case .accessoryCircular: circularView
        case .accessoryRectangular: rectangularView
        case .accessoryInline: inlineView
        default: homeView
        }
    }

    // MARK: Домашний экран

    private var homeView: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(macros, id: \.letter) { macro in
                row(macro)
            }
        }
        .padding(.vertical, 2)
        .containerBackground(for: .widget) { bg }
    }

    private func row(_ macro: Macro) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(verbatim: macro.letter)
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
                        Capsule().fill(.white.opacity(0.15))
                        Capsule()
                            .fill(macro.color)
                            .frame(width: geometry.size.width * macro.share)
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
            Text(verbatim: "Б")
        } currentValueLabel: {
            Text(verbatim: "\(Int(entry.protein.rounded()))")
                .minimumScaleFactor(0.6)
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .containerBackground(.clear, for: .widget)
    }

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(macros, id: \.letter) { macro in
                HStack(spacing: 4) {
                    Text(verbatim: macro.letter)
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
        Text(verbatim: "Б \(Int(entry.protein.rounded())) · Ж \(Int(entry.fat.rounded())) · У \(Int(entry.carbs.rounded()))")
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
