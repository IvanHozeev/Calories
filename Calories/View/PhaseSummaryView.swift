import SwiftUI
import Charts

/// Итог пройденной фазы: что вышло, как это шло и что было задумано.
///
/// Только итог, без настроек: фаза прожита, менять в ней нечего. Главное —
/// крупно на тёмной карточке: на сколько изменился вес, и тут же график, где
/// пунктир — задуманное, а линия — как было на деле. Ниже — план против факта
/// полосами, питание за фазу и что на неё повлияло.
struct PhaseSummaryView: View {
    var store: CalorieStore
    let record: PhaseRecord
    @Environment(\.dismiss) private var dismiss

    private var tint: Color { PhaseLook.color(record.intent) }

    var body: some View {
        List {
            Section {
                heroCard
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }

            if let plannedWeeks = record.plannedWeeks, let plannedEnd = record.plannedEndWeightKg {
                planVersusFact(plannedWeeks: plannedWeeks, plannedEnd: plannedEnd)
            }

            if let intake = store.intakeSummary(from: record.startDate, to: record.endDate) {
                Section {
                    HStack(spacing: 8) {
                        tile("ккал в день", value: Int(intake.calories.rounded()).formatted(), unit: nil)
                        tile("белок в день", value: "\(Int(intake.protein.rounded()))",
                             unit: String(localized: "г"), color: MacroKind.protein.color)
                        tile("дней с записями", value: "\(intake.days)",
                             unit: "/ \(record.days)")
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                } header: {
                    Text("Питание")
                }
            }

            if !insights.isEmpty {
                Section {
                    ForEach(Array(insights.enumerated()), id: \.offset) { _, insight in
                        Label {
                            Text(verbatim: insight.text)
                                .font(.app(.subheadline))
                        } icon: {
                            Image(systemName: insight.good ? "checkmark.circle" : "exclamationmark.triangle")
                                .foregroundStyle(insight.good ? ProgressRing.kcalColors[0] : ProgressRing.overColors[0])
                        }
                    }
                }
            }

            if store.plan == nil {
                Section {
                    Button {
                        dismiss()
                    } label: {
                        Text("К новому плану")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.mainAction)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }
        }
        .glassRow()
        .listStyle(.insetGrouped)
        .navigationTitle("Итог фазы")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("phaseSummary")
    }

    // MARK: - Главное

    private var range: String {
        let start = record.startDate.formatted(.dateTime.day().month(.wide))
        let end = record.endDate.formatted(.dateTime.day().month(.wide))
        return "\(start) — \(end)"
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    ZStack {
                        Circle().fill(tint)
                        Image(systemName: record.intent.symbol)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(PhaseLook.ink(record.intent))
                    }
                    .frame(width: 26, height: 26)
                    Text(record.intent.title)
                        .font(.app(.headline))
                }
                Spacer()
                if record.endedEarly == true {
                    Text("раньше срока")
                        .font(.app(.caption, weight: .semibold))
                        .foregroundStyle(MacroKind.fat.color)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(MacroKind.fat.color.opacity(0.2), in: Capsule())
                }
            }

            if let change = record.changeKg, let start = record.startWeightKg, let end = record.endWeightKg {
                HStack(alignment: .lastTextBaseline) {
                    Text("\(Text(verbatim: String(format: "%+.1f", change)).font(.app(size: 52, weight: .bold)))\(Text(verbatim: " \(String(localized: "кг"))").font(.app(size: 22, weight: .semibold)).foregroundColor(.white.opacity(0.6)))")
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(verbatim: String(format: "%.1f → %.1f", start, end))
                            .font(.app(.body, weight: .semibold))
                        Text(verbatim: weeksAndRate)
                            .font(.app(.caption))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .padding(.bottom, 6)
                }
                .monospacedDigit()

                chart
                    .frame(height: 96)
                    .accessibilityLabel(Text(verbatim: String(format: "%.1f → %.1f", start, end)))

                HStack {
                    Text(verbatim: record.startDate.formatted(.dateTime.day().month(.wide)))
                    Spacer()
                    Text(verbatim: record.endDate.formatted(.dateTime.day().month(.wide)))
                }
                .font(.app(.caption2))
                .foregroundStyle(.white.opacity(0.6))
            } else {
                Text(verbatim: range)
                    .font(.app(.subheadline))
                    .foregroundStyle(.white.opacity(0.7))
                Text("За время фазы не было взвешиваний — подвести итог не по чему.")
                    .font(.app(.caption))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(Color(white: 0.11), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private var weeksAndRate: String {
        let weeks = String(format: String(localized: "%lld нед."), record.weeks)
        guard let weekly = record.weeklyChangeKg else { return weeks }
        return "\(weeks) · \(String(format: "%+.2f %@", weekly, String(localized: "кг/нед")))"
    }

    /// Вес по тренду раз в три дня от старта до финиша фазы.
    private var factPoints: [(date: Date, kg: Double)] {
        let calendar = Calendar.current
        var points: [(date: Date, kg: Double)] = []
        var day = record.startDate
        while day < record.endDate {
            if let kg = store.weightTrend(on: day) { points.append((day, kg)) }
            day = calendar.date(byAdding: .day, value: 3, to: day) ?? record.endDate
        }
        if let kg = record.endWeightKg { points.append((record.endDate, kg)) }
        return points
    }

    /// Задуманное: прямая от старта до задуманного финиша.
    private var planPoints: [(date: Date, kg: Double)] {
        guard let start = record.startWeightKg, let weeks = record.plannedWeeks,
              let end = record.plannedEndWeightKg,
              let finish = Calendar.current.date(byAdding: .day, value: weeks * 7, to: record.startDate)
        else { return [] }
        return [(record.startDate, start), (finish, end)]
    }

    private var chart: some View {
        let fact = factPoints
        let plan = planPoints
        let values = fact.map(\.kg) + plan.map(\.kg)
        let low = (values.min() ?? 0) - 0.3
        let high = (values.max() ?? 1) + 0.3
        let lastDate = max(plan.last?.date ?? record.endDate, record.endDate)
        return Chart {
            ForEach(plan, id: \.date) { point in
                LineMark(x: .value("Дата", point.date), y: .value("Вес", point.kg),
                         series: .value("Ряд", "plan"))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [4, 5]))
            }
            ForEach(fact, id: \.date) { point in
                LineMark(x: .value("Дата", point.date), y: .value("Вес", point.kg),
                         series: .value("Ряд", "fact"))
                    .foregroundStyle(tint)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
            }
            if let last = fact.last {
                PointMark(x: .value("Дата", last.date), y: .value("Вес", last.kg))
                    .symbol {
                        Circle()
                            .strokeBorder(tint, lineWidth: 3)
                            .background(Circle().fill(Color(white: 0.11)))
                            .frame(width: 11, height: 11)
                    }
            }
        }
        .chartXScale(domain: record.startDate...lastDate)
        .chartYScale(domain: low...high)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
    }

    // MARK: - План и факт

    private func planVersusFact(plannedWeeks: Int, plannedEnd: Double) -> some View {
        Section {
            bar(title: "Срок",
                value: String(format: String(localized: "%1$lld из %2$lld нед."), record.weeks, plannedWeeks),
                share: Double(record.weeks) / Double(max(1, plannedWeeks)),
                color: tint)
            if let start = record.startWeightKg, let change = record.changeKg {
                let planned = plannedEnd - start
                bar(title: "Вес",
                    value: String(format: String(localized: "%1$@ из %2$@ кг"),
                                  String(format: "%+.1f", change), String(format: "%+.1f", planned)),
                    share: abs(planned) > 0.05 ? change / planned : 1,
                    color: MacroKind.fat.color)
            }
        } header: {
            Text("План и факт")
        }
    }

    private func bar(title: LocalizedStringKey, value: String, share: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.app(.subheadline, weight: .semibold))
                Spacer()
                Text(verbatim: value)
                    .font(.app(.footnote))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.2))
                    Capsule().fill(color)
                        .frame(width: geometry.size.width * min(max(share, 0), 1))
                }
            }
            .frame(height: 8)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Питание

    private func tile(_ title: LocalizedStringKey, value: String, unit: String?, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.app(.caption2))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(verbatim: value)
                    .font(.app(.title3, weight: .bold))
                    .foregroundStyle(color)
                if let unit {
                    Text(verbatim: unit)
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                }
            }
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .tileSurface(cornerRadius: 18)
    }

    // MARK: - Что повлияло

    private var insights: [(text: String, good: Bool)] {
        var result: [(String, Bool)] = []
        if let strength = store.strengthChange(from: record.startDate, to: record.endDate) {
            let good = strength.outcome != .loss
            result.append((String(format: String(localized: "%1$@: %2$@ за фазу"),
                                  strength.outcome.title, String(format: "%+.0f%%", strength.percent)), good))
        }
        if let gap = store.averageGoalGap(from: record.startDate, to: record.endDate), abs(gap) >= 50 {
            let text = gap > 0
                ? String(format: String(localized: "В среднем на %lld ккал в день выше нормы"), gap)
                : String(format: String(localized: "В среднем на %lld ккал в день ниже нормы"), -gap)
            // Сверх нормы на сушке — против цели, на наборе — не беда.
            let good = record.intent == .bulk ? gap > 0 : gap < 0
            result.append((text, good))
        }
        return result
    }
}

private extension PhaseRecord {
    /// Сколько календарных дней длилась фаза.
    var days: Int {
        max(1, Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 1)
    }
}
