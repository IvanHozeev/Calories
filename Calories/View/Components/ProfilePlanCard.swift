import SwiftUI

/// Карточка плана в шапке профиля — единственная точка входа в «План».
/// Не путать с `PlanCard` в ContentView: та — сводка на главном экране, эта — вход и промо.
///
/// Раньше вход был иконкой-искоркой в тулбаре: она ничего не объясняла, а для новичка
/// без профиля вообще была выключена — то есть платную фичу не видел ровно тот, кому её
/// продают. Карточка показывает ценность до покупки и заодно занимает место секции «Цель»,
/// которая при активном плане скрывается (норму задаёт план, а не goal.calorieMultiplier).
struct ProfilePlanCard: View {
    var store: CalorieStore
    var onOpenPlan: () -> Void
    var onShowPaywall: () -> Void

    var body: some View {
        if !store.isPremium {
            Button(action: onShowPaywall) { promo }
                .buttonStyle(.plain)
        } else if let plan = store.plan {
            Button(action: onOpenPlan) { activePlan(plan) }
                .buttonStyle(.plain)
        } else if store.profile == nil {
            needsProfile
        } else {
            Button(action: onOpenPlan) { emptyState }
                .buttonStyle(.plain)
        }
    }

    // MARK: Состояния

    private var promo: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "target")
                    .foregroundStyle(.yellow)
                Text("Персональный план")
                    .font(.headline)
                proBadge
                Spacer()
                chevron
            }
            Text("Спланируй сушку или набор: приложение само посчитает дневную норму калорий под целевой вес и срок.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .glassCard()
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "target")
                    .foregroundStyle(.yellow)
                Text("Персональный план")
                    .font(.headline)
                Spacer()
                chevron
            }
            Text("Поставь целевой вес и срок — дневная норма пересчитается под них.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .glassCard()
    }

    private var needsProfile: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "target")
                    .foregroundStyle(.secondary)
                Text("Персональный план")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Text("Заполни параметры тела ниже — план считается по твоим BMR и TDEE.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .glassCard()
    }

    private func activePlan(_ plan: Plan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "target")
                    .foregroundStyle(.yellow)
                Text(plan.title)
                    .font(.headline)
                Spacer()
                chevron
            }

            // Где мы на дистанции. Без этого карточка показывала цель и темп,
            // но не отвечала на первый же вопрос: сколько ещё это терпеть.
            HStack(spacing: 6) {
                Text(String(format: String(localized: "Неделя %d из %d"),
                            plan.currentWeek, plan.durationWeeks))
                    .font(.caption.weight(.medium))
                if plan.weeksRemaining > 0 {
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(String(format: String(localized: "осталось %d нед."), plan.weeksRemaining))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text("последняя неделя")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 6) {
                Text(String(format: "%.1f \(String(localized: "кг"))", plan.targetWeightKg))
                    .font(.subheadline.weight(.semibold))
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(String(format: "%+.2f \(String(localized: "кг/нед"))", plan.weeklyRateKg))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: plan.progress)
                .tint(store.planAdherence()?.status.color ?? .accentColor)

            HStack {
                if let status = store.planAdherence()?.status {
                    Label(status.title, systemImage: status.icon)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(status.color)
                }
                Spacer()
                Text("Финиш \(plan.endDate.formatted(.dateTime.day().month(.abbreviated)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .glassCard()
    }

    // MARK: Мелочи

    private var proBadge: some View {
        Text(verbatim: "PRO")
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                LinearGradient(
                    colors: [.orange, .yellow],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: Capsule()
            )
            .foregroundStyle(.black)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tertiary)
    }
}
