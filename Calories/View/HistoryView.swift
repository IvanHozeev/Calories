import SwiftUI

struct HistoryView: View {
    var store: CalorieStore

    private var loggedDays: [DaySummary] {
        store.historyDays.filter { !$0.entries.isEmpty }
    }

    var body: some View {
        List {
            Section {
                ForEach(loggedDays) { day in
                    NavigationLink {
                        DayDetailView(store: store, date: day.date)
                    } label: {
                        DayRow(day: day)
                    }
                }
            }
            .listSectionSeparator(.hidden, edges: .top)
        }
        .listStyle(.insetGrouped)
        .navigationTitle("История")
        .navigationBarTitleDisplayMode(.large)
    }
}

struct DayRow: View {
    let day: DaySummary

    private var overGoal: Bool { day.totalCalories > day.goal }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(day.date, format: .dateTime.day().month(.wide))
                    .font(.body.weight(.medium))
                Text("\(day.entries.count) \(entriesLabel(day.entries.count))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(day.totalCalories) ккал")
                    .font(.subheadline.weight(.semibold))
                Text(overGoal ? "+\(day.difference)" : "\(day.difference)")
                    .font(.caption)
                    .foregroundStyle(overGoal ? .red : .green)
            }
        }
        .padding(.vertical, 4)
    }

    private func entriesLabel(_ n: Int) -> String {
        switch n % 10 {
        case 1 where n % 100 != 11: return "приём пищи"
        case 2...4 where !(n % 100 >= 12 && n % 100 <= 14): return "приёма пищи"
        default: return "приёмов пищи"
        }
    }
}
