import SwiftUI

/// Строка одного дня в списке истории — дата, число приёмов пищи, итог и отклонение от цели.
struct DayRow: View {
    let day: DaySummary

    private var overGoal: Bool { day.totalCalories > day.goal }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(day.date, format: .dateTime.day().month(.wide))
                    .font(.body.weight(.medium))
                Text(verbatim: "\(day.entries.count) \(entriesLabel(day.entries.count))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(verbatim: "\(day.totalCalories) \(String(localized: "ккал"))")
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
        case 1 where n % 100 != 11: return String(localized: "приём пищи")
        case 2...4 where !(n % 100 >= 12 && n % 100 <= 14): return String(localized: "приёма пищи")
        default: return String(localized: "приёмов пищи")
        }
    }
}
