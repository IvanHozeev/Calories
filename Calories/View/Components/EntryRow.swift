import SwiftUI

/// Строка съеденного за день. Калории — главное число строки, поэтому они крупные
/// и тёмные, а не серые справа. Макросы идут цветными тегами, как и везде в приложении,
/// вместо слипшегося «Б6 Ж31 У58».
struct EntryRow: View {
    let entry: FoodEntry
    /// Чем запись заметно богата. Считает стор — строке неоткуда знать состав.
    var micros: [Micronutrient] = []

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var hasMacros: Bool {
        entry.protein > 0 || entry.fat > 0 || entry.carbs > 0
    }

    /// Вес порции.
    ///
    /// У приёма из нескольких продуктов своего веса нет — он лежит у
    /// составляющих, и раньше строка молчала о весе вовсе. Складываем их, но
    /// только когда вес известен у всех: сумма двух из трёх — не вес приёма,
    /// а полуправда.
    private var portionText: String? {
        if let grams = entry.grams, grams > 0 {
            return String(format: "%.0f \(String(localized: "г"))", grams)
        }
        let parts = entry.components
        guard !parts.isEmpty, parts.allSatisfy({ ($0.grams ?? 0) > 0 }) else { return nil }
        let total = parts.reduce(0.0) { $0 + ($1.grams ?? 0) }
        return String(format: "%.0f \(String(localized: "г"))", total)
    }

    var body: some View {
        // Два уровня вместо трёх: название с калориями сверху, всё остальное
        // одной серой строкой под ним.
        //
        // Раньше уровней было три — название, подписи, макросы, — плюс
        // «ккал» отдельной строкой справа: ячейка занимала вдвое больше, чем
        // в ней было смысла, и в день помещалось четыре записи вместо восьми.
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.app(.subheadline))
                    .lineLimit(1)

                // Вес — одной серой подписью под названием.
                //
                // Времени здесь больше нет: оно ушло в заголовок приёма пищи,
                // где раньше дублировались калории единственной строки. Значков
                // категорий тоже: вилка у приёма и корзина у своего продукта
                // ничего не говорили о съеденном, а строку занимали.
                if let portionText {
                    Text(verbatim: portionText)
                        .foregroundStyle(.tertiary)
                        .font(.app(.caption))
                        .lineLimit(1)
                }

                // Макросы — своей строкой. В одну кучу с временем и порцией
                // они слипались: это числа, которые читают, а не подпись,
                // которую пробегают глазом. Место экономим на пустоте, а не
                // на том, ради чего в строку и смотрят.
                if hasMacros || !micros.isEmpty {
                    HStack(spacing: 8) {
                        if hasMacros {
                            MacroTags(macros: entry.macros, compact: true)
                        }
                        if !micros.isEmpty {
                            MicroTags(nutrients: micros)
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            // «ккал» строчной подписью рядом с числом, а не под ним: слово
            // одно на весь список и повторять его столбиком незачем.
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(verbatim: "\(entry.calories)")
                    .font(.app(.subheadline, weight: .semibold))
                    .monospacedDigit()
                Text("ккал")
                    .font(.app(.caption2))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}
