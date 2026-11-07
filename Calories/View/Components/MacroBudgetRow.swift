import SwiftUI

/// Одна строка итога макроса: название, спейсер, граммы цветом своего макроса.
///
/// Белок и жир заданы телом, углеводы — остаток нормы калорий. Все три итога
/// читаются как числа одного вида: граммы макроса, цветом своего макроса.
struct MacroBudgetRow: View {
    let title: LocalizedStringKey
    let grams: Double
    let color: Color

    init(_ title: LocalizedStringKey, grams: Double, color: Color) {
        self.title = title
        self.grams = grams
        self.color = color
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(verbatim: "\(Int(grams.rounded())) \(String(localized: "г"))")
                .font(.app(.body, weight: .semibold))
                .foregroundStyle(color)
        }
    }
}
