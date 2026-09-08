import SwiftUI

/// Одна фаза плана: зачем она и с какой скоростью.
///
/// Отдельным экраном, а не строкой с тремя контролами: у фазы три параметра,
/// и втиснутые в одну строку они превращаются в головоломку — особенно темп,
/// который надо ещё и сопоставить с прогнозом веса.
struct PlanPhaseEditorView: View {
    @Binding var phase: PlanPhase
    /// Вес, с которого фаза стартует. Нужен, чтобы показать проценты
    /// в килограммах: «0.7% в неделю» ничего не говорит, пока не видно,
    /// что это 560 граммов.
    let startWeightKg: Double

    private var weeklyKg: Double { phase.weeklyRateKg(fromWeightKg: startWeightKg) }

    private var endWeightKg: Double {
        startWeightKg + weeklyKg * Double(phase.durationWeeks)
    }

    var body: some View {
        Form {
            Section {
                Picker("Зачем", selection: $phase.intent) {
                    ForEach(PlanIntent.allCases) { intent in
                        Text(intent.title).tag(intent)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .listRowBackground(Color.clear)
                // Темп при смене намерения берётся типичный для него: 0.7% на
                // сушке и 0.7% на наборе — очень разные заявления.
                .onChange(of: phase.intent) { _, newIntent in
                    phase.weeklyRatePercent = newIntent.defaultWeeklyRatePercent
                }
            }

            Section("Длительность") {
                Stepper("Недель: \(phase.durationWeeks)", value: $phase.durationWeeks, in: 1...52)
            }

            if phase.intent != .maintenance {
                Section {
                    Stepper(value: $phase.weeklyRatePercent, in: 0.05...2.0, step: 0.05) {
                        HStack {
                            Text(String(format: "%.2f%%", phase.weeklyRatePercent))
                                .monospacedDigit()
                            Spacer()
                            Text(String(format: "%+.2f \(String(localized: "кг/нед"))", weeklyKg))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    if phase.isAggressive {
                        Label(phase.intent == .cut
                              ? "Быстрее процента веса в неделю — на сушке это уже за счёт мышц."
                              : "Быстрее половины процента в неделю — на наборе большая часть прибавки будет жиром.",
                              systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }
                } header: {
                    Text("Темп")
                } footer: {
                    Text("В процентах массы тела за неделю, а не в килограммах: одно и то же число подходит и лёгкому, и тяжёлому.")
                }
            }

            Section("Прогноз") {
                LabeledContent("Вес к концу фазы") {
                    Text(String(format: "%.1f \(String(localized: "кг"))", endWeightKg))
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
            }
        }
        .glassRow()
        .navigationTitle(phase.intent.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
