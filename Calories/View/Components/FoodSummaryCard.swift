import SwiftUI

/// Карточка итога вверху экрана порции и всех редакторов: калории, под ними
/// цена ста граммов, макросы и полоска долей.
///
/// Одна на все экраны. Раньше у каждого была своя: в дневнике калории
/// зеленели, у блюда и продукта в «Рационе» стоял другой кегль, и три
/// строки «0 г» не прятались. Теперь число белое, макрос, округлившийся до
/// нуля, пропадает (это делает `MacrosRow`), а полоска без подписей — они уже
/// стоят над числами.
struct FoodSummaryCard: View {
    let calories: Int
    /// Строка под числом — «388 ккал / 100 г». nil — не показывать.
    var densityLine: String? = nil
    let macros: Macros

    var body: some View {
        VStack(spacing: 4) {
            VStack(spacing: 2) {
                Text(verbatim: "\(calories) \(String(localized: "ккал"))")
                    .font(.app(size: 26, weight: .bold))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                if let densityLine {
                    Text(verbatim: densityLine)
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }

            MacrosRow(macros: macros)

            MacroSplitBar(macros: macros, showsLabels: false)
                .padding(.top, 2)
                .padding(.horizontal, 4)
        }
        .frame(maxWidth: .infinity)
    }
}
