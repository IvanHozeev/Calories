import SwiftUI

/// План одной строкой под кольцом.
///
/// На месте большой карточки, которая занимала полэкрана и повторяла то, что
/// и так есть на экране плана. Но убрать её совсем было нельзя по двум причинам,
/// и обе про то, чего не видно.
///
/// Первая: вход в план — платная функция, и если единственной дверью в неё
/// станет нажатие на кольцо, о котором ничто не сообщает, её просто не найдут.
/// Строка эту дверь показывает.
///
/// Вторая: у плана теперь цепочка фаз, и «фаза сменилась» или «план кончился» —
/// это то, что замечают краем глаза на главном экране, а не открывая план
/// специально. Строка и есть тот самый край глаза.
struct PlanStrip: View {
    var store: CalorieStore
    var onOpenPlan: () -> Void
    var onShowPaywall: () -> Void

    var body: some View {
        Button(action: store.isPremium ? onOpenPlan : onShowPaywall) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.app(.caption))
                    .foregroundStyle(tint)
                content
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.app(.caption2, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .font(.app(.caption))
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            // Форма касания до стекла: без неё нажатие ловилось только по
            // тексту, а стекло между буквами его не пропускало.
            .contentShape(Capsule())
            .liquidGlass(in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("planStrip")
    }

    private var icon: String {
        if !store.isPremium { return "lock.fill" }
        if store.planOutcome != nil { return "flag.checkered" }
        return "target"
    }

    private var tint: Color {
        guard store.isPremium else { return .secondary }
        if store.planOutcome != nil { return .secondary }
        return store.plan == nil ? .secondary : (store.planAdherence()?.status.color ?? .yellow)
    }

    @ViewBuilder
    private var content: some View {
        if !store.isPremium {
            Text("Персональный план")
                .foregroundStyle(.secondary)
        } else if store.planOutcome != nil {
            Text("План завершён — посмотри итог")
                .foregroundStyle(.secondary)
        } else if let plan = store.plan {
            // Неделя, фаза и темп: ровно то, за чем на карточку и смотрели.
            // Фаза только когда их несколько — иначе она повторяет название плана.
            Text(String(format: String(localized: "Неделя %d из %d"),
                        plan.currentWeek, plan.durationWeeks))
            if plan.timeline.count > 1, let phase = plan.currentPhase {
                Text(verbatim: "·").foregroundStyle(.tertiary)
                Text(phase.title)
            }
            Text(verbatim: "·").foregroundStyle(.tertiary)
            Text(String(format: "%+.2f \(String(localized: "кг/нед"))", plan.weeklyRateKg))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        } else {
            // Без плана у премиума идёт поддержание, и строка не зовёт
            // «спланировать» вообще, а говорит, что сейчас имеет смысл.
            Text(verbatim: store.isPremium
                 ? store.phaseAdvice(bodyFatPercent: store.measuredBodyFatPercent).headline
                 : String(localized: "Спланировать сушку или набор"))
                .foregroundStyle(.secondary)
        }
    }
}

