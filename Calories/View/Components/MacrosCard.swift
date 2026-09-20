import SwiftUI

/// Макросы за день одной стеклянной плашкой под кольцом.
///
/// В стиле строки плана и недели: без белой карточки, тихо, цвет — только у
/// цифр и тонких полосок, и это те же цвета, что у дуг кольца. Белая карточка
/// с крупными системными цветами была самым тяжёлым пятном под кольцом.
struct MacrosCard: View {
    let macros: Macros
    let proteinTarget: Double?
    let fatTarget: Double?
    /// Остаток нормы после белка и жира. nil — целей ещё нет, показываем минимум.
    var carbsTarget: Double? = nil
    let weightKg: Double?
    /// Открыть разбор дня. Раньше на карточке жили три всплывающих окошка —
    /// по одному на макрос. Их приходилось открывать по очереди, сравнить их
    /// между собой было нельзя, а витаминам в таком формате места нет вовсе.
    var onOpen: () -> Void = {}

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // Три колонки на accessibility-размерах ломают слова посреди («Pro-tein»),
        // поэтому там раскладываем макросы строками.
        let isBig = dynamicTypeSize.isAccessibilitySize
        let layout = isBig
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 14))
        return Button(action: onOpen) {
            HStack(spacing: 10) {
                layout {
                    macroColumn(.protein, value: macros.protein, color: MacroKind.protein.color)
                    macroColumn(.fat, value: macros.fat, color: MacroKind.fat.color)
                    macroColumn(.carbs, value: macros.carbs, color: MacroKind.carbs.color)
                }
                // Шеврон как у строки плана: без него непонятно, что плашка
                // куда-то ведёт.
                Image(systemName: "chevron.right")
                    .font(.app(.caption2, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .liquidGlass(in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("openDayNutrition")
    }

    private func macroColumn(_ kind: MacroKind, value: Double, color: Color) -> some View {
        let target = target(for: kind)
        let progress = target.map { $0 > 0 ? min(value / $0, 1) : 0 } ?? 0
        return VStack(alignment: .leading, spacing: 3) {
            Text(LocalizedStringKey(kind.title))
                .font(.app(.caption2))
                .foregroundStyle(.tertiary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(String(format: "%.0f", value))
                    .font(.app(.subheadline, weight: .semibold))
                    .foregroundStyle(color)
                // Цель мелко рядом, чтобы не спорить с самим значением.
                if let target {
                    Text(verbatim: "/ \(Int(target.rounded()))")
                        .font(.app(.caption2))
                        .foregroundStyle(.tertiary)
                }
                Text("г")
                    .font(.app(.caption2))
                    .foregroundStyle(.tertiary)
            }
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            // Полоска вместо разделителей: как далеко до цели, тем же цветом,
            // что дуга макроса в кольце.
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.18))
                    Capsule().fill(color)
                        .frame(width: geometry.size.width * progress)
                }
            }
            .frame(height: 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func target(for kind: MacroKind) -> Double? {
        switch kind {
        case .protein: return proteinTarget
        case .fat: return fatTarget
        case .carbs: return carbsTarget ?? MacroTargets.carbsMinimum
        }
    }
}

