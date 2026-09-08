import SwiftUI

/// План: как он идёт и чем закончился.
///
/// Настройка живёт отдельно, в `PlanEditorView`. Разделены они потому, что это
/// работы разной частоты: план настраивают один раз, а смотрят на него каждую
/// неделю — и раньше единственное, ради чего сюда заходят, было зажато между
/// полем целевого веса и степпером недель.
struct PlanView: View {
    var store: CalorieStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingCancel = false

    private var tdee: Double {
        store.profile?.tdee ?? Double(store.dailyGoal)
    }

    // Своего NavigationStack тут нет намеренно: экран не показывается листом,
    // а пушится с «Сегодня». Обёртка давала второй навбар — стрелку назад снаружи
    // и «Готово» внутри, два способа уйти с одного экрана.
    @ViewBuilder
    var body: some View {
        // Плана нет — показывать нечего, сразу настройка.
        if store.plan == nil {
            PlanEditorView(store: store)
        } else {
            dashboard
        }
    }

    @ViewBuilder
    private var dashboard: some View {
        List {
            if let plan = store.plan {
                Section {
                    hero(plan)
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            if let outcome = store.planOutcome {
                outcomeSection(outcome)
            } else if let plan = store.plan, let adherence = store.planAdherence() {
                adherenceSection(plan: plan, adherence: adherence)
            }

            if let composition = store.planCompositionChange {
                compositionSection(composition)
            }

            Section {
                NavigationLink {
                    PlanEditorView(store: store)
                } label: {
                    Label("Изменить план", systemImage: "slider.horizontal.3")
                }
                .accessibilityIdentifier("editPlan")
            }

            if store.planOutcome == nil {
                Section {
                    Button("Завершить текущий план", role: .destructive) {
                        confirmingCancel = true
                    }
                }
            }
        }
        .glassRow()
        .listStyle(.insetGrouped)
        .scrollIndicators(.hidden)
        .confirmationDialog(
            "Завершить план?",
            isPresented: $confirmingCancel,
            titleVisibility: .visible
        ) {
            Button("Завершить план", role: .destructive) {
                store.cancelPlan()
                dismiss()
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Дневная цель вернётся к расчёту по профилю. Записи о еде и весе останутся на месте.")
        }
        .navigationTitle(store.plan.map(\.title) ?? String(localized: "Новый план"))
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Шапка: где мы на дистанции и сколько есть сегодня. Два числа, ради которых
    /// экран открывают, — остальное ниже и мельче.
    private func hero(_ plan: Plan) -> some View {
        let status = store.planAdherence()?.status
        let finished = plan.isFinished

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: finished ? "flag.checkered" : "target")
                    .foregroundStyle(finished ? Color.secondary : Color.yellow)
                Text(plan.title)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if let status, !finished {
                    // Компактный значок вместо подписи: полная подпись статуса
                    // ломалась на две строки и утаскивала за собой название плана.
                    // Словами статус всё равно назван ниже, в разборе.
                    Image(systemName: status.icon)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(status.color)
                        .padding(6)
                        .background(status.color.opacity(0.12), in: Circle())
                        .accessibilityLabel(Text(verbatim: status.title))
                }
            }

            if !finished {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: "\(store.adaptedTodayGoal)")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("ккал сегодня")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                weightTrack(plan, tint: status?.color ?? .accentColor)

                // Полоса фаз только когда их несколько: у плана из одной фазы
                // она повторяла бы то, что уже сказано неделей и темпом.
                if plan.phases.count > 1 {
                    PlanTimeline(plan: plan)
                }

                HStack(spacing: 6) {
                    Text(String(format: String(localized: "Неделя %d из %d"),
                                plan.currentWeek, plan.durationWeeks))
                    if let phase = plan.currentPhase, plan.phases.count > 1 {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(phase.intent.title)
                    }
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(String(format: "%+.2f \(String(localized: "кг/нед"))", plan.weeklyRateKg))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassCard()
    }

    /// Полоса пройденного пути — по весу, а не по времени.
    ///
    /// Раньше тут был прогресс по календарю: на третьей неделе из восьми он честно
    /// показывал 37%, даже если вес не сдвинулся ни на грамм. Рядом с целевым весом
    /// это читалось как «идём по плану», хотя план как раз проваливался.
    /// Без взвешиваний считать нечего — тогда полоса остаётся по времени и подписана
    /// соответственно.
    private func weightTrack(_ plan: Plan, tint: Color) -> some View {
        let current = store.latestWeight?.weightKg
        let total = plan.targetWeightKg - plan.startWeightKg
        let byWeight = current != nil && abs(total) > 0.05
        let progress: Double = byWeight
            ? min(max((current! - plan.startWeightKg) / total, 0), 1)
            : plan.progress

        return VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.channel(thickness: 8))
                    Capsule()
                        .fill(tint)
                        .frame(width: max(3, geo.size.width * progress))
                        .glowingFill(tint, thickness: 8)
                }
            }
            .frame(height: 8)

            HStack {
                Text(String(format: "%.1f \(String(localized: "кг"))", plan.startWeightKg))
                Spacer()
                if byWeight, let current {
                    let left = abs(plan.targetWeightKg - current)
                    Text(String(format: String(localized: "осталось %.1f кг"), left))
                        .foregroundStyle(left <= 0.1 ? Color.green : Color.secondary)
                } else {
                    Text("нет взвешиваний")
                }
                Spacer()
                Text(String(format: "%.1f \(String(localized: "кг"))", plan.targetWeightKg))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
    }

    /// Из чего уходит вес.
    ///
    /// Главный вопрос натурала на сушке, на который весы одни ответить не могут:
    /// «минус 6 кг» — это успех или съеденные мышцы. Показываем обе части и прямо
    /// говорим, где заканчивается точность метода.
    private func compositionSection(_ change: CompositionChange) -> some View {
        Section {
            resultRow("Вес", String(format: "%.1f → %.1f \(String(localized: "кг"))", change.startWeightKg, change.endWeightKg))
            resultRow("Жир", String(format: "%.1f → %.1f \(String(localized: "кг"))  (%+.1f)",
                                    change.startFatKg, change.endFatKg, change.fatDeltaKg))
            resultRow("Сухая масса", String(format: "%.1f → %.1f \(String(localized: "кг"))  (%+.1f)",
                                            change.startLeanKg, change.endLeanKg, change.leanDeltaKg),
                      highlighted: change.verdict != .leanLoss)

            VStack(alignment: .leading, spacing: 6) {
                Label(change.verdict.title, systemImage: verdictIcon(change.verdict))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(verdictColor(change.verdict))
                Text(verbatim: change.verdict.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
        } header: {
            Text("Из чего уходит вес")
        } footer: {
            Text(String(
                format: String(localized: "По замерам от %1$@ и %2$@. Процент жира считается лентой, у метода погрешность около ±3%% — на твоём весе это ±%3$.1f кг сухой массы, и изменения меньше этого считать нельзя."),
                change.fromDate.formatted(.dateTime.day().month(.abbreviated)),
                change.toDate.formatted(.dateTime.day().month(.abbreviated)),
                change.noiseKg
            ))
        }
    }

    private func verdictIcon(_ verdict: CompositionVerdict) -> String {
        switch verdict {
        case .leanLoss:    return "exclamationmark.triangle.fill"
        case .leanGain:    return "arrow.up.circle.fill"
        case .withinNoise: return "checkmark.circle.fill"
        }
    }

    private func verdictColor(_ verdict: CompositionVerdict) -> Color {
        switch verdict {
        case .leanLoss:    return .orange
        case .leanGain:    return .green
        case .withinNoise: return .green
        }
    }

    /// Итог вместо слежения: план дошёл до финиша, и дальше он не «идёт», а ждёт,
    /// пока его закроют. Пока не закрыт, дневная норма продолжает держать дефицит —
    /// поэтому кнопка тут заметная, а не спрятана внизу вместе с отменой.
    @ViewBuilder
    private func outcomeSection(_ outcome: PlanOutcome) -> some View {
        Section {
            resultRow("Старт плана", String(format: "%.1f \(String(localized: "кг"))", outcome.plan.startWeightKg))
            if let final = outcome.finalWeightKg {
                resultRow("Финиш", String(format: "%.1f \(String(localized: "кг"))", final))
            }
            resultRow("Цель", String(format: "%.1f \(String(localized: "кг"))", outcome.plan.targetWeightKg))

            if let shortfall = outcome.shortfallKg {
                if outcome.reachedTarget {
                    Label("Цель взята", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                } else {
                    Label(
                        String(format: String(localized: "Не хватило %.1f кг"), shortfall),
                        systemImage: "flag.checkered"
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                }
            } else {
                Text("За время плана не было взвешиваний — подвести итог не по чему.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                store.cancelPlan()
                dismiss()
            } label: {
                Text("Завершить план")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)
        } header: {
            Text("План завершён")
        } footer: {
            Text("Пока план не закрыт, дневная норма продолжает держать его дефицит. Заверши — она вернётся к расчёту по профилю, или увеличь срок ниже, чтобы продолжить.")
        }
    }

    private func adherenceSection(plan: Plan, adherence: PlanAdherence) -> some View {
        Section {
            PlanProgressChart(plan: plan, entries: store.weightEntries)

            statusRow(adherence.status)

            resultRow("Ожидаемый вес сегодня", String(format: "%.1f \(String(localized: "кг"))", adherence.expectedWeightToday))
            if let actual = adherence.actualWeightToday {
                resultRow("Фактический вес (тренд)", String(format: "%.1f \(String(localized: "кг"))", actual))
            }
            if let deviation = adherence.deviationKg {
                resultRow("Отклонение", String(format: "%+.1f \(String(localized: "кг"))", deviation))
            }

            if adherence.status == .insufficientData {
                if let gap = adherence.dataGap {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: gap.progress)
                            .progressViewStyle(.engraved(.blue))
                        if gap.weighInsLogged < gap.weighInsRequired {
                            Text("Взвешиваний: \(gap.weighInsLogged) из \(gap.weighInsRequired)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if gap.daysUntilTrend > 0 {
                            Text("Тренд появится через \(gap.daysUntilTrend) дн.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Text("Пока недостаточно данных — взвешивайся регулярно хотя бы неделю, чтобы увидеть фактический темп.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                if let projectedEndDate = adherence.projectedEndDate {
                    resultRow("При текущем темпе цель — к", projectedEndDate.formatted(.dateTime.day().month(.wide)))
                }

                if adherence.status == .ahead {
                    aheadActions(plan: plan, adherence: adherence)
                } else {
                    behindOrOnTrackActions(plan: plan, adherence: adherence)
                }
            }
        } header: {
            Text("Как идёт план")
        }
    }

    @ViewBuilder
    private func aheadActions(plan: Plan, adherence: PlanAdherence) -> some View {
        // Вариант 1: замедлить — есть больше, прийти к цели к исходной дате
        if let recalibrated = adherence.recalibratedDailyCalories, !plan.cyclingEnabled {
            VStack(alignment: .leading, spacing: 8) {
                Text("Замедлить: при \(recalibrated) ккал/день придёшь к \(String(format: "%.1f", plan.targetWeightKg)) кг к \(plan.endDate.formatted(.dateTime.day().month(.wide))).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Ставить \(recalibrated) ккал/день") {
                    store.dailyGoal = recalibrated
                }
                .buttonStyle(.bordered)
            }
        } else if plan.cyclingEnabled, let recalibrated = adherence.recalibratedDailyCalories {
            Text("При включённом цикле замедлить темп можно через увеличение целевого веса или срока — расчёт (\(recalibrated) ккал/день в среднем) пересчитается автоматически.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }

        // Вариант 2: финишировать раньше — принять новый срок
        if let projectedEndDate = adherence.projectedEndDate,
           projectedEndDate < plan.endDate.addingTimeInterval(-3 * 86400) {
            Button("Перенести финиш на \(projectedEndDate.formatted(.dateTime.day().month(.wide)))") {
                store.reschedulePlan(to: projectedEndDate)
            }
        }

        // Вариант 3: углубить цель — показываем к какому весу придёт к исходной дате
        if let projected = adherence.projectedWeightAtPlanEnd {
            let rounded = (projected * 10).rounded() / 10
            VStack(alignment: .leading, spacing: 8) {
                Text("Углубить цель: при текущем темпе к \(plan.endDate.formatted(.dateTime.day().month(.wide))) ты можешь достичь \(String(format: "%.1f", rounded)) кг.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Поставить цель \(String(format: "%.1f", rounded)) кг") {
                    // Меняется темп последней фазы, а не срок: просьба дойти до
                    // другого веса — про то, как быстро идти, а не когда кончить.
                    store.startPlan(plan.retargeted(to: rounded))
                }
                .buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder
    private func behindOrOnTrackActions(plan: Plan, adherence: PlanAdherence) -> some View {
        if let recalibrated = adherence.recalibratedDailyCalories, recalibrated != store.dailyGoal, !plan.cyclingEnabled {
            VStack(alignment: .leading, spacing: 8) {
                Text("Чтобы успеть к \(plan.endDate.formatted(.dateTime.day().month(.wide))):")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Ставить \(recalibrated) ккал/день") {
                    store.dailyGoal = recalibrated
                }
                .buttonStyle(.bordered)
            }
        } else if plan.cyclingEnabled, let recalibrated = adherence.recalibratedDailyCalories {
            Text("При включённом цикле точную корректировку стоит вносить через целевой вес/срок — расчёт (\(recalibrated) ккал/день в среднем) учтёт её автоматически.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }

        if let projectedEndDate = adherence.projectedEndDate,
           projectedEndDate > plan.endDate.addingTimeInterval(7 * 86400) {
            Button("Сдвинуть финиш на \(projectedEndDate.formatted(.dateTime.day().month(.wide)))") {
                store.reschedulePlan(to: projectedEndDate)
            }
        }
    }

    private func statusRow(_ status: PlanStatus) -> some View {
        Label(status.title, systemImage: status.icon)
            .foregroundStyle(status.color)
            .font(.subheadline.weight(.semibold))
    }

    private func resultRow(_ title: LocalizedStringKey, _ value: String, highlighted: Bool = false) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(highlighted ? .primary : .secondary)
            Spacer()
            Text(value)
                .font(highlighted ? .body.weight(.semibold) : .body)
                .foregroundStyle(highlighted ? .green : .primary)
        }
    }
}
