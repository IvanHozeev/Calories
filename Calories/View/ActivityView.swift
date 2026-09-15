import SwiftUI

/// История дней: календарь месяца или карточки дней.
///
/// Раньше это был экран «Активность» за огоньком в тулбаре: серия, награды,
/// неделя макросов и только в самом низу — прошедшие дни. Заходили туда ради
/// последнего. Серия переехала подписью к полоске недели на «Сегодня», неделя
/// макросов живёт в разборе дня, а здесь осталась только история.
struct ActivityView: View {
    let store: CalorieStore

    @State private var historyMode: HistoryMode = .calendar
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
                Picker("Вид", selection: $historyMode) {
                    ForEach(HistoryMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
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
        .glassRow()
        .listStyle(.insetGrouped)
        .scrollIndicators(.hidden)
        .navigationTitle("История")
        .navigationDestination(item: $selectedDay) { date in
            DayDetailView(store: store, date: date)
        }
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
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }

                // Идентификаторы обязаны различаться по всей сетке, а не внутри
                // своего ForEach: у подписей колонок это были 0…6, у пустых
                // ячеек — те же 0…N, и SwiftUI считал их одной ячейкой.
                // Строка вместо числа разводит их гарантированно.
                ForEach((0..<leadingBlanks).map { "blank-\($0)" }, id: \.self) { _ in
                    Color.clear.frame(height: 40)
                }

                ForEach(days, id: \.date) { day in
                    let isToday = calendar.isDateInToday(day.date)
                    // Как неделя на «Сегодня»: число без плашки, цвет — точкой
                    // под ним, сегодня жирным. Сетка залитых квадратов была
                    // тяжелее всего остального приложения.
                    Button {
                        guard day.hasEntries else { return }
                        onSelect(day.date)
                    } label: {
                        VStack(spacing: 3) {
                            Text(verbatim: "\(calendar.component(.day, from: day.date))")
                                .font(.subheadline.weight(isToday ? .bold : .regular))
                                .monospacedDigit()
                                .foregroundStyle(isToday ? .primary : (day.hasEntries ? .secondary : .tertiary))
                            Circle()
                                .fill(color(for: day))
                                .frame(width: 5, height: 5)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!day.hasEntries)
                }
            }

            HStack(spacing: 14) {
                legend(ProgressRing.kcalColors[0], "В цели")
                legend(.orange, "Мимо цели")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private func legend(_ color: Color, _ title: LocalizedStringKey) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(title)
        }
    }

    private func color(for day: (date: Date, hasEntries: Bool, onGoal: Bool)) -> Color {
        if day.onGoal { return ProgressRing.kcalColors[0] }
        if day.hasEntries { return .orange }
        return .clear
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

            // Как полоски на «Сегодня»: тонко и плоско, цвет — кольца.
            let barColor = overGoal ? Color.orange : ProgressRing.kcalColors[0]
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(barColor.opacity(0.18))
                    Capsule()
                        .fill(barColor)
                        .frame(width: max(4, geo.size.width * fill))
                }
            }
            .frame(height: 4)

            MacroTags(macros: day.totalMacros)
        }
        .padding(.vertical, 6)
    }

}
