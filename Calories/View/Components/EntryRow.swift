import SwiftUI

struct EntryRow: View {
    let entry: FoodEntry

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.body)
                Text(verbatim: "\(String(localized: "Б"))\(Int(entry.macros.protein)) \(String(localized: "Ж"))\(Int(entry.macros.fat)) \(String(localized: "У"))\(Int(entry.macros.carbs)) · " + entry.date.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(verbatim: "\(entry.calories) \(String(localized: "ккал"))")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
