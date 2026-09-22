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

            if store.planOutcome == nil, let plan = store.plan, plan.phases.contains(where: { $0.intent == .cut }) {
                dietBreakSection(plan)
            }

            if store.planOutcome == nil, let plan = store.plan, plan.cyclingEnabled, !plan.isDietBreak(on: Date()) {
                weekCycleSection(plan)
            }

            if let composition = store.planCompositionChange {
                compositionSection(composition, intent: store.plan?.currentPhase?.intent)
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
        // Правка в тулбаре, а не строкой списка: настраивают план один раз,
        // а смотрят на него каждую неделю, и строка занимала место в самом
        // низу, куда ради неё приходилось долистывать весь разбор.
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    PlanEditorView(store: store)
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel("Изменить план")
                .accessibilityIdentifier("editPlan")
            }
        }
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
                    .font(.app(.headline))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if let status, !finished {
                    // Компактный значок вместо подписи: полная подпись статуса
                    // ломалась на две строки и утаскивала за собой название плана.
                    // Словами статус всё равно назван ниже, в разборе.
                    Image(systemName: status.icon)
                        .font(.app(.caption, weight: .semibold))
                        .foregroundStyle(status.color)
                        .padding(6)
                        .background(status.color.opacity(0.12), in: Circle())
                        .accessibilityLabel(Text(verbatim: status.title))
                }
            }

            if !finished {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: "\(store.adaptedTodayGoal)")
                        .font(.app(size: 34, weight: .bold))
                        .monospacedDigit()
                    Text("ккал сегодня")
                        .font(.app(.subheadline))
                        .foregroundStyle(.secondary)
                }

                weightTrack(plan, tint: status?.color ?? .accentColor)

                // Полоса фаз только когда их несколько: у плана из одной фазы
                // она повторяла бы то, что уже сказано неделей и темпом.
                if plan.timeline.count > 1 {
                    PlanTimeline(plan: plan)
                }

                HStack(spacing: 6) {
                    Text(String(format: String(localized: "Неделя %d из %d"),
                                plan.currentWeek, plan.durationWeeks))
                    if let phase = plan.currentPhase, plan.timeline.count > 1 {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(phase.title)
                    }
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(String(format: "%+.2f \(String(localized: "кг/нед"))", plan.weeklyRateKg))
                }
                .font(.app(.caption))
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        // Тем же стеклом, что строка плана на «Сегодня»: план — премиум, и
        // шапка его экрана — продолжение той строки, а не белая карточка.
        .liquidGlass(in: RoundedRectangle(cornerRadius: 22))
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
            // Тонкая полоска с подложкой того же цвета, как у макросов под
            // кольцом, — вместо толстой канавки со свечением.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(tint.opacity(0.18))
                    Capsule()
                        .fill(tint)
                        .frame(width: max(4, geo.size.width * progress))
                }
            }
            .frame(height: 4)

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
            .font(.app(.caption2))
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
    }

    /// Из чего уходит вес.
    ///
    /// Главный вопрос натурала на сушке, на который весы одни ответить не могут:
    /// «минус 6 кг» — это успех или съеденные мышцы. Показываем обе части и прямо
    /// говорим, где заканчивается точность метода.
    private func compositionSection(_ change: CompositionChange, intent: PlanIntent?) -> some View {
        Section {
            resultRow("Вес", String(format: "%.1f → %.1f \(String(localized: "кг"))", change.startWeightKg, change.endWeightKg))
            resultRow("Жир", String(format: "%.1f → %.1f \(String(localized: "кг"))  (%+.1f)",
                                    change.startFatKg, change.endFatKg, change.fatDeltaKg))
            resultRow("Сухая масса", String(format: "%.1f → %.1f \(String(localized: "кг"))  (%+.1f)",
                                            change.startLeanKg, change.endLeanKg, change.leanDeltaKg),
                      highlighted: change.verdict != .leanLoss)

            // Вердикт с оглядкой на то, зачем идёт фаза: «сухая держится» —
            // успех на сушке и провал на наборе. Без плана остаётся прежний,
            // намерения не знающий.
            VStack(alignment: .leading, spacing: 6) {
                if let intent {
                    let verdict = change.verdict(for: intent)
                    Label(verdict.title, systemImage: verdict.icon)
                        .font(.app(.subheadline, weight: .semibold))
                        .foregroundStyle(phaseVerdictColor(verdict))
                    Text(verbatim: change.advice(for: intent))
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let share = change.fatShareOfChange {
                        Text(String(format: String(localized: "Жиром — %d%% изменения веса."),
                                    Int((share * 100).rounded())))
                            .font(.app(.caption))
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                    }
                } else {
                    Label(change.verdict.title, systemImage: verdictIcon(change.verdict))
                        .font(.app(.subheadline, weight: .semibold))
                        .foregroundStyle(verdictColor(change.verdict))
                    Text(verbatim: change.verdict.explanation)
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 4)
        } header: {
            // Заголовок по намерению: на наборе вес не уходит, и спрашивать
            // «из чего уходит» там нечего.
            switch intent {
            case .bulk:        Text("Из чего набирается вес")
            case .maintenance: Text("Из чего состоит вес")
            default:           Text("Из чего уходит вес")
            }
        } footer: {
            Text(String(
                format: String(localized: "По замерам от %1$@ и %2$@. Процент жира считается лентой, у метода погрешность около ±3%% — на твоём весе это ±%3$.1f кг сухой массы, и изменения меньше этого считать нельзя."),
                change.fromDate.formatted(.dateTime.day().month(.abbreviated)),
                change.toDate.formatted(.dateTime.day().month(.abbreviated)),
                change.noiseKg
            ))
        }
    }

    private func phaseVerdictColor(_ verdict: PhaseCompositionVerdict) -> Color {
        switch verdict {
        case .worked:        return .green
        case .costly:        return .orange
        case .stalled:       return .secondary
        case .recomposition: return .green
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
                        .font(.app(.subheadline, weight: .semibold))
                        .foregroundStyle(.green)
                } else {
                    Label(
                        String(format: String(localized: "Не хватило %.1f кг"), shortfall),
                        systemImage: "flag.checkered"
                    )
                    .font(.app(.subheadline, weight: .semibold))
                    .foregroundStyle(.orange)
                }
            } else {
                Text("За время плана не было взвешиваний — подвести итог не по чему.")
                    .font(.app(.caption))
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

    /// Диет-брейк: идёт ли он, когда следующий и кнопка поставить его руками.
    ///
    /// Даты справа коротко, «пн, 14 сент.», и без предлогов: «с понедельник,
    /// 14 сентября» склонять форматтер не умеет, а подпись слева и так говорит,
    /// что это за дата.
    @ViewBuilder
    private func dietBreakSection(_ plan: Plan) -> some View {
        let today = Date()
        let short = Date.FormatStyle.dateTime.weekday(.abbreviated).day().month(.abbreviated)
        Section {
            if plan.isDietBreak(on: today) {
                let end = plan.firstNonBreakDay(from: today)
                breakRow("Идёт брейк", icon: "cup.and.saucer.fill", tint: .green,
                         detail: "Дефицит вернётся", date: end.formatted(short))
            } else if plan.pendingManualDietBreak(on: today) != nil,
                      let start = plan.nextDietBreakStart(after: today) {
                breakRow("Брейк запланирован", icon: "cup.and.saucer", tint: .green,
                         detail: "Начнётся", date: start.formatted(short))
                Button("Убрать брейк", role: .destructive) {
                    store.cancelPendingDietBreak()
                }
                .accessibilityIdentifier("cancelDietBreak")
            } else {
                if let next = plan.nextDietBreakStart(after: today) {
                    breakRow("Следующий по плану", icon: "calendar", tint: .secondary,
                             detail: nil, date: next.formatted(short))
                }
                if plan.canStartDietBreak(from: today) {
                    let start = plan.startDate(ofWeek: plan.dietBreakStartWeek(from: today))
                    Menu {
                        Section(String(format: String(localized: "Начнётся %@"), start.formatted(short))) {
                            Button("На 1 неделю") { store.startDietBreak(weeks: 1) }
                            Button("На 2 недели") { store.startDietBreak(weeks: 2) }
                        }
                    } label: {
                        HStack {
                            Label("Взять брейк", systemImage: "plus.circle.fill")
                            Spacer()
                            Text(start.formatted(short))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    .accessibilityIdentifier("startDietBreak")
                }
            }
        } header: {
            Text("Диет-брейк")
        } footer: {
            Text("Неделя-две на поддержании. Жир за сушку уходит так же, а голод и тяга сорваться — заметно меньше. Брейк встаёт с начала недели плана, финиш сдвигается на его длину, целевой вес не меняется.")
        }
    }

    private func breakRow(_ title: LocalizedStringKey, icon: String, tint: Color,
                          detail: LocalizedStringKey?, date: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail {
                    Text(detail)
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(date)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    /// Неделя цикла по дням и перенос рефида на сегодня.
    ///
    /// Здесь, а не в настройке плана: переносят рефид не раз и навсегда, а когда
    /// жизнь подкинула праздник, — и искать это в редакторе, где меняют стиль
    /// цикла на весь план, никто не станет.
    private func weekCycleSection(_ plan: Plan) -> some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let monday = Plan.weekStart(for: today)
        let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
        let offsets = plan.cycleOffsets(forWeekOf: today)
        let symbols = calendar.shortWeekdaySymbols

        return Section {
            HStack(spacing: 4) {
                ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                    let isToday = calendar.isDate(day, inSameDayAs: today)
                    let isRefeed = offsets[index] > 0
                    // Как неделя на «Сегодня»: без рамок, сегодня — жирным,
                    // рефид — точкой под числом, цвет только у неё.
                    VStack(spacing: 2) {
                        Text(symbols[(index + 1) % 7])
                            .font(.app(.caption2))
                            .foregroundStyle(.tertiary)
                        Text(store.goal(for: day).formatted())
                            .font(.app(.caption, weight: isToday ? .bold : .regular))
                            .monospacedDigit()
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                            .foregroundStyle(isToday ? .primary : .secondary)
                        Circle()
                            .fill(isRefeed ? ProgressRing.fatColors[0] : .clear)
                            .frame(width: 5, height: 5)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
            }
            .padding(.vertical, 4)

            if plan.canUndoRefeedMove(on: today) {
                Button {
                    store.undoRefeedMove()
                } label: {
                    Label("Вернуть рефид на его день", systemImage: "arrow.uturn.backward")
                }
                .accessibilityIdentifier("undoRefeedMove")
            } else if plan.refeedSwapDay(for: today) != nil {
                Button {
                    store.moveRefeed()
                } label: {
                    Label("Рефид сегодня", systemImage: "fork.knife")
                }
                .accessibilityIdentifier("moveRefeedToToday")
            }
        } header: {
            Text("Эта неделя")
        } footer: {
            // Объяснение — только когда есть что нажать: в сам рефид-день
            // «перенеси на сегодня» без кнопки звучит как издёвка.
            if plan.refeedSwapDay(for: today) != nil {
                Text("Праздник не в тот день — перенеси рефид на сегодня. Он меняется местами с самым сытным днём, что ещё впереди на этой неделе, так что недельный дефицит не меняется. Со следующего понедельника — обычная раскладка.")
            }
        }
    }

    private func adherenceSection(plan: Plan, adherence: PlanAdherence) -> some View {
        Section {
            PlanProgressChart(plan: plan, entries: store.weightEntries)

            // Во время брейка вес о плане не говорит: калории подняли, вернулись
            // вода и гликоген. Сравнение с ожидаемым, отклонение, прогноз финиша
            // и советы «замедлить/ускорить» здесь врали бы — а совет ещё и
            // переписал бы норму под неделю поддержания. Оставляем только тренд.
            if plan.isDietBreak(on: Date()) {
                Label("Идёт диет-брейк. Плюс на весах сейчас — вода и гликоген, а не жир; план по весу оценим, когда вернётся дефицит.",
                      systemImage: "cup.and.saucer.fill")
                    .font(.app(.caption))
                    .foregroundStyle(.green)
                    .fixedSize(horizontal: false, vertical: true)
                if let actual = adherence.actualWeightToday {
                    resultRow("Фактический вес (тренд)", String(format: "%.1f \(String(localized: "кг"))", actual))
                }
            } else {
            statusRow(adherence.status)

            // Пока вес устаканивается после подъёма калорий, об этом надо
            // сказать прямо. Иначе человек видит плюс полтора килограмма
            // и делает вывод про жир, которого там нет.
            if adherence.isSettlingAfterIncrease {
                Label("Калории только что подняли — вернувшиеся гликоген и вода дают на весах пару килограммов. Пока это идёт, вес о плане не говорит.",
                      systemImage: "drop.fill")
                    .font(.app(.caption))
                    .foregroundStyle(.blue)
                    .fixedSize(horizontal: false, vertical: true)
            }

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
                                .font(.app(.caption))
                                .foregroundStyle(.secondary)
                        } else if gap.daysUntilTrend > 0 {
                            Text("Тренд появится через \(gap.daysUntilTrend) дн.")
                                .font(.app(.caption))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Text("Пока недостаточно данных — взвешивайся регулярно хотя бы неделю, чтобы увидеть фактический темп.")
                    .font(.app(.caption))
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
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
                Button("Ставить \(recalibrated) ккал/день") {
                    store.dailyGoal = recalibrated
                }
                .buttonStyle(.bordered)
            }
        } else if plan.cyclingEnabled, let recalibrated = adherence.recalibratedDailyCalories {
            Text("При включённом цикле замедлить темп можно через увеличение целевого веса или срока — расчёт (\(recalibrated) ккал/день в среднем) пересчитается автоматически.")
                .font(.app(.caption2))
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
                    .font(.app(.caption))
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
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
                Button("Ставить \(recalibrated) ккал/день") {
                    store.dailyGoal = recalibrated
                }
                .buttonStyle(.bordered)
            }
        } else if plan.cyclingEnabled, let recalibrated = adherence.recalibratedDailyCalories {
            Text("При включённом цикле точную корректировку стоит вносить через целевой вес/срок — расчёт (\(recalibrated) ккал/день в среднем) учтёт её автоматически.")
                .font(.app(.caption2))
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
            .font(.app(.subheadline, weight: .semibold))
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
