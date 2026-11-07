import SwiftUI

/// Секция нормы жира: пикер граммов на кг веса, итоговая строка и предупреждение.
///
/// Жир настраивается отдельным колёсным пикером в рабочем коридоре 0.6–1.2 г/кг.
struct FatTargetSection: View {
    @Binding var fatTenths: Int
    @Binding var isPickerShown: Bool
    let draftProfile: UserProfile?
    let warning: String?
    /// Вызывается когда пикер жира показывается — вызывающая сторона сбрасывает
    /// остальные открытые пикеры (белок, рост, возраст).
    let onToggle: () -> Void

    var body: some View {
        Section {
            HStack {
                Text("Жира на кг веса")
                Spacer()
                Text(String(format: "%.1f \(String(localized: "г/кг"))", Double(fatTenths) / 10.0))
                    .foregroundStyle(.secondary)
            }
            .tappableRow {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isPickerShown.toggle()
                    if isPickerShown { onToggle() }
                }
            }
            if isPickerShown {
                Picker("Жир", selection: $fatTenths) {
                    // Колесо ограничено жёсткими границами: за ними не бывает
                    // осознанного выбора, только промах пальцем.
                    ForEach(Int(MacroTargets.fatFloorPerKg * 10)...Int(MacroTargets.fatCeilingPerKg * 10),
                            id: \.self) { Text(String(format: "%.1f", Double($0) / 10.0)).tag($0) }
                }
                .pickerStyle(.wheel)
                .frame(height: 160)
            }
            if let draftProfile {
                // Той же строкой, что и углеводы: граммы макроса цветом своего макроса.
                MacroBudgetRow("Итого жира",
                               grams: draftProfile.fatTargetGrams,
                               color: MacroKind.fat.color)
            }
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
