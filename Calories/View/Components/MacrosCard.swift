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
    /// Макросы на момент, когда открыли добавление еды: от них полоски
    /// доливаются, когда возвращаешься на «Сегодня». Без этого цифры и полоски
    /// просто оказывались другими — самое частое событие дня проходило молча.
    var revealFrom: Macros? = nil
    var revealTicket: Int = 0

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var shown: Macros?

    var body: some View {
        // Три колонки на accessibility-размерах ломают слова посреди («Pro-tein»),
        // поэтому там раскладываем макросы строками.
        let isBig = dynamicTypeSize.isAccessibilitySize
        let layout = isBig
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 14))
        let values = shown ?? macros
        return Button(action: onOpen) {
            HStack(spacing: 10) {
                layout {
                    macroColumn(.protein, value: values.protein, color: MacroKind.protein.color)
                    macroColumn(.fat, value: values.fat, color: MacroKind.fat.color)
                    macroColumn(.carbs, value: values.carbs, color: MacroKind.carbs.color)
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
        // Та же пауза и та же кривая, что у кольца: полоски и дуги — одно
        // событие, и расходиться по времени им нельзя.
        .onChange(of: revealTicket) { _, _ in
            guard let from = revealFrom else { return }
            shown = from
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(450))
                withAnimation(.easeOut(duration: 0.9)) { shown = nil }
            }
        }
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

