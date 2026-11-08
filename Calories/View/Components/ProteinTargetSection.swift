import SwiftUI

/// Норма белка: на чём считать и сколько.
struct ProteinTargetSection: View {
    @Binding var draft: ProfileDraft
    @Binding var openPicker: ProfilePicker?
    let measurement: BodyMeasurement?

    /// Сухая масса известна только по снятым замерам — без них персональный
    /// режим предлагать нечестно, он молча посчитает то же самое от веса.
    private var leanMassKg: Double? { draft.profile.leanMassKg(from: measurement) }

    private var footer: LocalizedStringKey {
        if leanMassKg == nil {
            return "Обычно 1.6–2.2 г на кг веса. Заполни замеры — и норму можно будет считать от сухой массы, а не от общего веса."
        }
        return draft.proteinBasis == .leanMass
            ? "Для сухой массы диапазон другой — обычно 2.2–3.0 г на кг: сухой массы меньше, чем веса, а кормишь ты именно её."
            : "Обычно 1.6–2.2 г на кг веса. От сухой массы точнее: при одном весе на 12% и на 25% жира мышц разное количество, а кормишь ты мышцы."
    }

    var body: some View {
        Section {
            if leanMassKg != nil {
                Picker("Считать", selection: $draft.proteinBasis) {
                    ForEach(ProteinBasis.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityIdentifier("proteinBasis")
                .onChange(of: draft.proteinBasis) { _, basis in
                    if basis == .leanMass { draft.seedLeanProteinIfNeeded(leanMassKg: leanMassKg) }
                }
            }

            HStack {
                Text(draft.proteinBasis == .leanMass ? "Белка на кг сухой массы" : "Белка на кг веса")
                Spacer()
                Text(String(format: "%.1f \(String(localized: "г/кг"))", Double(draft.activeProteinTenths) / 10.0))
                    .foregroundStyle(.secondary)
            }
            .tappableRow {
                withAnimation(.easeInOut(duration: 0.2)) {
                    openPicker = openPicker == .protein ? nil : .protein
                }
            }

            if openPicker == .protein {
                Picker("Белок", selection: draft.proteinBasis == .leanMass ? $draft.proteinLeanTenths : $draft.proteinTenths) {
                    ForEach(10...50, id: \.self) { Text(String(format: "%.1f", Double($0) / 10.0)).tag($0) }
                }
                .pickerStyle(.wheel)
                .frame(height: 160)
            }

            // Той же строкой, что и углеводы ниже: три итога одного вида —
            // граммы макроса — и читаться они должны одинаково, цветом
            // своего макроса. Белок и жир стояли чёрными, а углеводы
            // фиолетовыми, будто это числа из разных мест.
            MacroBudgetRow("Итого белка",
                           grams: draft.profile.proteinTargetGrams(from: measurement),
                           color: MacroKind.protein.color)
        } header: {
            Text("Норма белка")
                .tracksSectionHead(String(localized: "Норма белка"))
        } footer: {
            Text(footer)
        }
    }
}
