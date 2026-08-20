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
        default: smallView
        }
    }

    private var smallView: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 12)
            Circle()
                .trim(from: 0, to: entry.progress)
                .stroke(
                    LinearGradient(colors: ringColors, startPoint: .topLeading, endPoint: .bottomTrailing),
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
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
                    .stroke(Color.white.opacity(0.08), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: entry.progress)
                    .stroke(
                        LinearGradient(colors: ringColors, startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
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
        .supportedFamilies([.systemSmall, .systemMedium])
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
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
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
        default: smallView
        }
    }

    private var smallView: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 12)
            Circle()
                .trim(from: 0, to: entry.progress)
                .stroke(
                    LinearGradient(colors: ringColors, startPoint: .topLeading, endPoint: .bottomTrailing),
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
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
                    .stroke(Color.white.opacity(0.08), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: entry.progress)
                    .stroke(
                        LinearGradient(colors: ringColors, startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
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
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
