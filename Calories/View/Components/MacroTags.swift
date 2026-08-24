import SwiftUI

/// Цветные микро-теги Б/Ж/У. Строка вида «Б12 Ж22 У41» читается как сплошной текст —
/// чтобы понять состав, приходится всматриваться в цифры. Цвет позволяет считывать
/// перекос глазом: синий белок, оранжевый жиры, фиолетовые углеводы.
struct MacroTags: View {
    let macros: Macros
    var compact: Bool = false

    var body: some View {
        HStack(spacing: compact ? 4 : 6) {
            tag("Б", value: macros.protein, color: .blue)
            tag("Ж", value: macros.fat, color: .orange)
            tag("У", value: macros.carbs, color: .purple)
        }
    }

    private func tag(_ letter: LocalizedStringKey, value: Double, color: Color) -> some View {
        HStack(spacing: 3) {
            Text(letter)
                .font(.caption2.weight(.bold))
                .foregroundStyle(color)
            Text(verbatim: "\(Int(value.rounded()))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, compact ? 5 : 7)
        .padding(.vertical, 3)
        .background(color.opacity(0.12), in: Capsule())
    }
}
