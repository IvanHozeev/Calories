import SwiftUI

/// Значки витаминов и минералов, которыми продукт заметно богат, — рядом с
/// макросами в строке.
///
/// Смысл в том, чтобы состав считывался, не открывая продукт: «Ca K» у творога
/// видно боковым зрением, а «кальций 83 мг на 100 г» приходится читать и
/// сравнивать с нормой в уме.
///
/// Цвет здесь не украшение, а единственное отличие. Натрий — потолок, а не
/// цель: «богат натрием» это предупреждение, и зелёным вместе с кальцием он
/// стоять не может, иначе значок читается как достоинство.
struct MicroTags: View {
    let nutrients: [Micronutrient]
    /// Больше трёх не показываем: дальше они съедают строку, а различать
    /// продукты по четвёртому значку всё равно не выходит.
    var limit: Int = 3
    var compact: Bool = true

    var body: some View {
        HStack(spacing: compact ? 4 : 6) {
            ForEach(nutrients.prefix(limit)) { nutrient in
                MicroChip(nutrient: nutrient, compact: compact)
                    .accessibilityLabel(nutrient.title)
                    // Идентификатор не зависит от языка: тесты идут на английской
                    // локали, а подпись значка — химический символ.
                    .accessibilityIdentifier("microTag-\(nutrient.rawValue)")
            }
            if nutrients.count > limit {
                // Стрелка, а не плюс: плюс в этом приложении везде означает
                // «добавить», и в строке продукта читался бы как кнопка.
                overflowTag
                    .accessibilityLabel(Text("Ещё"))
            }
        }
    }

    private var overflowTag: some View {
        Image(systemName: "arrow.up")
            .font(.app(.caption2, weight: .bold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, compact ? 5 : 7)
            .padding(.vertical, 3)
            .chipSurface(tint: .secondary)
    }

}

/// Один значок вещества в стеклянной капсуле.
///
/// Своим типом, потому что он нужен в двух разных местах: строкой продукта,
/// где значков несколько подряд, и в списках состава — слева от названия.
/// Там и там это одна и та же вещь, и расходиться им нельзя.
///
/// Цвет здесь не украшение, а единственное отличие. Натрий — потолок, а не
/// цель: «богат натрием» это предупреждение, и зелёным вместе с кальцием он
/// стоять не может, иначе значок читается как достоинство.
struct MicroChip: View {
    let nutrient: Micronutrient
    var compact: Bool = true
    private var color: Color { nutrient.isCeiling ? .orange : .green }

    var body: some View {
        // Значку нужна его ширина целиком.
        //
        // В тесной строке SwiftUI сжимал его вместе с остальным, и «Fib» —
        // самый длинный из значков — переносился на две строки: «Fi» и «b»
        // под ним. Место здесь уступает название продукта, оно и так с
        // многоточием.
        Text(verbatim: nutrient.symbol)
            .font(.app(.caption2, weight: .bold))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(color)
            .padding(.horizontal, compact ? 5 : 7)
            .padding(.vertical, 3)
            .chipSurface(tint: color)
    }
}

/// Поверхность значка: стекло там, где оно не портит форму, краска там, где
/// портит.
///
/// Капсула значка высотой около двадцати точек, то есть со скруглением
/// вдвое меньше того, на котором системное стекло ещё держит форму. На
/// iOS 26 вокруг него вдобавок есть поле — а значков в строке три подряд, и
/// их поля складываются в серую кляксу под строкой. Поэтому стекло только
/// с 27, а цвет на нём остаётся за буквой: сам материал бесцветный, иначе
/// ряд значков снова станет самым пёстрым местом экрана.
struct ChipSurface: ViewModifier {
    let tint: Color

    func body(content: Content) -> some View {
        if #available(iOS 27, *) {
            content.liquidGlass(in: Capsule())
        } else {
            content.background(tint.opacity(0.12), in: Capsule())
        }
    }
}

extension View {
    /// Подложка значка: стекло там, где оно не портит форму.
    func chipSurface(tint: Color) -> some View {
        modifier(ChipSurface(tint: tint))
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        MicroTags(nutrients: [.calcium, .potassium, .vitaminB12])
        MicroTags(nutrients: [.iron, .magnesium, .zinc, .selenium])
        MicroTags(nutrients: [.sodium, .potassium])
    }
    .padding()
}
