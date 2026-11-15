import SwiftUI

/// Из чего состоят калории порции: три цветных отрезка в одной полоске.
///
/// В строке продукта цвет макросов жил в трёх местах сразу: название красилось
/// в цвет ведущего макроса, под ним стояли цветные буквы «Б Ж У» с числами, а
/// число калорий красилось по плотности. Четыре цветовых кода без подписей, и
/// новичок не понимал, что значит зелёное «23». Теперь название и число
/// калорий чёрные, а цвет макросов остался в одном месте — здесь, и читается
/// без слов: чем длиннее отрезок, тем больше калорий из этого макроса.
///
/// Доли считаются по калориям, а не по граммам: грамм жира весит как два с
/// четвертью грамма белка, и по граммам масло выглядело бы почти нейтральным.
struct MacroShareBar: View {
    let macros: Macros
    var width: CGFloat = 36
    var height: CGFloat = 5

    private static let gap: CGFloat = 1.5

    /// Доли калорий по макросам в порядке «белки, жиры, углеводы»; нулевые
    /// отрезки не рисуются. Пусто, если макросов нет вовсе.
    static func shares(_ macros: Macros) -> [(kind: MacroKind, share: Double)] {
        let parts: [(MacroKind, Double)] = [
            (.protein, max(macros.protein, 0) * 4),
            (.fat, max(macros.fat, 0) * 9),
            (.carbs, max(macros.carbs, 0) * 4),
        ]
        let total = parts.reduce(0) { $0 + $1.1 }
        guard total > 0 else { return [] }
        return parts.filter { $0.1 > 0 }.map { (kind: $0.0, share: $0.1 / total) }
    }

    var body: some View {
        let shares = Self.shares(macros)
        if !shares.isEmpty {
            let free = width - Self.gap * CGFloat(shares.count - 1)
            HStack(spacing: Self.gap) {
                ForEach(shares, id: \.kind) { part in
                    Capsule()
                        .fill(part.kind.color)
                        // Не уже двух точек: доля в один-два процента иначе
                        // пропала бы вовсе, а её отсутствие читалось бы как ноль.
                        .frame(width: max(2, free * CGFloat(part.share)), height: height)
                }
            }
            .frame(width: width, alignment: .leading)
            // Голосом цвета не прочитать: доли — словами.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: shares
                .map { "\($0.kind.title) \(Int(($0.share * 100).rounded()))%" }
                .joined(separator: ", ")))
        }
    }
}
