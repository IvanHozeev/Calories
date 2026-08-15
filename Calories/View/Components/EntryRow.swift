import SwiftUI

struct EntryRow: View {
    let entry: FoodEntry
    let onDelete: () -> Void
    var onEdit: (() -> Void)? = nil

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

            if let onEdit {
                Button {
                    onEdit()
                } label: {
                    Image(systemName: "pencil")
                        .foregroundStyle(.blue)
                        .imageScale(.medium)
                }
                .buttonStyle(.plain)
            }

            Button {
                withAnimation { onDelete() }
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red)
                    .imageScale(.medium)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }
}
