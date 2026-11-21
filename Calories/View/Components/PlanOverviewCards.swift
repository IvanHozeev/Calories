import SwiftUI
import Charts

/// Карточка идущей фазы: где я на дистанции и идёт ли план.
///
/// Раньше шапку плана занимали «ккал сегодня» и полоска веса, а статус и
/// темп жили секцией ниже. Норма дня видна на «Сегодня», а сюда приходят
/// узнать другое: какая фаза, сколько её осталось, что дальше и как идёт. Всё
/// это теперь на одной карточке, статус — последней строкой.
struct PlanPhaseCard: View {
    let plan: Plan
    let adherence: PlanAdherence?
    var today: Date = Date()

    private var index: Int? { plan.phaseIndex(on: today) }
    private var phase: PlanPhase? { index.map { plan.timeline[$0] } }

    /// Неделя внутри идущей фазы — то, что меняется каждую неделю.
    private var weekInPhase: Int? {
        guard let index else { return nil }
        let days = Calendar.current.dateComponents([.day], from: plan.startDate(ofPhaseAt: index), to: today).day ?? 0
        return min(days / 7 + 1, plan.timeline[index].durationWeeks)
    }

    /// Доля пройденного в идущей фазе — для заливки её отрезка.
    private var phaseProgress: Double {
        guard let index else { return 0 }
        let start = plan.startDate(ofPhaseAt: index)
        let length = Double(plan.timeline[index].durationWeeks * 7 * 86_400)
        guard length > 0 else { return 0 }
        return min(max(today.timeIntervalSince(start) / length, 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: phase?.title ?? plan.title)
                    .font(.app(.title2, weight: .bold))
                Spacer(minLength: 8)
                if let phase, let week = weekInPhase {
                    Text(String(format: String(localized: "неделя %lld из %lld"), week, phase.durationWeeks))
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            phaseBar
                .accessibilityHidden(true)

            Text(verbatim: nextLine)
                .font(.app(.caption))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Статус — только когда есть чем его назвать: без профиля или
            // взвешиваний вердикта нет, и черта над пустым местом висела бы
            // зря.
            if plan.isDietBreak(on: today) || adherence != nil {
                Divider()
                statusRow
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tileSurface(cornerRadius: 20)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("planPhaseCard")
    }

    /// Фазы отрезками по длине: пройденные залиты, идущая — на свою долю.
    private var phaseBar: some View {
        GeometryReader { geometry in
            let phases = plan.timeline
            let gaps = CGFloat(max(phases.count - 1, 0)) * 3
            let total = CGFloat(max(plan.durationWeeks, 1))
            HStack(spacing: 3) {
                ForEach(Array(phases.enumerated()), id: \.element.id) { offset, item in
                    let width = max(6, (geometry.size.width - gaps) * CGFloat(item.durationWeeks) / total)
                    let fill: Double = index.map { offset < $0 ? 1 : (offset == $0 ? phaseProgress : 0) } ?? 1
                    let color = Self.color(for: item)
                    ZStack(alignment: .leading) {
                        Capsule().fill(color.opacity(item.isDietBreak || item.intent == .maintenance ? 0.24 : 0.2))
                        Capsule().fill(color).frame(width: width * fill)
                    }
                    .frame(width: width, height: 8)
                }
            }
        }
        .frame(height: 8)
    }

    /// Цвет отрезка: дефицит — зелёным, как кольцо, набор — цветом белка,
    /// поддержание и брейк — серым: там вес никуда не ведут.
    static func color(for phase: PlanPhase) -> Color {
        if phase.isDietBreak { return Color(.systemGray) }
        switch phase.intent {
        case .cut: return ProgressRing.kcalColors[0]
        case .bulk: return MacroKind.protein.color
        case .maintenance: return Color(.systemGray)
        }
    }

    /// Что после идущей фазы — или когда финиш, если она последняя.
    private var nextLine: String {
        let rest = index.map { Array(plan.timeline.dropFirst($0 + 1)) } ?? []
        guard !rest.isEmpty else {
            return String(format: String(localized: "Финиш %@"), PlanView.planDate(plan.endDate))
        }
        let parts = rest.map { phase in
            String(format: String(localized: "%1$@ %2$lld нед."),
                   phase.title.localizedLowercase, phase.durationWeeks)
        }
        return String(format: String(localized: "Дальше: %@"), parts.joined(separator: " · "))
    }

    @ViewBuilder
    private var statusRow: some View {
        if plan.isDietBreak(on: today) {
            // Во время брейка вес о плане не говорит: вода и гликоген.
            row(icon: "cup.and.saucer.fill", tint: Palette.good,
                title: String(localized: "Идёт брейк"),
                caption: String(format: String(localized: "Дефицит вернётся %@"),
                                plan.firstNonBreakDay(from: today)
                                    .formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))))
        } else if let adherence {
            row(icon: adherence.status.icon, tint: adherence.status.color,
                title: adherence.status.title, caption: rateCaption(adherence))
        }
    }

    /// Темп по тренду против плана — ровно то, на что смотрят под вердиктом.
    private func rateCaption(_ adherence: PlanAdherence) -> String? {
        let planned = plan.weeklyRateKg(on: today)
        // Темпа ещё нет — тренд не набрал недель. Тогда говорим, насколько
        // вес в стороне от плана: это известно с первого взвешивания.
        guard let observed = adherence.observedWeeklyRateKg else {
            guard let deviation = adherence.deviationKg else { return nil }
            guard abs(deviation) >= 0.05 else { return String(localized: "ровно по плану") }
            return String(format: deviation < 0
                          ? String(localized: "на %@ кг впереди плана")
                          : String(localized: "на %@ кг позади плана"),
                          String(format: "%.1f", abs(deviation)))
        }
        return String(format: String(localized: "%1$@ кг в неделю при плане %2$@"),
                      String(format: "%+.2f", observed), String(format: "%+.2f", planned))
    }

    private func row(icon: String, tint: Color, title: String, caption: String?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.app(.title3))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: title)
                    .font(.app(.subheadline, weight: .semibold))
                if let caption {
                    Text(verbatim: caption)
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// Карточка веса: линия плана и тренд поверх неё.
///
/// Без осей и сетки: вопрос здесь не «сколько было пятого числа», а «иду ли
/// я вдоль плана». Пунктир — план от старта до цели, серые точки —
/// взвешивания, зелёная линия — тренд до сегодня.
struct PlanWeightCard: View {
    let plan: Plan
    let entries: [WeightEntry]
    /// Тренд веса на дату — из стора, тем же сглаживанием, что везде.
    let trend: (Date) -> Double?
    var today: Date = Date()

    private var weighIns: [WeightEntry] {
        entries.filter { $0.date >= plan.startDate && $0.date <= today }
    }

    private var planned: [(date: Date, kg: Double)] {
        var points: [(Date, Double)] = [(plan.startDate, plan.startWeightKg)]
        for index in plan.timeline.indices {
            points.append((plan.startDate(ofPhaseAt: index + 1), plan.weight(atStartOfPhaseAt: index + 1)))
        }
        return points.map { (date: $0.0, kg: $0.1) }
    }

    /// Тренд раз в три дня от старта до сегодня.
    private var trendPoints: [(date: Date, kg: Double)] {
        let calendar = Calendar.current
        var points: [(date: Date, kg: Double)] = []
        var day = plan.startDate
        while day < today {
            if let kg = trend(day) { points.append((day, kg)) }
            day = calendar.date(byAdding: .day, value: 3, to: day) ?? today
        }
        if let kg = trend(today) { points.append((today, kg)) }
        return points
    }

    private var current: Double? { trend(today) }

    /// Какая доля срока плана уже прошла.
    private var todayShare: CGFloat {
        let total = plan.endDate.timeIntervalSince(plan.startDate)
        guard total > 0 else { return 0 }
        return CGFloat(min(max(today.timeIntervalSince(plan.startDate) / total, 0), 1))
    }

    /// «Сегодня» молчит, когда отметка так близко к краю, что слово налезло бы
    /// на «старт» или «цель»: тогда эти две подписи сами говорят, где человек.
    private func todayLabelFits(x: CGFloat, total: CGFloat) -> Bool {
        x > 90 && x < total - 90
    }

    private var bounds: ClosedRange<Double> {
        let values = weighIns.map(\.weightKg) + planned.map(\.kg) + trendPoints.map(\.kg)
        let low = (values.min() ?? plan.startWeightKg) - 0.5
        let high = (values.max() ?? plan.startWeightKg) + 0.5
        return low...high
    }

    private static let lineColor = ProgressRing.kcalColors[0]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Вес")
                    .font(.app(.subheadline, weight: .semibold))
                Spacer()
                Text(verbatim: header)
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            chart
                .frame(height: 110)
                .accessibilityHidden(true)

            // «Сегодня» — под отметкой, а не посередине: середина подписи
            // совпадала с серединой карточки, и при отметке на трети пути
            // слово стояло под пустым местом. Положение — доля пройденного
            // срока, та же, что у линии на графике.
            GeometryReader { geometry in
                let x = geometry.size.width * todayShare
                ZStack(alignment: .topLeading) {
                    Text(String(format: String(localized: "старт %@"), String(format: "%.1f", plan.startWeightKg)))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(String(format: String(localized: "цель %@"), String(format: "%.1f", plan.targetWeightKg)))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Text("сегодня")
                        .fixedSize()
                        .position(x: x, y: 7)
                        .opacity(todayLabelFits(x: x, total: geometry.size.width) ? 1 : 0)
                }
            }
            .frame(height: 16)
            .font(.app(.caption2))
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tileSurface(cornerRadius: 20)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("planWeightCard")
    }

    private var header: String {
        let start = String(format: "%.1f", plan.startWeightKg)
        guard let current else { return "\(start) \(String(localized: "кг"))" }
        return "\(start) → \(String(format: "%.1f", current)) \(String(localized: "кг"))"
    }

    private var chart: some View {
        Chart {
            ForEach(planned, id: \.date) { point in
                LineMark(x: .value("Дата", point.date), y: .value("Вес", point.kg),
                         series: .value("Ряд", "plan"))
                    .foregroundStyle(Color.secondary.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [4, 5]))
            }
            RuleMark(x: .value("Дата", today))
                .foregroundStyle(Color.primary.opacity(0.12))
                .lineStyle(StrokeStyle(lineWidth: 1))
            ForEach(weighIns) { entry in
                PointMark(x: .value("Дата", entry.date), y: .value("Вес", entry.weightKg))
                    .foregroundStyle(Color.secondary.opacity(0.5))
                    .symbolSize(14)
            }
            ForEach(trendPoints, id: \.date) { point in
                LineMark(x: .value("Дата", point.date), y: .value("Вес", point.kg),
                         series: .value("Ряд", "trend"))
                    .foregroundStyle(Self.lineColor)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
            }
            if let current {
                PointMark(x: .value("Дата", today), y: .value("Вес", current))
                    .symbol {
                        Circle()
                            .strokeBorder(Self.lineColor, lineWidth: 3)
                            .background(Circle().fill(Color(.systemBackground)))
                            .frame(width: 11, height: 11)
                    }
            }
        }
        .chartXScale(domain: plan.startDate...plan.endDate)
        .chartYScale(domain: bounds)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
    }
}
