import SwiftUI

/// Итог пройденной фазы: что задумано, что вышло и как это получилось.
///
/// Только сводка, без настроек. Фаза уже прожита: менять в ней темп, срок и
/// брейки нечего, а прежде тут открывался тот же экран, что и у идущей, — с
/// теми же степперами и прогнозом на будущее.
struct PhaseSummaryView: View {
    var store: CalorieStore
    let record: PhaseRecord

    private var range: String {
        let start = record.startDate.formatted(.dateTime.day().month(.abbreviated).year())
        let end = record.endDate.formatted(.dateTime.day().month(.abbreviated).year())
        return "\(start) — \(end)"
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(record.intent.title)
                            .font(.app(.title2, weight: .bold))
                        Spacer()
                        Text(String(format: String(localized: "%lld нед."), record.weeks))
                            .font(.app(.title3, weight: .semibold))
                            .monospacedDigit()
                    }
                    Text(verbatim: range)
                        .font(.app(.subheadline))
                        .foregroundStyle(.secondary)
                    if record.endedEarly == true {
                        Label("Завершена раньше срока", systemImage: "flag.checkered")
                            .font(.app(.caption, weight: .semibold))
                            .foregroundStyle(.orange)
                            .padding(.top, 2)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Вес") {
                if let start = record.startWeightKg, let end = record.endWeightKg {
                    row("Старт", String(format: "%.1f %@", start, String(localized: "кг")))
                    row("Финиш", String(format: "%.1f %@", end, String(localized: "кг")))
                    if let change = record.changeKg {
                        row("Изменение", String(format: "%+.1f %@", change, String(localized: "кг")),
                            emphasized: true)
                    }
                    if let weekly = record.weeklyChangeKg {
                        row("В неделю", String(format: "%+.2f %@", weekly, String(localized: "кг/нед")))
                    }
                } else {
                    Text("За время фазы не было взвешиваний — подвести итог не по чему.")
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                }
            }

            // Задуманное рядом с прожитым — только там, где оно записано.
            if let plannedWeeks = record.plannedWeeks, let plannedWeight = record.plannedEndWeightKg {
                Section("Было в плане") {
                    row("Срок", String(format: String(localized: "%lld нед."), plannedWeeks))
                    row("Вес к концу", String(format: "%.1f %@", plannedWeight, String(localized: "кг")))
                    if let end = record.endWeightKg {
                        let gap = end - plannedWeight
                        row("От плана", String(format: "%+.1f %@", gap, String(localized: "кг")))
                    }
                }
            }

            if let intake = store.intakeSummary(from: record.startDate, to: record.endDate) {
                Section("Питание") {
                    row("Калорий в день", String(format: "%.0f %@", intake.calories, String(localized: "ккал")))
                    row("Белка в день", String(format: "%.0f %@", intake.protein, String(localized: "г")))
                    row("Дней с записями", String(format: "%lld", intake.days))
                }
            }
        }
        .glassRow()
        .listStyle(.insetGrouped)
        .navigationTitle(record.intent.title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("phaseSummary")
    }

    private func row(_ title: LocalizedStringKey, _ value: String, emphasized: Bool = false) -> some View {
        LabeledContent {
            Text(verbatim: value)
                .font(.app(.body, weight: emphasized ? .semibold : .regular))
                .monospacedDigit()
        } label: {
            Text(title)
        }
    }
}
