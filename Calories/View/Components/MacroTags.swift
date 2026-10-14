import SwiftUI

/// Цветные микро-теги Б/Ж/У. Строка вида «Б12 Ж22 У41» читается как сплошной текст —
/// чтобы понять состав, приходится всматриваться в цифры. Цвет позволяет считывать
/// перекос глазом: синий белок, оранжевый жиры, фиолетовые углеводы.
struct MacroTags: View {
    let macros: Macros
    var compact: Bool = false
    /// Чем продукт богат. Задаётся снаружи, когда судить надо не по
    /// показанной порции, а по продукту: «богат белком» — свойство творога,
    /// а не того, что его взяли двести грамм.
    var leading: MacroKind? = nil

    private var accent: MacroKind? { leading ?? macros.leadingKind }

    var body: some View {
        HStack(spacing: compact ? 8 : 10) {
            tag("Б", value: macros.protein, kind: .protein)
            tag("Ж", value: macros.fat, kind: .fat)
            tag("У", value: macros.carbs, kind: .carbs)
        }
    }

    private func tag(_ letter: LocalizedStringKey, value: Double, kind: MacroKind) -> some View {
        // Ведущий макрос — цветом и размером, остальные тихо серым.
        //
        // Раньше о ведущем говорила цветная полоска слева от строки, а все три
        // буквы были цветные независимо от того, чего в продукте много. Полоска
        // — отдельный знак, который надо выучить, и ряд строк с ней был самым
        // пёстрым местом экрана. Теперь отвечает сама цифра: та, ради которой
        // продукт и берут, крупнее и в своём цвете.
        let isLead = accent == kind
        let color = isLead ? kind.color : Color.secondary
        // Без цветных капсул: в стиле плашек под кольцом цвет несёт только
        // буква, и это цвет дуги макроса. Ряд капсул под каждой строкой
        // списка был самым пёстрым местом экрана.
        // Крупнее подписи: в списке съеденного и в поиске это второе по
        // важности число после калорий, а мелким шрифтом оно читалось как
        // сноска — приходилось вглядываться, чтобы понять, чем богат продукт.
        return HStack(spacing: 3) {
            Text(letter)
                .font(.app(isLead ? .subheadline : .footnote, weight: .bold))
                .foregroundStyle(color)
            Text(verbatim: "\(Int(value.rounded()))")
                .font(.app(isLead ? .subheadline : .footnote, weight: isLead ? .semibold : .medium))
                .foregroundStyle(color)
                .monospacedDigit()
        }
    }
}
