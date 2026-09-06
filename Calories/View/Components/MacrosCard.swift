import SwiftUI

struct MacrosCard: View {
    let macros: Macros
    let proteinTarget: Double?
    let fatTarget: Double?
    /// Остаток нормы после белка и жира. nil — целей ещё нет, показываем минимум.
    var carbsTarget: Double? = nil
    let weightKg: Double?

    @State private var selectedMacro: MacroKind?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // Три колонки на accessibility-размерах ломают слова посреди («Pro-tein»),
        // поэтому там раскладываем макросы строками.
        let isBig = dynamicTypeSize.isAccessibilitySize
        let layout = isBig
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout())
        return layout {
            macroColumn(.protein, value: macros.protein, color: .blue)
                .popover(isPresented: Binding(
                    get: { selectedMacro == .protein },
                    set: { if !$0 { selectedMacro = nil } }
                )) { macroPopover(.protein) }
            if !isBig { Divider().frame(height: 36) }
            macroColumn(.fat, value: macros.fat, color: .orange)
                .popover(isPresented: Binding(
                    get: { selectedMacro == .fat },
                    set: { if !$0 { selectedMacro = nil } }
                )) { macroPopover(.fat) }
            if !isBig { Divider().frame(height: 36) }
            macroColumn(.carbs, value: macros.carbs, color: .purple)
                .popover(isPresented: Binding(
                    get: { selectedMacro == .carbs },
                    set: { if !$0 { selectedMacro = nil } }
                )) { macroPopover(.carbs) }
        }
        .padding()
        .glassCard()
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
        return Button {
            selectedMacro = kind
        } label: {
            inner {
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func target(for kind: MacroKind) -> Double? {
        switch kind {
        case .protein: return proteinTarget
        case .fat: return fatTarget
        case .carbs: return carbsTarget ?? MacroTargets.carbsMinimum
        }
    }

    private func note(for kind: MacroKind) -> String {
        switch kind {
        case .protein: return String(localized: "Норма белка из профиля — от веса или от сухой массы, смотря что выбрано.")
        case .fat: return String(localized: "Норма жира из профиля. Ниже 0.5 г/кг рискуешь гормонами — жир нужен телу постоянно.")
        case .carbs: return carbsTarget == nil
            ? String(localized: "130 г/день — RDA, минимум глюкозы для работы мозга, не зависит от веса.")
            : String(localized: "Остаток дневной нормы после белка и жира — то, чем управляешь ты.")
        }
    }

    private func macroPopover(_ kind: MacroKind) -> some View {
        let total = value(for: kind)
        let target = target(for: kind)

        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(LocalizedStringKey(kind.title))
                    .font(.headline)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Факт")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let weightKg, weightKg > 0 {
                        Text(String(format: "%.2f \(String(localized: "г/кг"))", total / weightKg))
                            .font(.title2.bold())
                        Text(String(format: String(localized: "%.0f г при весе %.1f кг"), total, weightKg))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(String(format: "%.0f \(String(localized: "г"))", total))
                            .font(.title2.bold())
                    }
                }

                Divider()

                if let target {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(LocalizedStringKey(kind == .carbs ? "Цель (минимум)" : "Цель"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if kind != .carbs, let weightKg, weightKg > 0 {
                            Text(String(format: "%.2f \(String(localized: "г/кг"))", target / weightKg))
                                .font(.title3.bold())
                            Text(String(format: "≈ %.0f \(String(localized: "г"))", target))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(String(format: "%.0f \(String(localized: "г"))", target))
                                .font(.title3.bold())
                        }
                    }

                    Text(note(for: kind))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(kind == .protein
                         ? "Чтобы увидеть цель, заполни профиль."
                         : "Чтобы увидеть цель, укажи вес — в профиле или на экране «Вес».")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding()
        }
        .frame(width: 280)
        .presentationCompactAdaptation(.popover)
    }
}
