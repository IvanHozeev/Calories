import SwiftUI

/// Настройка плана: цепочка фаз, недельный цикл и расчёт под них.
///
/// Отдельно от экрана плана намеренно. Настраивают план один раз, а следят за ним
/// каждую неделю — это две разные работы с разной частотой, и на одном экране
/// главное (как идёт) оказывалось зажато между полем ввода и степпером.
struct PlanEditorView: View {
    var store: CalorieStore
    @Environment(\.dismiss) private var dismiss

    @State private var phases: [PlanPhase]
    /// Фаза, которую новый план получил по совету «Что дальше». Помечена в
    /// списке, чтобы было видно: её поставило приложение, и её можно убрать.
    @State private var suggestedID: UUID?
    @State private var cyclingEnabled: Bool
    @State private var weekendStyle: WeekendStyle

    init(store: CalorieStore) {
        self.store = store
        // Новый план начинается с той фазы, которую советует «Что дальше»:
        // после сушки — поддержание на нужный срок, а не снова сушка на восемь
        // недель, как раньше подставлялось всем подряд.
        if let plan = store.plan {
            _phases = State(initialValue: plan.phases)
            _suggestedID = State(initialValue: nil)
        } else {
            let first = Self.suggestedPhase(store.phaseAdvice(bodyFatPercent: store.measuredBodyFatPercent))
            _phases = State(initialValue: [first])
            _suggestedID = State(initialValue: first.id)
        }
        _cyclingEnabled = State(initialValue: store.plan?.cyclingEnabled ?? false)
        _weekendStyle = State(initialValue: store.plan?.weekendStyle ?? .satSun)
    }

    private var currentWeight: Double {
        store.latestWeight?.weightKg ?? store.profile?.weightKg ?? 0
    }

    private var startWeight: Double {
        store.plan?.startWeightKg ?? currentWeight
    }

    private var tdee: Double {
        store.profile?.tdee ?? Double(store.dailyGoal)
    }

    private var draftPlan: Plan? {
        guard startWeight > 0, !phases.isEmpty else { return nil }
        return Plan(
            startDate: store.plan?.startDate ?? Date(),
            startWeightKg: startWeight,
            phases: anchoredPhases,
            cyclingEnabled: cyclingEnabled,
            weekendStyle: weekendStyle
        )
    }

