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
    /// Первая фаза переходить не от чего — у неё рампы нет.
    var isFirst: Bool = false

    private var weeklyKg: Double { phase.weeklyRateKg(fromWeightKg: startWeightKg) }

    private var endWeightKg: Double {
        startWeightKg + weeklyKg * Double(phase.durationWeeks)
    }

    var body: some View {
        if phase.isDietBreak {
            dietBreakForm
        } else {
            phaseForm
        }
    }

    /// Брейк — это не фаза с выбором цели и темпа: он всегда поддержание.
    /// Настраивать в нём можно только длину.
    private var dietBreakForm: some View {
        Form {
            Section {
                Stepper("Недель: \(phase.durationWeeks)", value: $phase.durationWeeks, in: 1...2)
            } footer: {
                Text("Неделя-две на поддержании посреди дефицита. Убрать брейк — смахни его в списке фаз.")
            }
        }
        .glassRow()
        .navigationTitle(phase.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var phaseForm: some View {
        Form {
            // Переключателя «дефицит / поддержание / набор» здесь нет: что это за
            // фаза, выбирают при добавлении, и заголовок экрана об этом говорит.
            // Сушку, превращённую в набор на месте, проще не заметить, чем
            // сделать нарочно — нужна другая фаза, её и добавляют.
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
                        .font(.app(.caption))
                        .foregroundStyle(.orange)
                    }
                } header: {
                    Text("Темп")
                } footer: {
                    Text("В процентах массы тела за неделю, а не в килограммах: одно и то же число подходит и лёгкому, и тяжёлому.")
                }
            }

            if phase.intent == .cut {
                Section {
                    Picker("Диет-брейки", selection: $phase.dietBreakEvery) {
                        Text("Вручную").tag(Int?.none)
                        ForEach(PlanPhase.dietBreakOptions, id: \.self) { every in
                            Text(String(format: String(localized: "%lld : 1"), every)).tag(Int?.some(every))
                        }
                    }
                    .accessibilityIdentifier("dietBreakSchedule")
                } header: {
                    Text("Диет-брейки")
                } footer: {
                    Text("«Вручную» — брейк берёшь сам, когда нужен, на экране плана. «4 : 1» — неделя поддержания после каждых четырёх недель дефицита, приложение ставит её само; взять внеплановый брейк можно и так. Срок фазы — недели дефицита, брейки добавляются к нему.")
                }
            }

            if !isFirst {
                Section {
                    Stepper(value: $phase.rampWeeks, in: 0...min(8, phase.durationWeeks)) {
                        if phase.rampWeeks == 0 {
                            Text("Сразу")
                        } else {
                            Text(String(format: String(localized: "Плавно, %lld нед."), phase.rampWeeks))
                        }
                    }
                } header: {
                    Text("Переход")
                } footer: {
                    Text("Выход из дефицита прыжком возвращает гликоген и воду: весы за три дня показывают плюс пару килограммов, к жиру не имеющих отношения. Пока норма поднимается плавно, приложение и не считает этот скачок отставанием.")
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
