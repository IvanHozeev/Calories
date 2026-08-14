import SwiftUI

struct HistoryView: View {
    @ObservedObject var store: CalorieStore

    var body: some View {
        List {
            Section {
                WeeklyChartView(days: store.lastSevenDays)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section("Дни") {
                ForEach(store.historyDays) { day in
                    NavigationLink {
                        DayDetailView(store: store, date: day.date)
                    } label: {
                        DayRow(day: day)
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("История")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct DayRow: View {
    let day: DaySummary

    private var overGoal: Bool { day.totalCalories > day.goal }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(day.date, format: .dateTime.day().month(.wide))
                    .font(.body.weight(.medium))
                Text(day.entries.isEmpty ? "Нет записей" : "\(day.entries.count) приёмов пищи")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if day.entries.isEmpty {
                Image(systemName: "plus.circle")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(day.totalCalories) ккал")
                        .font(.subheadline.weight(.semibold))
                    Text(overGoal ? "+\(day.difference)" : "\(day.difference)")
                        .font(.caption)
                        .foregroundStyle(overGoal ? .red : .green)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
