import SwiftUI

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
            : AnyLayout(HStackLayout())
        return Button(action: onOpen) {
            HStack(spacing: 8) {
                layout {
                    macroColumn(.protein, value: macros.protein, color: .blue)
                    if !isBig { Divider().frame(height: 36) }
                    macroColumn(.fat, value: macros.fat, color: .orange)
                    if !isBig { Divider().frame(height: 36) }
                    macroColumn(.carbs, value: macros.carbs, color: .purple)
                }
                // Шеврон как у остальных карточек: без него непонятно, что
                // карточка вообще куда-то ведёт — раньше она открывала попапы.
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassCard()
        .accessibilityIdentifier("openDayNutrition")
    }

    private func value(for kind: MacroKind) -> Double {
        switch kind {
        case .protein: return macros.protein
        case .fat: return macros.fat
        case .carbs: return macros.carbs
        }
    }

    private func macroColumn(_ kind: MacroKind, value: Double, color: Color) -> some View {
        let isBig = dynamicTypeSize.isAccessibilitySize
        let inner: AnyLayout = isBig
            ? AnyLayout(HStackLayout(spacing: 8))
            : AnyLayout(VStackLayout(spacing: 4))
        return inner {
                Text(String(format: "%.0f \(String(localized: "г"))", value))
                    .font(.title3.bold())
                    .foregroundStyle(color)
                // Съеденное без цели — просто число: непонятно, много это или мало.
                // Цель мелким шрифтом под ним, чтобы не спорить с самим значением.
                if let target = target(for: kind) {
                    Text(verbatim: "/ \(Int(target.rounded()))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
                Text(LocalizedStringKey(kind.title))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if isBig { Spacer(minLength: 0) }
            }
        .frame(maxWidth: .infinity, alignment: isBig ? Alignment.leading : Alignment.center)
    }

    private func target(for kind: MacroKind) -> Double? {
        switch kind {
        case .protein: return proteinTarget
        case .fat: return fatTarget
        case .carbs: return carbsTarget ?? MacroTargets.carbsMinimum
        }
    }
}
