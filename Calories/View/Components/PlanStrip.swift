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

    /// Та же строка плиткой: крупно — фаза, средне — темп, подписью — неделя.
    var tile: TodayTile {
        TodayTile(icon: icon,
                  tint: tint,
                  label: String(localized: "План"),
                  value: tileValue,
                  value2: tileValue2,
                  caption: tileCaption,
                  identifier: "planStrip",
                  onTap: store.isPremium ? onOpenPlan : onShowPaywall)
    }

    private var tileValue: String {
        if !store.isPremium { return String(localized: "Персональный план") }
        if store.planOutcome != nil { return String(localized: "План завершён") }
        guard let plan = store.plan else {
            return store.phaseAdvice(bodyFatPercent: store.measuredBodyFatPercent).headline
        }
        guard plan.timeline.count > 1, let phase = plan.currentPhase else {
            return String(format: "%+.2f", plan.weeklyRateKg(on: Date())) + " \(String(localized: "кг/нед"))"
        }
        return phase.title
    }

    private var tileValue2: String? {
        guard let plan = store.plan else { return nil }
        guard plan.timeline.count > 1 else { return nil }
        let rate = plan.weeklyRateKg(on: Date())
        return String(format: "%+.2f", rate) + " \(String(localized: "кг/нед"))"
    }

    private var tileCaption: String? {
        guard store.isPremium else { return String(localized: "Открыть") }
        if store.planOutcome != nil { return String(localized: "посмотри итог") }
        guard let plan = store.plan else { return nil }
        return String(format: String(localized: "Неделя %d из %d"),
                      plan.currentWeek, plan.durationWeeks)
    }

    private var icon: String {
        if !store.isPremium { return "lock.fill" }
        if store.planOutcome != nil { return "flag.checkered" }
        guard let plan = store.plan else { return "target" }
        // Во время брейка вес о плане не говорит — бокалы, а не треугольник.
        if plan.isDietBreak(on: Date()) { return "cup.and.saucer.fill" }
        return store.planAdherence()?.status.icon ?? "target"
    }

    private var tint: Color {
        guard store.isPremium else { return .secondary }
        if store.planOutcome != nil { return .secondary }
        guard let plan = store.plan else { return .secondary }
        // Во время брейка вес о плане не говорит — зелёный, а не цвет статуса.
        if plan.isDietBreak(on: Date()) { return .green }
        return planAdherenceColor
    }

    private var planAdherenceColor: Color {
        store.planAdherence()?.status.color ?? .yellow
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
            // Фаза, темп и неделя: ровно то, за чем на карточку и смотрели.
            // Фаза только когда их несколько — иначе она повторяет название плана.
            if plan.timeline.count > 1, let phase = plan.currentPhase {
                Text(phase.title)
                    .font(.app(.caption, weight: .semibold))
            }
            Text(verbatim: "·").foregroundStyle(.tertiary)
            // Фактический темп веса по тренду, а не плановый темп фазы.
            // Во время брейка плановый темп 0 (поддержание), а фактический
            // может расти из-за воды и гликогена — показываем то, что реально
            // происходит с весом, чтобы строка и плитка не врали по-разному.
            let rate = store.planAdherence()?.observedWeeklyRateKg ?? plan.weeklyRateKg
            Text(verbatim: "·").foregroundStyle(.tertiary)
            Text(String(format: "%+.2f \(String(localized: "кг/нед"))", rate))
                .font(.app(.caption2))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Text(verbatim: "·").foregroundStyle(.tertiary)
            Text(String(format: String(localized: "Неделя %d из %d"),
                        plan.currentWeek, plan.durationWeeks))
                .font(.app(.caption2))
                .foregroundStyle(.secondary)
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