    var body: some View {
        Form {
            // Маршрут целиком — первым: куда план приведёт и когда. Раньше это
            // был «Расчёт» в самом низу, под настройками, и чтобы увидеть
            // финиш, приходилось долистывать до него после каждой правки.
            Section {
                PlanRouteCard(plan: draftPlan, tdee: tdee,
                              weightSource: store.latestWeight != nil
                                ? String(localized: "Взято из последнего взвешивания.")
                                : String(localized: "Взято из профиля — стоит записать актуальный вес на экране «Вес»."))
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }

            // Совет — плашкой цвета калорий: прежде чем выбирать фазы, полезно
            // знать, что телу сейчас выгоднее и почему.
            if store.plan == nil {
                let advice = store.phaseAdvice(bodyFatPercent: store.measuredBodyFatPercent)
                Section {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "lightbulb")
                            .font(.app(.body, weight: .semibold))
                            .foregroundStyle(ProgressRing.kcalColors[0])
                        VStack(alignment: .leading, spacing: 3) {
                            Text(verbatim: advice.headline)
                                .font(.app(.subheadline, weight: .semibold))
                            Text(verbatim: advice.detail)
                                .font(.app(.footnote))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(ProgressRing.kcalColors[0].opacity(0.14),
                                in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    .accessibilityIdentifier("phaseAdvice")
                }
            }

            // Пройденные фазы — итогом, а не настройкой: план закончен, и
            // то, что было прожито, смотрят, а не правят.
            if store.plan == nil, !store.phaseHistory.isEmpty {
                Section {
                    ForEach(store.phaseHistory.sorted { $0.endDate > $1.endDate }) { record in
                        NavigationLink {
                            PhaseSummaryView(store: store, record: record)
                        } label: {
                            finishedPhaseRow(record)
                        }
                    }
                } header: {
                    Text("Пройденные фазы")
                }
            }

            Section {
                // Перетаскивать фазы можно прямо так, без «Править».
                //
                // Порядок фаз — это и есть план: сушка перед набором или
                // после — разные годы жизни. С iOS 27 список умеет это сам;
                // на 26 остаётся прежний способ, он никуда не делся.
                if #available(iOS 27, *) {
                    phaseRows.reorderable()
                } else {
                    phaseRows
                }
                if phases.isEmpty {
                    Text("Добавь первую фазу кнопками ниже.")
                        .font(.app(.subheadline))
                        .foregroundStyle(.secondary)
                }
            } header: {
                // У нового плана это не сохранённое, а предложенное: фаза
                // по умолчанию принималась за запись о только что завершённой.
                Text(store.plan == nil ? "Фазы нового плана" : "Фазы")
            }

            // Кнопки добавления — своей строкой под карточкой фаз, цветом
            // своей фазы: какая что добавит, видно до нажатия.
            Section {
                HStack(spacing: 8) {
                    ForEach(PlanIntent.allCases) { intent in
                        Button {
                            addPhase(intent)
                        } label: {
                            // Значок и слово руками, не `Label`: в строке
                            // списка он показывал одну иконку.
                            HStack(spacing: 4) {
                                Image(systemName: "plus")
                                    .font(.app(.caption, weight: .bold))
                                Text(verbatim: intent.title)
                                    .font(.app(.subheadline, weight: .semibold))
                                    .lineLimit(1)
                            }
                            .fixedSize()
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        // Серый поддержания на кнопке читается как
                        // выключенная — у неё обычный вторичный цвет.
                        .tint(intent == .maintenance ? Color.secondary : PhaseLook.color(intent))
                        .accessibilityIdentifier("addPhase-\(intent.rawValue)")
                    }
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            } footer: {
                explain("Сушка, выход в поддержание, набор — это один план, а не три. Порядок фаз меняется перетаскиванием, темп каждой считается от веса, с которым она начинается.").map { Text($0) }
            }
            .listSectionSpacing(8)

            Section {
                Toggle("Недельный цикл калорий", isOn: $cyclingEnabled.animation(.snappy))
                if cyclingEnabled, let draftPlan {
                    // Неделя столбиками: рефид-дни выше и цветом жиров. Таблица
                    // из семи чисел читалась хуже, чем рисунок недели.
                    WeekCycleBars(days: draftPlan.weeklyCalorieBreakdown(tdee: tdee))
                    Picker("Рефид-дни", selection: $weekendStyle) {
                        ForEach(WeekendStyle.allCases) { style in
                            VStack(alignment: .leading) {
                                Text(style.title)
                                Text(style.subtitle)
                                    .font(.app(.caption))
                                    .foregroundStyle(.secondary)
                            }
                            .tag(style)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }
            } header: {
                Text("Неделя")
            } footer: {
                if cyclingEnabled {
                    explain("В \(weekendStyle.title) калорий больше, в остальные дни — меньше. Среднее за неделю остаётся тем же.",
                            short: "Среднее за неделю не меняется").map { Text($0) }
                } else {
                    explain("Одинаковая норма каждый день. Включи цикл, если хочешь распределить калории по дням недели с рефид-днями.").map { Text($0) }
                }
            }
        }
        .glassRow()
        .screenTitle(store.plan == nil ? String(localized: "Новый план") : String(localized: "Изменить план"), trailingButtons: 1)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                CheckmarkButton {
                    guard let draftPlan else { return }
                    store.startPlan(draftPlan)
                    dismiss()
                }
                .disabled(draftPlan == nil)
                .fontWeight(.semibold)
            }
        }
    }

    /// Фаза по совету: что, сколько недель и с каким темпом.
    static func suggestedPhase(_ advice: PhaseAdvice.Recommendation) -> PlanPhase {
        let intent: PlanIntent
        switch advice.kind {
        case .cut: intent = .cut
        case .bulk: intent = .bulk
        case .maintain: intent = .maintenance
        }
        return PlanPhase(intent: intent, durationWeeks: advice.weeks ?? 8,
                         weeklyRatePercent: intent == .maintenance ? nil : advice.weeklyRatePercent)
    }

    /// Добавить фазу — в конец, ничего не подменяя.
    private func addPhase(_ intent: PlanIntent) {
        withAnimation(.snappy) {
            phases.append(PlanPhase(intent: intent, durationWeeks: intent == .maintenance ? 4 : 8))
        }
    }

    /// Фазы, где расписание брейков не лезет в прошлое.
    ///
    /// Брейки включили посреди сушки: у человека седьмая неделя дефицита,
    /// а расписание «раз в четыре» поставило бы брейк на пятую, задним числом.
    /// Первый брейк сдвигается на ближайшую неделю, дальше — как выбрано.
    private var anchoredPhases: [PlanPhase] {
        guard let plan = store.plan else { return phases }
        return phases.map { phase in
            var phase = phase
            let stored = plan.phases.first { $0.id == phase.id }
            // Если меняется и длина фазы, и расписание брейков — первый брейк
            // может оказаться в прошлом. Сбрасываем и считаем заново.
            guard phase.dietBreakEvery != stored?.dietBreakEvery ||
                  phase.durationWeeks != stored?.durationWeeks else { return phase }
            phase.firstDietBreakAfter = nil
            if let every = phase.dietBreakEvery,
               let elapsed = plan.cutWeeksElapsed(inPhaseWithID: phase.id, on: Date()),
               elapsed > every {
                phase.firstDietBreakAfter = elapsed
            }
            return phase
        }
    }

    /// Вес, с которым фаза начинается, — по фазам до неё.
    private func weight(atStartOf phase: PlanPhase) -> Double {
        guard let index = phases.firstIndex(where: { $0.id == phase.id }) else { return startWeight }
        var weight = startWeight
        for earlier in phases.prefix(index) {
            weight += earlier.weeklyRateKg(fromWeightKg: weight) * Double(earlier.durationWeeks)
        }
        return weight
    }

    /// Фазы списком — отдельным свойством, чтобы переупорядочивание
    /// включалось только там, где оно есть, а сам список не раздваивался.
    private var phaseRows: some DynamicViewContent {
        ForEach($phases) { $phase in
            NavigationLink {
                PlanPhaseEditorView(phase: $phase,
                                    startWeightKg: weight(atStartOf: phase),
                                    startDate: startDate(of: phase),
                                    isFirst: phases.first?.id == phase.id,
                                    onRemove: removable ? { remove(phase) } : nil)
            } label: {
                routeRow(phase)
            }
            .accessibilityIdentifier("planPhaseRow")
            // Без отступов сверху и снизу: линия маршрута у соседних строк
            // должна сходиться в одну.
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] + 36 }
        }
        .onDelete { offsets in
            // У идущего плана последнюю фазу не отдаём: план без фаз — не
            // план, а «Готово» заблокировалось бы при старом плане в сторе. У
            // нового убрать можно и единственную — подставленную по совету,
            // чтобы собрать свой план с нуля; сохранить пустой нельзя.
            guard store.plan == nil || phases.count > offsets.count else { return }
            phases.remove(atOffsets: offsets)
        }
        .onMove { phases.move(fromOffsets: $0, toOffset: $1) }
    }

