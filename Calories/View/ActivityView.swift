import SwiftUI

/// Экран дисциплины и достижений. Раньше жил приватной структурой внутри ContentView
/// и смешивал две несовместимые вещи: эмоциональную часть (стрик, награды) и сухой
/// архив записей. Теперь архив тоже визуальный — календарь месяца либо карточки дней
/// с мини-баром и макросами, вместо строки «22 августа · 2706 ккал · −336».
struct ActivityView: View {
    let store: CalorieStore

    @State private var historyMode: HistoryMode = .calendar
    @State private var selectedAchievement: Achievement?
    @State private var selectedDay: Date?

    enum HistoryMode: String, CaseIterable, Identifiable {
        case calendar, list
        var id: String { rawValue }
        var title: String {
            switch self {
            case .calendar: return String(localized: "Календарь")
            case .list: return String(localized: "Список")
            }
        }
    }

    private var loggedDays: [DaySummary] {
        store.historyDays.filter { !$0.entries.isEmpty }
    }

    var body: some View {
        List {
            Section {
                streakHero
            }
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            Section("Награды") {
                achievementsStrip
            }
            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            Section {
                Picker("Вид", selection: $historyMode) {
                    ForEach(HistoryMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("История")
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            if historyMode == .calendar {
                Section {
                    MonthGrid(days: store.goalHistory(days: 35)) { date in
                        selectedDay = date
                    }
                    .padding(.vertical, 8)
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else if loggedDays.isEmpty {
                Section {
                    Text("Здесь появятся прошедшие дни")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(loggedDays) { day in
                        NavigationLink {
                            DayDetailView(store: store, date: day.date)
                        } label: {
                            HistoryDayCard(day: day)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollIndicators(.hidden)
        .navigationTitle("Активность")
        .navigationDestination(item: $selectedDay) { date in
            DayDetailView(store: store, date: date)
        }
        .sheet(item: $selectedAchievement) { achievement in
            AchievementSheet(achievement: achievement)
                .presentationDetents([.height(340)])
        }
    }

    // MARK: - Верх: стрик

    private var milestoneColor: Color {
        if store.streak >= 100 { return Color(red: 1, green: 0.75, blue: 0) }
        if store.streak >= 30 { return .red }
        if store.streak >= 7 { return .orange }
        return store.streak > 0 ? .orange : .secondary
    }

    private var streakLabel: String {
        let s = store.streak
        switch s % 10 {
        case 1 where s % 100 != 11: return String(localized: "день подряд")
        case 2...4 where !(s % 100 >= 12 && s % 100 <= 14): return String(localized: "дня подряд")
        default: return s == 0 ? String(localized: "начни серию сегодня") : String(localized: "дней подряд")
        }
    }

    private var motivationalText: String {
        if store.streak >= 30 { return String(localized: "Продолжай в том же духе — ты уже пример для других!") }
        if store.streak >= 7 { return String(localized: "Продолжай в том же духе — ты в отличной форме!") }
        if store.streak > 0 { return String(localized: "Продолжай в том же духе — каждый день на счету!") }
        return String(localized: "Начни сегодня — первый шаг уже завтра станет серией!")
    }

    private var streakHero: some View {
        VStack(spacing: 18) {
            VStack(spacing: 4) {
                // Огонь и цифра в один ряд: столбиком карточка съедала пол-экрана
                // и отодвигала ленту дней с наградами за фолд.
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 46))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [milestoneColor, milestoneColor.opacity(0.55)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    Text("\(store.streak)")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .foregroundStyle(milestoneColor)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                Text(streakLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if store.bestStreak > store.streak && store.bestStreak > 0 {
                    Label("Рекорд: \(store.bestStreak) дней", systemImage: "trophy.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.yellow)
                }
            }

            DayStrip(days: store.streakHistory)

            Text(motivationalText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .glassCard(cornerRadius: 20)
    }

    // MARK: - Награды

    private var achievementsStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(store.achievements) { achievement in
                    Button {
                        selectedAchievement = achievement
                    } label: {
                        AchievementCard(achievement: achievement)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Лента дней

/// Крупная лента последних дней. Прежние кружки по 20pt с подписями в 8pt
/// прочитать было невозможно, поэтому ячейки увеличены и получили цифру числа.
private struct DayStrip: View {
    let days: [(date: Date, hasEntries: Bool, onGoal: Bool)]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(days.suffix(7), id: \.date) { day in
                let isToday = Calendar.current.isDateInToday(day.date)
                VStack(spacing: 6) {
                    Text(weekdayLetter(day.date))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    ZStack {
                        Circle()
                            .fill(color(for: day).opacity(day.onGoal || day.hasEntries ? 1 : 0.35))
                        if day.onGoal {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                        } else {
                            Text("\(Calendar.current.component(.day, from: day.date))")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(day.hasEntries ? .white : .secondary)
                        }
                    }
                    .frame(width: 36, height: 36)
                    .overlay(
                        isToday
                            ? Circle().stroke(Color.primary.opacity(0.6), lineWidth: 2)
                            : nil
                    )
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func color(for day: (date: Date, hasEntries: Bool, onGoal: Bool)) -> Color {
        if day.onGoal { return .green }
        if day.hasEntries { return .orange }
        return Color(.systemGray4)
    }

    private func weekdayLetter(_ date: Date) -> String {
        let weekday = Calendar.current.component(.weekday, from: date)
        return Calendar.current.veryShortWeekdaySymbols[weekday - 1]
    }
}

// MARK: - Календарь месяца

/// Сетка последних пяти недель. Даёт то, чего не даёт список: картину месяца целиком —
/// где шли подряд зелёные дни, а где провалы.
private struct MonthGrid: View {
    let days: [(date: Date, hasEntries: Bool, onGoal: Bool)]
    var onSelect: (Date) -> Void

    private let calendar = Calendar.current

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
    }

    /// Подписи колонок в порядке, принятом в локали пользователя:
    /// в Израиле и США неделя начинается с воскресенья, в Европе с понедельника.
    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }

    /// Сколько пустых ячеек добавить в начало, чтобы первый день попал в свою колонку.
    private var leadingBlanks: Int {
        guard let first = days.first?.date else { return 0 }
        let weekday = calendar.component(.weekday, from: first)
        return (weekday - calendar.firstWeekday + 7) % 7
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(0..<leadingBlanks, id: \.self) { _ in
                    Color.clear.frame(height: 34)
                }

                ForEach(days, id: \.date) { day in
                    let isToday = calendar.isDateInToday(day.date)
                    Button {
                        guard day.hasEntries else { return }
                        onSelect(day.date)
                    } label: {
                        Text("\(calendar.component(.day, from: day.date))")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(day.hasEntries ? .white : .secondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                            .background(color(for: day), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                isToday
                                    ? RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.6), lineWidth: 2)
                                    : nil
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!day.hasEntries)
                }
            }

            HStack(spacing: 14) {
                legend(.green, "В цели")
                legend(.orange, "Мимо цели")
                legend(Color(.systemGray5), "Пропуск")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private func legend(_ color: Color, _ title: LocalizedStringKey) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .frame(width: 10, height: 10)
            Text(title)
        }
    }

    private func color(for day: (date: Date, hasEntries: Bool, onGoal: Bool)) -> Color {
        if day.onGoal { return .green }
        if day.hasEntries { return .orange }
        return Color(.systemGray5)
    }
}

// MARK: - Карточка дня в истории

/// Показывает не только итог, но и причину: полоса заполнения по калориям
/// и три тега макросов, чтобы сразу было видно, за счёт чего вышел перебор.
private struct HistoryDayCard: View {
    let day: DaySummary

    private var fill: Double {
        guard day.goal > 0 else { return 0 }
        return min(Double(day.totalCalories) / Double(day.goal), 1)
    }

    private var overGoal: Bool { day.totalCalories > day.goal }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(day.date, format: .dateTime.day().month(.wide))
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(verbatim: "\(day.totalCalories) \(String(localized: "ккал"))")
                    .font(.subheadline.weight(.semibold))
                Text(overGoal ? "+\(day.difference)" : "\(day.difference)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(overGoal ? .red : .green)
                    .monospacedDigit()
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(.systemGray5))
                    Capsule()
                        .fill(overGoal ? Color.red : Color.green)
                        .frame(width: max(4, geo.size.width * fill))
                }
            }
            .frame(height: 6)

            HStack(spacing: 6) {
                macroTag("Б", value: day.totalMacros.protein, color: .blue)
                macroTag("Ж", value: day.totalMacros.fat, color: .orange)
                macroTag("У", value: day.totalMacros.carbs, color: .purple)
            }
        }
        .padding(.vertical, 6)
    }

    private func macroTag(_ letter: LocalizedStringKey, value: Double, color: Color) -> some View {
        HStack(spacing: 3) {
            Text(letter)
                .font(.caption2.weight(.bold))
                .foregroundStyle(color)
            Text(verbatim: "\(Int(value.rounded()))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(color.opacity(0.12), in: Capsule())
    }
}

// MARK: - Награды

private struct AchievementCard: View {
    let achievement: Achievement

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: achievement.icon)
                .font(.title2)
                .foregroundStyle(achievement.isUnlocked ? achievement.tint : Color(.systemGray3))

            Text(achievement.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(achievement.isUnlocked ? .primary : .secondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 0)

            if achievement.isUnlocked {
                Label("Получено", systemImage: "checkmark.circle.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(achievement.tint)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: achievement.progress)
                        .tint(achievement.tint)
                    Text(verbatim: "\(achievement.current)/\(achievement.target)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .frame(width: 132, height: 130, alignment: .leading)
        .padding(14)
        .glassCard()
    }
}

private struct AchievementSheet: View {
    let achievement: Achievement
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: achievement.icon)
                .font(.system(size: 52))
                .foregroundStyle(achievement.isUnlocked ? achievement.tint : Color(.systemGray3))
                .padding(.top, 28)

            Text(achievement.title)
                .font(.title2.bold())

            Text(achievement.requirement)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            if achievement.isUnlocked {
                Label("Получено", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(achievement.tint)
            } else {
                VStack(spacing: 6) {
                    ProgressView(value: achievement.progress)
                        .tint(achievement.tint)
                    Text(verbatim: "\(achievement.current)/\(achievement.target)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .padding(.horizontal, 40)
            }

            Spacer()

            Button("Закрыть") { dismiss() }
                .font(.body.weight(.semibold))
                .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity)
    }
}
