import SwiftUI

/// Цепочка фаз одной полосой: где мы сейчас и что дальше.
///
/// Полоса, а не список, потому что вопрос к ней один и пространственный —
/// «сколько ещё до конца дефицита». Списком на него отвечать приходится
/// сложением недель в уме.
struct PlanTimeline: View {
    let plan: Plan
    /// Сегодняшний день, параметром ради тестируемости и превью.
    var today: Date = Date()

    private var currentIndex: Int? { plan.phaseIndex(on: today) }

    /// Доля пройденного внутри цепочки — по времени, а не по весу.
    /// Здесь это честно: полоса показывает расписание, а не результат.
    private var elapsedShare: Double {
        let total = plan.endDate.timeIntervalSince(plan.startDate)
        guard total > 0 else { return 0 }
        return min(max(today.timeIntervalSince(plan.startDate) / total, 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    HStack(spacing: 2) {
                        ForEach(Array(plan.phases.enumerated()), id: \.element.id) { index, phase in
                            Capsule()
                                .fill(color(for: phase.intent)
                                    .opacity(index == currentIndex ? 1 : 0.35))
                                .frame(width: width(of: phase, in: geometry.size.width))
                        }
                    }
                    // Отметка «сегодня»: без неё полоса показывает расписание,
                    // но не отвечает, где на нём человек.
                    if currentIndex != nil {
                        Capsule()
                            .fill(Color.primary)
                            .frame(width: 2)
                            .offset(x: geometry.size.width * elapsedShare - 1)
                    }
                }
            }
            .frame(height: 10)

            HStack(spacing: 10) {
                ForEach(Array(plan.phases.enumerated()), id: \.element.id) { index, phase in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(color(for: phase.intent))
                            .frame(width: 6, height: 6)
                        Text(phase.intent.title)
                            .lineLimit(1)
                        // Недели — только у идущей фазы. У всех трёх подписи
                        // не помещаются в строку и переносятся, а «сколько
                        // осталось этой» — единственный вопрос, который здесь
                        // задают; длительность остальных видна по ширине.
                        if index == currentIndex {
                            Text(String(format: String(localized: "%lld нед."), phase.durationWeeks))
                                .foregroundStyle(.tertiary)
                                .monospacedDigit()
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(index == currentIndex ? .primary : .secondary)
                }
                Spacer(minLength: 0)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
    }

    private func width(of phase: PlanPhase, in total: CGFloat) -> CGFloat {
        let weeks = plan.durationWeeks
        guard weeks > 0 else { return 0 }
        // Минимум в четыре пункта: недельная фаза внутри полугодового плана
        // иначе схлопывается в ничто и выглядит как ошибка отрисовки.
        return max(4, total * CGFloat(phase.durationWeeks) / CGFloat(weeks))
    }

    private func color(for intent: PlanIntent) -> Color {
        switch intent {
        case .cut:         return .blue
        case .maintenance: return .gray
        case .bulk:        return .green
        }
    }
}
