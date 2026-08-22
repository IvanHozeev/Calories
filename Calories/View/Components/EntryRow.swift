import SwiftUI

struct EntryRow: View {
    let entry: FoodEntry

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.body)
                Text("Б\(Int(entry.macros.protein)) Ж\(Int(entry.macros.fat)) У\(Int(entry.macros.carbs)) · " + entry.date.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(entry.calories) ккал")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
