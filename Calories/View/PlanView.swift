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
            // Порядок — как в макете: фаза и статус, вес, неделя, цена
            // дефицита, норма на следующую неделю. Подробности прогноза и
            // настройки брейка и цикла — ниже, для тех, кто пришёл за ними.
            if let plan = store.plan {
                Section {
                    PlanPhaseCard(plan: plan,
                                  adherence: store.planOutcome == nil ? store.planAdherence() : nil)
                    PlanWeightCard(plan: plan, entries: store.weightEntries,
                                   trend: { store.weightTrend(on: $0) })
                }
                // Без своих боковых отступов: карточки во всю ширину секции,
                // как все остальные ниже. С шестнадцатью точками по бокам
                // они выходили уже недельного итога и строк настроек.
                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            if let outcome = store.planOutcome {
                outcomeSection(outcome)
            }

            // Итог недели: что съедено, куда пошёл вес и что из этого следует.
            // Это часть Premium, как и сам план, и сюда ведёт строка
            // «Недельный обзор» с «Сегодня».
            if store.planOutcome == nil {
                WeekReviewView(store: store).weekSection
            }

            if store.planOutcome == nil, let plan = store.plan {
                costSection(plan)
            }

            if store.planOutcome == nil {
                WeekReviewView(store: store).proposalSection
            }

            if store.planOutcome == nil, let plan = store.plan, let adherence = store.planAdherence() {
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
        // Карточка фазы — сразу под заголовком, как в макете: системный
        // отступ над первой секцией оставлял над ней пустую полосу.
        .contentMargins(.top, 4, for: .scrollContent)
        .scrollIndicators(.hidden)
        .alert("Завершить план?", isPresented: $confirmingCancel) {
            Button("Отмена", role: .cancel) {}
            Button("Завершить план", role: .destructive) {
                store.cancelPlan()
                dismiss()
            }
        } message: {
            // Остаётся только то, чего человек не знает: что он ничего не
            // теряет. Куда денется цель — следствие самого завершения.
            Text("Записи о еде и весе останутся")
        }
        .screenTitle(String(localized: "План"), trailingButtons: 1)
        // Правка в тулбаре, а не строкой списка: настраивают план один раз,
        // а смотрят на него каждую неделю, и строка занимала место в самом
        // низу, куда ради неё приходилось долистывать весь разбор.
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    PlanEditorView(store: store)
                } label: {
                    Image(systemName: "pencil")
                }
                .accessibilityLabel("Изменить план")
                .accessibilityIdentifier("editPlan")
            }
        }
    }

    /// Из чего уходит вес.
    ///
    /// Главный вопрос натурала на сушке, на который весы одни ответить не могут:
    /// «минус 6 кг» — это успех или съеденные мышцы. Показываем обе части и прямо
    /// говорим, где заканчивается точность метода.
    private func compositionSection(_ change: CompositionChange, intent: PlanIntent?) -> some View {
        Section {
            // Крупно — насколько изменилось, подписью — откуда и куда.
            //
            // Вопрос секции «из чего уходит вес», и ответ на него — дельты.
            // Шесть чисел в столбик заставляли вычитать в уме, чтобы узнать
            // то, что приложение уже посчитало.
            ResultRow(title: "Вес",
                      value: String(format: "%+.1f \(String(localized: "кг"))",
                                    change.endWeightKg - change.startWeightKg),
                      caption: String(format: "%.1f → %.1f", change.startWeightKg, change.endWeightKg))
            ResultRow(title: "Жир",
                      value: String(format: "%+.1f \(String(localized: "кг"))", change.fatDeltaKg),
                      caption: String(format: "%.1f → %.1f", change.startFatKg, change.endFatKg))
            // Зелёным — только прибавка, которую метод способен различить.
            // Плюс килограмм при шуме в два с лишним красился как достижение,
            // а строкой ниже тот же килограмм назывался «на месте».
            ResultRow(title: "Сухая масса",
                      value: String(format: "%+.1f \(String(localized: "кг"))", change.leanDeltaKg),
                      highlighted: change.verdict == .leanGain,
                      caption: String(format: "%.1f → %.1f", change.startLeanKg, change.endLeanKg))

            // Сила — из GymLogger: вес и жир говорят, сколько ушло, сила —
            // какой ценой. Строки нет, если соседа нет или рядом с началом
            // и концом не было тренировок.
            if let strength = store.strengthChange(from: change.fromDate, to: change.toDate) {
                ResultRow(title: "Сила",
                          value: String(format: "%+.0f%%", strength.percent),
                          highlighted: strength.outcome == .gain,
                          caption: strength.outcome.title)
            }

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
            case .bulk:        Text("Из чего набирается вес").listSectionTitle()
            case .maintenance: Text("Из чего состоит вес").listSectionTitle()
            default:           Text("Из чего уходит вес").listSectionTitle()
            }
        } footer: {
            // Две вещи, и обе нужны: когда снято и где кончается точность.
            // Остальное — пересказ того, что человек уже прочёл в числах.
            // Заодно ушла вторая точка после сокращённой даты.
            Text(String(
                format: String(localized: "Замеры %1$@ и %2$@ · лентой, ±%3$.1f кг сухой массы — шум"),
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
        case .tooSoon:       return .secondary
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
            ResultRow(title: "Старт плана", value: String(format: "%.1f \(String(localized: "кг"))", outcome.plan.startWeightKg))
            if let final = outcome.finalWeightKg {
                ResultRow(title: "Финиш", value: String(format: "%.1f \(String(localized: "кг"))", final))
            }
            ResultRow(title: "Цель", value: String(format: "%.1f \(String(localized: "кг"))", outcome.plan.targetWeightKg))
            if let strength = store.strengthChange(from: outcome.plan.startDate, to: Date()) {
                ResultRow(title: "Сила",
                          value: String(format: "%+.0f%%", strength.percent),
                          highlighted: strength.outcome == .gain,
                          caption: strength.outcome.title)
            }

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
            .buttonStyle(.mainAction)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)
        } header: {
            Text("План завершён").listSectionTitle()
        } footer: {
            explain("Пока план не закрыт, дневная норма продолжает держать его дефицит. Заверши — она вернётся к расчёту по профилю, или увеличь срок ниже, чтобы продолжить.").map { Text($0) }
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
                // Передумать можно, пока идёт первая неделя брейка: он встаёт
                // с текущей недели, то есть сразу, и кнопки «убрать» иначе не
                // было бы вовсе.
                if plan.pendingManualDietBreak(on: today) != nil {
                    Button("Убрать брейк", role: .destructive) {
                        store.cancelPendingDietBreak()
                    }
                    .accessibilityIdentifier("cancelDietBreak")
                }
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
                    // Брейк встаёт с текущей недели плана, то есть действует
                    // с сегодняшнего дня. Дату начала показывать незачем —
                    // она в прошлом или сегодня, а человеку важно, что норма
                    // поднимется сейчас.
                    Menu {
                        Section(String(localized: "Начнётся сегодня")) {
                            Button("На 1 неделю") { store.startDietBreak(weeks: 1) }
                            Button("На 2 недели") { store.startDietBreak(weeks: 2) }
                        }
                    } label: {
                        HStack {
                            Label("Взять брейк", systemImage: "plus.circle.fill")
                            Spacer()
                            Text("Сегодня")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("startDietBreak")
                }
            }
        } header: {
            Text("Диет-брейк").listSectionTitle()
        } footer: {
            explain("Неделя-две на поддержании. Жир за сушку уходит так же, а голод и тяга сорваться — заметно меньше. Брейк действует с сегодняшнего дня, финиш сдвигается на его длину, целевой вес не меняется.").map { Text($0) }
        }
    }

    /// Цена дефицита: что с силой и сколько ещё терпеть до перерыва.
    ///
    /// Запас диеты жил в секции брейка, под его кнопками, а сила — только в
    /// разборе состава, который появляется к концу фазы. Это один вопрос —
    /// во что обходится сушка, — и ответ на него теперь одной карточкой.
    @ViewBuilder
    private func costSection(_ plan: Plan) -> some View {
        let today = Date()
        let strength = plan.phaseIndex(on: today).flatMap {
            store.strengthChange(from: plan.startDate(ofPhaseAt: $0), to: today)
        }
        let input = store.recoveryInput(now: today)
        let reserve = (!plan.isDietBreak(on: today) && input.isCutting) ? DietReserve(input) : nil
        if strength != nil || reserve != nil {
            Section {
                if let strength {
                    HStack(spacing: 10) {
                        Image(systemName: "dumbbell")
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: strength.outcome.title)
                                .font(.app(.subheadline, weight: .semibold))
                            Text("с начала фазы, по GymLogger")
                                .font(.app(.caption))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(verbatim: String(format: "%+.0f%%", strength.percent))
                            .font(.app(.body, weight: .semibold))
                            .monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("planStrength")
                }
                if let reserve {
                    dietReserveRow(reserve)
                }
            } footer: {
                // Что это за полоска: без пояснения «запас» читался как запас
                // калорий или еды.
                if reserve != nil {
                    Text("Запас диеты — сколько недель дефицита ты уже прошёл до рекомендованного перерыва. Чем полнее полоска, тем ближе диет-брейк: после долгого дефицита расход падает и голод растёт. На крутом темпе она заполняется быстрее.")
                }
            }
        }
    }

    /// Полоска «Запас диеты»: чем ближе перерыв, тем она полнее и краснее.
    private func dietReserveRow(_ reserve: DietReserve) -> some View {
        let color: Color = reserve.isDue ? ProgressRing.overColors[0] : MacroKind.fat.color
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Запас диеты")
                    .font(.app(.subheadline, weight: .semibold))
                Spacer()
                if reserve.isDue {
                    Text("Пора на перерыв")
                        .font(.app(.caption, weight: .semibold))
                        .foregroundStyle(color)
                } else {
                    Text("Перерыв через \(reserve.weeksLeft) нед.")
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            ProgressView(value: reserve.progress)
                .progressViewStyle(.engraved(color, thickness: 6))
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("dietReserve")
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
            Text("Эта неделя").listSectionTitle()
        } footer: {
            // Объяснение — только когда есть что нажать: в сам рефид-день
            // «перенеси на сегодня» без кнопки звучит как издёвка.
            if plan.refeedSwapDay(for: today) != nil {
                explain("Праздник не в тот день — перенеси рефид на сегодня. Он меняется местами с самым сытным днём, что ещё впереди на этой неделе, так что недельный дефицит не меняется. Со следующего понедельника — обычная раскладка.").map { Text($0) }
            }
        }
    }

    private func adherenceSection(plan: Plan, adherence: PlanAdherence) -> some View {
        Section {
            // Статус, темп и график — в карточках наверху. Здесь то, что из
            // них следует: прогноз финиша и что с ним можно сделать.

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
                    ResultRow(title: "Фактический вес (тренд)", value: String(format: "%.1f \(String(localized: "кг"))", actual))
                }
            } else {
            // Резкий темп называем вслух и здесь, а не только в редакторе:
            // именно сюда человек смотрит каждую неделю.
            if let phase = plan.currentPhase, phase.isAggressive {
                Label(String(format: String(localized: "Темп идущей фазы %1$@ %% массы в неделю — выше разумного предела в %2$@ %%. Сдвинь финиш дальше или подними целевой вес."),
                             String(format: "%.2f", phase.weeklyRatePercent),
                             String(format: "%.1f", phase.intent.aggressiveRatePercent)),
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.app(.caption))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

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

            // Вес одной строкой вместо трёх.
            //
            // Было: ожидаемый, фактический и отклонение — тремя рядами. Но
            // ожидаемый вес человек не выбирает и ничего с ним не делает, а
            // отклонение и есть разница между двумя первыми. Остаётся факт
            // крупно и отклонение подписью под ним — ровно то, ради чего
            // сюда смотрят: где я и насколько в стороне от плана.
            if let actual = adherence.actualWeightToday {
                ResultRow(title: "Вес",
                          value: String(format: "%.1f \(String(localized: "кг"))", actual),
                          caption: adherence.deviationKg.map { deviation in
                              // Ноль отклонения — это «ровно по плану», а не
                              // «на 0.0 кг позади»: округление до десятых
                              // делало из попадания отставание.
                              let off = abs(deviation)
                              guard off >= 0.05 else { return String(localized: "ровно по плану") }
                              return String(format: deviation < 0
                                            ? String(localized: "на %@ кг впереди плана")
                                            : String(localized: "на %@ кг позади плана"),
                                            String(format: "%.1f", off))
                          })
            } else {
                ResultRow(title: "Ожидаемый вес сегодня",
                          value: String(format: "%.1f \(String(localized: "кг"))", adherence.expectedWeightToday))
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
                // Дата финиша — только когда темп от нуля отличается. При трёх
                // взвешиваниях наклон с тем же успехом может быть нулём, и
                // «цель к 3 ноября» там — обещание точности, которой нет.
                if adherence.rateIsIndistinguishableFromZero {
                    Label("Темп пока не отличим от нуля: вес шумит сильнее, чем движется. Дата финиша появится, когда тренд станет уверенным.",
                          systemImage: "questionmark.circle")
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let projectedEndDate = adherence.projectedEndDate {
                    // Коридор — подписью под датой: та же цель при темпе на
                    // границах погрешности. Своей строкой он выглядел вторым
                    // сроком, а без него одна дата читается как обещание.
                    ResultRow(title: "Цель",
                              value: Self.planDate(projectedEndDate),
                              caption: adherence.projectedEndRange().map {
                                  String(format: String(localized: "от %1$@ до %2$@"),
                                         Self.planDate($0.lowerBound), Self.planDate($0.upperBound))
                              })
                }
                // Темп рядом с датой: без него дата в следующем августе выглядит
                // опечаткой, а с ним понятно, откуда она взялась.
                if let rate = adherence.observedWeeklyRateKg {
                    ResultRow(title: "Темп",
                              value: String(format: "%+.2f \(String(localized: "кг/нед"))", rate),
                              caption: adherence.trendFit.map {
                                  String(format: String(localized: "разброс ±%@"),
                                         String(format: "%.2f", $0.standardErrorKg))
                              })
                }

                // Шаг назад — рядом с предложениями, которые этот шаг и
                // делают. Возвращает план целиком: срок, цель и норму.
                if let previous = store.revertablePlan {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(format: String(localized: "Было: %1$@ кг к %2$@"),
                                    String(format: "%.1f", previous.targetWeightKg),
                                    Self.planDate(previous.endDate)))
                            .font(.app(.caption))
                            .foregroundStyle(.secondary)
                        Button("Вернуть прежний план") {
                            store.revertPlan()
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("revertPlan")
                    }
                }

                // Разбор расхождения — туда же, где названо само расхождение.
                // Вопрос «почему так» задают ровно здесь и ровно в эту секунду.
                NavigationLink {
                    StallReportView(store: store)
                } label: {
                    Label("Почему так", systemImage: "magnifyingglass")
                }
                .accessibilityIdentifier("openStallReport")

                if adherence.status == .ahead {
                    // Три предложения ниже — взаимоисключающие ответы на один
                    // и тот же запас: он тратится один раз, и принять надо
                    // что-то одно. Стопкой кнопок они читались как список дел,
                    // и человек проходил его сверху вниз.
                    // Без вступления: вердикт «Опережаешь график» стоит выше,
                    // а что запас тратится один раз, видно по самим кнопкам.
                    aheadActions(plan: plan, adherence: adherence)
                } else {
                    behindOrOnTrackActions(plan: plan, adherence: adherence)
                }
            }
            }
        } header: {
            Text("Прогноз").listSectionTitle()
        }
    }

    /// Насколько прибавка к норме должна быть заметной, чтобы о ней говорить.
    ///
    /// Полсотни килокалорий в день — это около пятидесяти граммов веса в неделю,
    /// то есть меньше, чем шумит сам тренд. Предлагать такое значит звать
    /// человека менять норму ради ничего.
    static let meaningfulCalorieGain = 50

    /// Дата на экране плана: с годом, если она не в этом году.
    ///
    /// Без года прогноз на десять месяцев вперёд печатался как «4 августа» и
    /// читался как прошедший день — цель, к которой уже опоздал.
    static func planDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: Date())
        return sameYear
            ? date.formatted(.dateTime.day().month(.wide))
            : date.formatted(.dateTime.day().month(.wide).year())
    }

    /// Предложение, после которого план становится резче разумного, — не
    /// предложение, а ловушка.
    ///
    /// Из жизни: человек согласился финишировать раньше, потом съесть больше,
    /// потом углубить цель — и каждый шаг по отдельности был верным, а вместе
    /// они загнали темп на 1.27 кг в неделю и срезали норму на четыреста
    /// килокалорий. Каждое предложение теперь проверяется по тому плану,
    /// который из него получится.
    private func isSafe(_ plan: Plan) -> Bool { !plan.hasAggressivePhase }

    @ViewBuilder
    private func aheadActions(plan: Plan, adherence: PlanAdherence) -> some View {
        // Вариант 1: есть больше и всё равно прийти к цели в срок.
        //
        // Только пока темп говорит то же, что и положение: иначе выходил совет
        // есть больше человеку, у которого вес и так стоит.
        //
        // И только когда прибавка заметна. Раньше предложение показывалось
        // всегда и выглядело бессмыслицей: «замедлить — и прийти к той же цели
        // к той же дате». Человек не видел, что меняется, потому что менялась
        // не цель, а размер тарелки, а про него текст и не говорил.
        if let recalibrated = adherence.recalibratedDailyCalories, !plan.cyclingEnabled,
           adherence.projectionAgreesWithPlan,
           recalibrated - store.dailyGoal >= Self.meaningfulCalorieGain {
            let extra = recalibrated - store.dailyGoal
            VStack(alignment: .leading, spacing: 8) {
                // Кнопка ниже уже называет норму целиком, а цель и срок
                // стоят выше по экрану. Остаётся прибавка — единственное,
                // чего человек ещё не видел.
                Text("+\(extra) ккал в день, цель и срок те же")
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
                Button("Ставить \(recalibrated) ккал/день") {
                    // Через стор, а не присваиванием: он запомнит, что норму
                    // выбрали пересчётом, и дальше поведёт её так же.
                    store.acceptRecalibratedGoal(recalibrated)
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
           projectedEndDate < plan.endDate.addingTimeInterval(-3 * 86400),
           isSafe(plan.rescheduled(toEnd: projectedEndDate)) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Та же цель, но раньше: темп пересчитается под новый срок.")
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
                Button("Перенести финиш на \(Self.planDate(projectedEndDate))") {
                    store.reschedulePlan(to: projectedEndDate)
                }
                .buttonStyle(.bordered)
            }
        }

        // Вариант 3: углубить цель — но только если при нынешнем темпе выходит
        // вес глубже целевого. Иначе это предложение ослабить цель, названное
        // углублением.
        if let rounded = adherence.deeperTarget, isSafe(plan.retargeted(to: rounded)) {
            VStack(alignment: .leading, spacing: 8) {
                Text("При этом темпе к сроку выходит меньше")
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
                Text("Чтобы успеть к \(Self.planDate(plan.endDate)):")
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
                Button("Ставить \(recalibrated) ккал/день") {
                    store.acceptRecalibratedGoal(recalibrated)
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
            VStack(alignment: .leading, spacing: 8) {
                Button("Сдвинуть финиш на \(Self.planDate(projectedEndDate))") {
                    store.reschedulePlan(to: projectedEndDate)
                }
                Button("Цель под новый срок") {
                    store.reschedulePlan(to: projectedEndDate, adjustTarget: true)
                }
            }
        }
    }


}
