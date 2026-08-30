import SwiftUI

/// Строка съеденного за день. Калории — главное число строки, поэтому они крупные
/// и тёмные, а не серые справа. Макросы идут цветными тегами, как и везде в приложении,
/// вместо слипшегося «Б6 Ж31 У58».
struct EntryRow: View {
    let entry: FoodEntry
    /// Значки категорий всех продуктов приёма пищи. Место под них занято всегда,
    /// даже когда значков нет: иначе названия строк поедут по левому краю.
    var icons: [String] = []

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var hasMacros: Bool {
        entry.protein > 0 || entry.fat > 0 || entry.carbs > 0
    }

    private var portionText: String? {
        guard let grams = entry.grams, grams > 0 else { return nil }
        return String(format: "%.0f \(String(localized: "г"))", grams)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Больше трёх не показываем: дальше значки съедают место у названия,
            // а различать приёмы пищи по четвёртой иконке всё равно не выходит.
            HStack(spacing: 3) {
                ForEach(icons.prefix(3), id: \.self) { icon in
                    Image(systemName: icon)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 44, height: 20, alignment: .leading)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(entry.name)
                    .font(.body)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text(entry.date, format: .dateTime.hour().minute())
                    if let portionText {
                        Text(verbatim: "·")
                        Text(verbatim: portionText)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if hasMacros {
                    MacroTags(macros: entry.macros, compact: true)
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 1) {
                Text(verbatim: "\(entry.calories)")
                    .font(.headline)
                    .monospacedDigit()
                Text("ккал")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}
