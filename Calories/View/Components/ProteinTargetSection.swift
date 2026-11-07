import SwiftUI

/// Секция нормы белка: выбор основы (вес или сухая масса), пикер граммов на кг и итоговая строка.
struct ProteinTargetSection: View {
    @Binding var proteinBasis: ProteinBasis
    @Binding var proteinTenths: Int
    @Binding var proteinLeanTenths: Int
    @Binding var isPickerShown: Bool
    let leanMassKg: Double?
    let measurement: BodyMeasurement?
    let draftProfile: UserProfile?
    let footer: LocalizedStringKey
    /// Вызывается при переключении основы расчёта белка.
    let onBasisChanged: (ProteinBasis) -> Void
    /// Вызывается когда пикер белка показывается — вызывающая сторона сбрасывает
    /// остальные открытые пикеры (рост, возраст, жир).
    let onToggle: () -> Void

    var body: some View {
        Section {
            if leanMassKg != nil {
                Picker("Считать", selection: $proteinBasis) {
                    ForEach(ProteinBasis.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityIdentifier("proteinBasis")
                .onChange(of: proteinBasis) { _, basis in
                    onBasisChanged(basis)
                }
            }
            HStack {
                Text(proteinBasis == .leanMass ? "Белка на кг сухой массы" : "Белка на кг веса")
                Spacer()
                Text(String(format: "%.1f \(String(localized: "г/кг"))", Double(activeProteinTenths) / 10.0))
                    .foregroundStyle(.secondary)
            }
            .tappableRow {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isPickerShown.toggle()
                    if isPickerShown { onToggle() }
                }
            }
            if isPickerShown {
                Picker("Белок", selection: proteinBasis == .leanMass ? $proteinLeanTenths : $proteinTenths) {
                    ForEach(10...50, id: \.self) { Text(String(format: "%.1f", Double($0) / 10.0)).tag($0) }
                }
                .pickerStyle(.wheel)
                .frame(height: 160)
            }
            if let draftProfile {
                // Той же строкой, что и углеводы: граммы макроса цветом своего макроса.
                MacroBudgetRow("Итого белка",
                               grams: draftProfile.proteinTargetGrams(from: measurement),
                               color: MacroKind.protein.color)
            }
        } header: {
            Text("Норма белка")
        } footer: {
            Text(footer)
        }
    }

    private var activeProteinTenths: Int {
        proteinBasis == .leanMass ? proteinLeanTenths : proteinTenths
    }
}
