import SwiftUI

/// Цветные микро-теги Б/Ж/У. Строка вида «Б12 Ж22 У41» читается как сплошной текст —
/// чтобы понять состав, приходится всматриваться в цифры. Цвет позволяет считывать
/// перекос глазом: синий белок, оранжевый жиры, фиолетовые углеводы.
struct MacroTags: View {
    let macros: Macros
    var compact: Bool = false

    var body: some View {
        HStack(spacing: compact ? 8 : 10) {
            tag("Б", value: macros.protein, color: MacroKind.protein.color)
            tag("Ж", value: macros.fat, color: MacroKind.fat.color)
            tag("У", value: macros.carbs, color: MacroKind.carbs.color)
        }
    }

    private func tag(_ letter: LocalizedStringKey, value: Double, color: Color) -> some View {
        // Без цветных капсул: в стиле плашек под кольцом цвет несёт только
        // буква, и это цвет дуги макроса. Ряд капсул под каждой строкой
        // списка был самым пёстрым местом экрана.
        // Крупнее подписи: в списке съеденного и в поиске это второе по
        // важности число после калорий, а мелким шрифтом оно читалось как
        // сноска — приходилось вглядываться, чтобы понять, чем богат продукт.
        HStack(spacing: 3) {
            Text(letter)
                .font(.app(.footnote, weight: .bold))
                .foregroundStyle(color)
            Text(verbatim: "\(Int(value.rounded()))")
                .font(.app(.footnote, weight: .medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}
