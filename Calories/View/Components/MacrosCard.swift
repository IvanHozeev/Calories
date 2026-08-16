import SwiftUI

struct MacrosCard: View {
    let macros: Macros
    let proteinTarget: Double?
    let fatTarget: Double?
    let weightKg: Double?
    let suggestion: String?

    @State private var selectedMacro: MacroKind?
    @State private var visibleSuggestion: String?

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                macroColumn(.protein, value: macros.protein, color: .blue)
                    .popover(isPresented: Binding(
                        get: { selectedMacro == .protein },
                        set: { if !$0 { selectedMacro = nil } }
                    )) { macroPopover(.protein) }
                Divider().frame(height: 36)
                macroColumn(.fat, value: macros.fat, color: .orange)
                    .popover(isPresented: Binding(
                        get: { selectedMacro == .fat },
                        set: { if !$0 { selectedMacro = nil } }
                    )) { macroPopover(.fat) }
                Divider().frame(height: 36)
                macroColumn(.carbs, value: macros.carbs, color: .purple)
                    .popover(isPresented: Binding(
                        get: { selectedMacro == .carbs },
                        set: { if !$0 { selectedMacro = nil } }
                    )) { macroPopover(.carbs) }
            }

            if let proteinTarget, proteinTarget > 0 {
                let proteinMet = macros.protein >= proteinTarget
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text("Белок: \(Int(macros.protein.rounded())) из \(Int(proteinTarget.rounded())) г")
                            .font(.caption)
                            .foregroundStyle(proteinMet ? .green : .secondary)
                        if proteinMet {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(.green)
                        }
                        Spacer()
                    }
                    if !proteinMet {
                        ProgressView(value: macros.protein / proteinTarget)
                            .tint(.blue)
                    }
                }
            }

            if let s = visibleSuggestion {
                HStack(spacing: 6) {
                    Image(systemName: "lightbulb.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                    Text(s)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .transition(.opacity)
            }
        }
        // Нет .animation на всём VStack — иначе SwiftUI замеряет идеальный
        // (unconstrained) размер при анимации и временно расширяет контент ScrollView.
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .onAppear { visibleSuggestion = suggestion }
        .onChange(of: suggestion) { _, newValue in
            withAnimation(.easeInOut(duration: 0.3)) {
                visibleSuggestion = newValue
            }
        }
    }

    private func value(for kind: MacroKind) -> Double {
        switch kind {
        case .protein: return macros.protein
        case .fat: return macros.fat
        case .carbs: return macros.carbs
        }
    }

    private func macroColumn(_ kind: MacroKind, value: Double, color: Color) -> some View {
        Button {
            selectedMacro = kind
        } label: {
            VStack(spacing: 4) {
                Text(String(format: "%.0f г", value))
                    .font(.title3.bold())
                    .foregroundStyle(color)
                Text(kind.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func target(for kind: MacroKind) -> Double? {
        switch kind {
        case .protein: return proteinTarget
        case .fat: return fatTarget
        case .carbs: return MacroTargets.carbsMinimum
        }
    }

    private func note(for kind: MacroKind) -> String {
        switch kind {
        case .protein: return "Из профиля — норма белка на кг веса под твою цель."
        case .fat: return "≥0.8 г/кг — принятый минимум для гормонального здоровья."
        case .carbs: return "130 г/день — RDA, минимум глюкозы для работы мозга, не зависит от веса."
        }
    }

    private func macroPopover(_ kind: MacroKind) -> some View {
        let total = value(for: kind)
        let target = target(for: kind)

        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(kind.title)
                    .font(.headline)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Факт")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let weightKg, weightKg > 0 {
                        Text(String(format: "%.2f г/кг", total / weightKg))
                            .font(.title2.bold())
                        Text(String(format: "%.0f г при весе %.1f кг", total, weightKg))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(String(format: "%.0f г", total))
                            .font(.title2.bold())
                    }
                }

                Divider()

                if let target {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Цель" + (kind == .carbs ? " (минимум)" : ""))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if kind != .carbs, let weightKg, weightKg > 0 {
                            Text(String(format: "%.2f г/кг", target / weightKg))
                                .font(.title3.bold())
                            Text(String(format: "≈ %.0f г", target))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(String(format: "%.0f г", target))
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
