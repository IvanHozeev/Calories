import SwiftUI

/// Цвета фаз — одни на редакторе плана, на экране фазы и в итоге.
///
/// Сушка — цветом калорий (той же мятой, что у кольца в норме), набор — цветом
/// углеводов, поддержание — нейтральным серым: оно держит вес, а не двигает
/// его. Брейк — цветом жиров, как на макете: короткая передышка внутри сушки.
enum PhaseLook {
    static func color(_ intent: PlanIntent) -> Color {
        switch intent {
        case .cut: return ProgressRing.kcalColors[0]
        case .maintenance: return Color(.systemGray3)
        case .bulk: return MacroKind.carbs.color
        }
    }

    /// Цвет значка на кружке фазы: на сером — тёмный, на цветном — белый.
    static func ink(_ intent: PlanIntent) -> Color {
        intent == .maintenance ? Color.primary.opacity(0.75) : .white
    }

    static func color(_ phase: PlanPhase) -> Color {
        phase.isDietBreak ? MacroKind.fat.color : color(phase.intent)
    }
}

/// Маршрут плана одной карточкой: финиш, сколько недель, вес от и до, линия
/// прогноза веса и лента фаз по их длине.
///
/// Это то, ради чего правят план, — куда он приведёт и когда. Раньше это
/// лежало строками «Расчёта» в самом низу экрана.
struct PlanRouteCard: View {
    let plan: Plan?
    let tdee: Double
    /// Откуда взят вес на старте — одной строкой под карточкой.
    let weightSource: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let plan {
                header(plan)
                WeightLine(plan: plan)
                    .frame(height: 56)
                    .accessibilityHidden(true)
                ribbon(plan)
                footer(plan)
            } else {
                Text("Добавь фазы — здесь появится маршрут: финиш, вес и недели.")
                    .font(.app(.subheadline))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tileSurface(cornerRadius: 24)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("planRoute")
    }

    private func header(_ plan: Plan) -> some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Финиш")
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
                Text(verbatim: PlanView.planDate(plan.endDate))
                    .font(.app(size: 28, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: String(localized: "%lld нед."), plan.durationWeeks))
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
                Text(verbatim: String(format: "%.1f → %.1f %@", plan.startWeightKg, plan.targetWeightKg,
                                      String(localized: "кг")))
                    .font(.app(.body, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .monospacedDigit()
    }

    /// Лента фаз: каждая — блоком своей длины, брейки внутри сушки — своими.
    private func ribbon(_ plan: Plan) -> some View {
        let segments = plan.timeline
        let total = max(1, segments.reduce(0) { $0 + $1.durationWeeks })
        return GeometryReader { geometry in
            let gap: CGFloat = 3
            let free = geometry.size.width - gap * CGFloat(max(0, segments.count - 1))
            HStack(spacing: gap) {
                ForEach(segments) { segment in
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(PhaseLook.color(segment))
                        .frame(width: max(4, free * CGFloat(segment.durationWeeks) / CGFloat(total)))
                        .overlay {
                            // Число недель — только там, где оно влезает.
                            if free * CGFloat(segment.durationWeeks) / CGFloat(total) > 22 {
                                Text(verbatim: "\(segment.durationWeeks)")
                                    .font(.app(.caption2, weight: .bold))
                                    .foregroundStyle(segment.isDietBreak ? .white : PhaseLook.ink(segment.intent))
                                    .monospacedDigit()
                            }
                        }
                }
            }
        }
        .frame(height: 28)
    }

    private func footer(_ plan: Plan) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(plan.cyclingEnabled ? "Норма в среднем" : "Норма на старте")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(verbatim: "\(plan.dailyCalorieTarget(tdee: tdee)) \(String(localized: "ккал"))")
                    .font(.app(.subheadline, weight: .semibold))
                    .foregroundStyle(ProgressRing.kcalColors[0])
                    .monospacedDigit()
            }
            .font(.app(.subheadline))
            if plan.hasAggressivePhase {
                Label("Темп фазы выше разумного: на сушке это 1% массы в неделю, на наборе 0.5%. Такая фаза отмечена оранжевым.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.app(.caption))
                    .foregroundStyle(.orange)
            }
            Text(verbatim: weightSource)
                .font(.app(.caption))
                .foregroundStyle(.tertiary)
        }
    }
}

/// Прогноз веса линией: по точке на каждой границе фаз.
private struct WeightLine: View {
    let plan: Plan

    private var points: [(week: Double, kg: Double)] {
        var result: [(Double, Double)] = [(0, plan.startWeightKg)]
        var week = 0.0
        for (index, segment) in plan.timeline.enumerated() {
            week += Double(segment.durationWeeks)
            result.append((week, plan.weight(atStartOfPhaseAt: index + 1)))
        }
        return result.map { (week: $0.0, kg: $0.1) }
    }

    var body: some View {
        GeometryReader { geometry in
            let pts = points
            let total = max(1, pts.last?.week ?? 1)
            let low = (pts.map(\.kg).min() ?? 0) - 0.4
            let high = (pts.map(\.kg).max() ?? 0) + 0.4
            let span = max(0.1, high - low)
            let inset: CGFloat = 6
            let width = geometry.size.width - inset * 2
            let height = geometry.size.height - inset * 2
            let xy = pts.map { point in
                CGPoint(x: inset + width * point.week / total,
                        y: inset + height * (high - point.kg) / span)
            }
            ZStack {
                Path { path in
                    guard let first = xy.first else { return }
                    path.move(to: first)
                    for point in xy.dropFirst() { path.addLine(to: point) }
                }
                .stroke(Color.primary.opacity(0.85),
                        style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                if let last = xy.last {
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.85), lineWidth: 2.4)
                        .background(Circle().fill(Color(.systemBackground)))
                        .frame(width: 10, height: 10)
                        .position(last)
                }
            }
        }
    }
}

/// Неделя цикла столбиками: рефид-дни выше и цветом жиров.
struct WeekCycleBars: View {
    let days: [(label: String, calories: Int)]

    var body: some View {
        let low = days.map(\.calories).min() ?? 0
        let high = days.map(\.calories).max() ?? 1
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                let refeed = day.calories > low
                VStack(spacing: 4) {
                    Text(verbatim: "\(day.calories)")
                        .font(.app(size: 9, weight: refeed ? .bold : .regular))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(refeed ? MacroKind.fat.color : ProgressRing.kcalColors[0].opacity(0.55))
                        .frame(height: high > low && refeed ? 52 : 34)
                    Text(verbatim: day.label)
                        .font(.app(.caption2, weight: refeed ? .bold : .regular))
                        .foregroundStyle(refeed ? Color.primary : Color.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: days.map { "\($0.label) \($0.calories)" }.joined(separator: ", ")))
    }
}
