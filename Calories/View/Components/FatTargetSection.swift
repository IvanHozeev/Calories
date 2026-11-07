import SwiftUI

/// Норма жира и её границы.
struct FatTargetSection: View {
    @Binding var draft: ProfileDraft
    @Binding var openPicker: ProfilePicker?

    /// Что сказать, если жир вне рабочего коридора.
    private var warning: String? {
        let perKg = Double(draft.fatTenths) / 10
        if perKg < MacroTargets.fatComfortRange.lowerBound {
            return String(localized: "У нижней границы. Держать так можно недолго — в пике сушки, а не всю фазу.")
        }
        if perKg > MacroTargets.fatComfortRange.upperBound {
            return String(localized: "Много: каждый лишний грамм жира — это два с лишним грамма углеводов, которых не будет на тренировке.")
        }
        return nil
    }

    var body: some View {
        Section {
            HStack {
                Text("Жира на кг веса")
                Spacer()
                Text(String(format: "%.1f \(String(localized: "г/кг"))", Double(draft.fatTenths) / 10.0))
                    .foregroundStyle(.secondary)
            }
            .tappableRow {
                withAnimation(.easeInOut(duration: 0.2)) {
                    openPicker = openPicker == .fat ? nil : .fat
                }
            }

            if openPicker == .fat {
                Picker("Жир", selection: $draft.fatTenths) {
                    // Колесо ограничено жёсткими границами: за ними не бывает
                    // осознанного выбора, только промах пальцем.
                    ForEach(Int(MacroTargets.fatFloorPerKg * 10)...Int(MacroTargets.fatCeilingPerKg * 10),
                            id: \.self) { Text(String(format: "%.1f", Double($0) / 10.0)).tag($0) }
                }
                .pickerStyle(.wheel)
                .frame(height: 160)
            }

            MacroBudgetRow("Итого жира",
                           grams: draft.profile.fatTargetGrams,
                           color: MacroKind.fat.color)

            // Вне рабочего коридора число разрешено, но о нём сказано вслух.
            if let warning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.app(.caption))
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Норма жира")
        } footer: {
            explain("Рабочий коридор — 0.6–1.2 г на кг веса, обычно 0.8. Меньше 0.5 и больше 1.5 выставить нельзя: ниже это ставка на гормоны, выше жир вытесняет углеводы, на которых работают тренировки.").map { Text($0) }
        }
    }
}