    /// Пройденная фаза: сколько недель было на деле и каким стал вес — не
    /// задуманное, а то, чем она закончилась.
    private func finishedPhaseRow(_ record: PhaseRecord) -> some View {
        HStack(spacing: 10) {
            Image(systemName: record.intent.symbol)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.intent.title)
                Text(String(format: String(localized: "%lld нед."), record.weeks))
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
            if let end = record.endWeightKg {
                Text(String(format: "%.1f \(String(localized: "кг"))", end))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    /// Можно ли убрать фазу с её экрана: у идущего плана последнюю — нельзя.
    private var removable: Bool { store.plan == nil || phases.count > 1 }

    private func remove(_ phase: PlanPhase) {
        withAnimation(.snappy) { phases.removeAll { $0.id == phase.id } }
    }

    /// Когда фаза начинается — со всеми брейками фаз перед ней.
    private func startDate(of phase: PlanPhase) -> Date {
        let start = Calendar.current.startOfDay(for: store.plan?.startDate ?? Date())
        guard let index = phases.firstIndex(where: { $0.id == phase.id }) else { return start }
        let weeks = phases.prefix(index).reduce(0) { $0 + $1.expandedWeeks }
        return Calendar.current.date(byAdding: .day, value: weeks * 7, to: start) ?? start
    }

    /// Фаза — остановкой маршрута: кружок цвета фазы на общей линии, название,
    /// темп, даты и вес, с которым она закончится.
    private func routeRow(_ phase: PlanPhase) -> some View {
        let index = phases.firstIndex(where: { $0.id == phase.id }) ?? 0
        let start = weight(atStartOf: phase)
        let weekly = phase.weeklyRateKg(fromWeightKg: start)
        let end = start + weekly * Double(phase.durationWeeks)
        let from = startDate(of: phase)
        let to = Calendar.current.date(byAdding: .day, value: phase.expandedWeeks * 7 - 1, to: from) ?? from
        let line = Color.secondary.opacity(0.25)
        return HStack(alignment: .center, spacing: 14) {
            VStack(spacing: 0) {
                Rectangle().fill(index == 0 ? Color.clear : line).frame(width: 2, height: 14)
                ZStack {
                    Circle().fill(PhaseLook.color(phase.intent))
                    Image(systemName: phase.intent.symbol)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(PhaseLook.ink(phase.intent))
                }
                .frame(width: 22, height: 22)
                Rectangle().fill(index == phases.count - 1 ? Color.clear : line)
                    .frame(width: 2)
                    .frame(minHeight: 14, maxHeight: .infinity)
            }
            .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(phase.title)
                    .font(.app(.body, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                HStack(spacing: 6) {
                    Text(String(format: String(localized: "%lld нед."), phase.durationWeeks))
                    if phase.intent == .maintenance {
                        Text(verbatim: "·")
                        Text("вес держим")
                    } else {
                        Text(verbatim: "·")
                        // Резкий темп — оранжевым на самом числе.
                        Text(verbatim: String(format: "%+.2f %@", weekly, String(localized: "кг/нед")))
                            .foregroundStyle(phase.isAggressive ? Color.orange : Color.secondary)
                    }
                    if phase.intent == .cut, let every = phase.dietBreakEvery {
                        Text(verbatim: "·")
                        Text(String(format: String(localized: "брейк %lld : 1"), every))
                    }
                }
                .font(.app(.caption))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                let dates = Text(verbatim: "\(from.formatted(.dateTime.day().month(.abbreviated))) — \(to.formatted(.dateTime.day().month(.abbreviated)))")
                    .font(.app(.caption))
                    .foregroundStyle(.tertiary)
                    .fixedSize()
                // Плашка — в строке дат, а если там тесно, строкой ниже: у
                // названия она переносила его, в подписи — обрезала подпись.
                if phase.id == suggestedID {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 6) { dates; suggestedChip }
                        VStack(alignment: .leading, spacing: 4) { dates; suggestedChip }
                    }
                } else {
                    dates
                }
            }
            .padding(.vertical, 12)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                Text(String(format: "%.1f", end))
                    .font(.app(.body, weight: .semibold))
                Text("кг к концу")
                    .font(.app(.caption2))
                    .foregroundStyle(.secondary)
            }
            .monospacedDigit()
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var suggestedChip: some View {
        Text("рекомендация")
            .font(.app(.caption2, weight: .semibold))
            .foregroundStyle(ProgressRing.kcalColors[0])
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(ProgressRing.kcalColors[0].opacity(0.15), in: Capsule())
            .fixedSize()
    }
}
