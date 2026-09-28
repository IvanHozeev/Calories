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
    /// Какой макрос сейчас ведущий — тот, что ещё не закрыт.
    ///
    /// Нужен не для расчёта, а для внимания: колонка ведущего чуть заметнее,
    /// а закрытие макроса видно как событие — иначе смена цвета по всему
    /// приложению читается как сбой, пока не поймаешь правило.
    var focus: MacroKind? = nil

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
                // Полоски ходят вместе с дугами кольца, той же пружиной.
                .animation(.spring(response: 0.65, dampingFraction: 0.85), value: macros)
                // Смена ведущего макроса — отдельное, более медленное
                // движение: это смена смысла, а не изменение числа.
                .animation(.easeInOut(duration: 0.5), value: focus)
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
        let isLeading = focus == kind
        return VStack(alignment: .leading, spacing: 3) {
            Text(LocalizedStringKey(kind.title))
                .font(.app(.caption2))
                // Подпись ведущего макроса — его цветом: приложение
                // подсказывает, куда смотреть, не добавляя ни строчки текста.
                .foregroundStyle(isLeading ? color : Color.secondary.opacity(0.6))
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(String(format: "%.0f", value))
                    .font(.app(.subheadline, weight: .semibold))
                    .foregroundStyle(color)
                    .contentTransition(.numericText())
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

