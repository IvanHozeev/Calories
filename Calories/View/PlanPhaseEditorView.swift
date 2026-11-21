import SwiftUI

/// Одна фаза плана: сколько недель, с каким темпом, с брейками ли и как в неё
/// входить.
///
/// Срок — крупным числом в тёмной карточке, под ним недели клетками: так видно,
/// куда встанут брейки и насколько они удлинят фазу. Темп — тремя карточками
/// со смыслом («бережно», «рабочий», «предел»), а не степпером в сотых долях
/// процента: никто не знает, чем 0.65% отличается от 0.7%. Точная настройка
/// осталась — строкой под карточками.
struct PlanPhaseEditorView: View {
    @Binding var phase: PlanPhase
    /// Вес, с которого фаза стартует: проценты показываем и в килограммах.
    let startWeightKg: Double
    /// Когда фаза начинается — для дат под клетками недель.
    var startDate: Date = Date()
    /// Первая фаза переходить не от чего — у неё перехода нет.
    var isFirst: Bool = false
    /// Убрать фазу из плана. nil — нельзя (последняя фаза идущего плана).
    var onRemove: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    private var weeklyKg: Double { phase.weeklyRateKg(fromWeightKg: startWeightKg) }
    private var endWeightKg: Double { startWeightKg + weeklyKg * Double(phase.durationWeeks) }
    private var endDate: Date {
        Calendar.current.date(byAdding: .day, value: phase.expandedWeeks * 7, to: startDate) ?? startDate
    }

    var body: some View {
        Form {
            Section {
                weeksCard
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }

            if !phase.isDietBreak, phase.intent != .maintenance {
                paceSection
            }

            if !phase.isDietBreak, phase.intent == .cut {
                Section {
                    Picker("Диет-брейки", selection: $phase.dietBreakEvery) {
                        Text("Вручную").tag(Int?.none)
                        ForEach(PlanPhase.dietBreakOptions, id: \.self) { every in
                            Text(String(format: String(localized: "%lld : 1"), every)).tag(Int?.some(every))
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    .accessibilityIdentifier("dietBreakSchedule")
                } header: {
                    Text("Диет-брейки")
                } footer: {
                    explain("«Вручную» — брейк берёшь сам, когда нужен, на экране плана. «4 : 1» — неделя поддержания после каждых четырёх недель дефицита, приложение ставит её само; взять внеплановый брейк можно и так. Срок фазы — недели дефицита, брейки добавляются к нему.").map { Text($0) }
                }
            }

            if !isFirst, !phase.isDietBreak {
                Section {
                    Picker("Выход из прошлой фазы", selection: $phase.rampWeeks) {
                        Text("Сразу").tag(0)
                        Text("1 неделя").tag(1)
                        Text("2 недели").tag(2)
                        // Настроенный раньше переход длиннее — не теряем его.
                        if phase.rampWeeks > 2 {
                            Text(String(format: String(localized: "%lld нед."), phase.rampWeeks)).tag(phase.rampWeeks)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                } header: {
                    Text("Выход из прошлой фазы")
                } footer: {
                    explain("Выход из дефицита прыжком возвращает гликоген и воду: весы за три дня показывают плюс пару килограммов, к жиру не имеющих отношения. Пока норма поднимается плавно, приложение и не считает этот скачок отставанием.").map { Text($0) }
                }
            }

            Section {
                forecastCard
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }

            if let onRemove {
                Section {
                    Button("Убрать фазу", role: .destructive) {
                        dismiss()
                        onRemove()
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("removePhase")
                }
            }
        }
        .glassRow()
        .navigationTitle(phase.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Срок

    /// Тёмная карточка: число недель крупно, «−» и «+» по краям, под ними
    /// недели клетками — дефицит, брейки — и даты начала и конца.
    private var weeksCard: some View {
        let range = phase.isDietBreak ? 1...2 : 1...52
        return VStack(spacing: 16) {
            HStack {
                stepButton("minus", label: "Меньше недель") {
                    phase.durationWeeks = max(range.lowerBound, phase.durationWeeks - 1)
                }
                Spacer()
                VStack(spacing: 0) {
                    Text(verbatim: "\(phase.durationWeeks)")
                        .font(.app(size: 48, weight: .bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(verbatim: String(format: String(localized: "недель · до %@"),
                                          endDate.formatted(.dateTime.day().month(.wide))))
                        .font(.app(.footnote))
                        .foregroundStyle(.white.opacity(0.65))
                }
                Spacer()
                stepButton("plus", label: "Больше недель") {
                    phase.durationWeeks = min(range.upperBound, phase.durationWeeks + 1)
                }
            }

            // Клетка — неделя. Брейки встают туда, куда их поставит расписание.
            HStack(spacing: 3) {
                ForEach(Array(weekCells.enumerated()), id: \.offset) { _, color in
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(color)
                        .frame(height: 24)
                        .frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)

            HStack {
                Text(verbatim: startDate.formatted(.dateTime.day().month(.abbreviated)))
                Spacer()
                if phase.intent == .cut, !phase.isDietBreak {
                    legend(PhaseLook.color(.cut), String(localized: "Дефицит").lowercased())
                    legend(MacroKind.fat.color, String(localized: "Брейк").lowercased())
                    Spacer()
                }
                Text(verbatim: endDate.formatted(.dateTime.day().month(.abbreviated)))
            }
            .font(.app(.caption2))
            .foregroundStyle(.white.opacity(0.65))
            .monospacedDigit()
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .background(Color(white: 0.11), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .animation(.snappy, value: phase.durationWeeks)
        .animation(.snappy, value: phase.dietBreakEvery)
    }

    private var weekCells: [Color] {
        phase.expanded().flatMap { segment in
            Array(repeating: PhaseLook.color(segment), count: segment.durationWeeks)
        }
    }

    private func legend(_ color: Color, _ title: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            Text(verbatim: title)
        }
    }

    private func stepButton(_ symbol: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.app(size: 16, weight: .bold))
                .frame(width: 44, height: 44)
                .background(.white.opacity(0.12), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }

    // MARK: - Темп

    private struct PaceOption {
        let name: LocalizedStringKey
        let percent: Double
    }

    /// Три темпа на цель. Верхний — ровно та граница, за которой приложение
    /// предупреждает (`aggressiveRatePercent`).
    private var paceOptions: [PaceOption] {
        switch phase.intent {
        case .bulk:
            return [PaceOption(name: "Осторожно", percent: 0.2),
                    PaceOption(name: "Рабочий", percent: 0.3),
                    PaceOption(name: "Предел", percent: 0.5)]
        default:
            return [PaceOption(name: "Бережно", percent: 0.5),
                    PaceOption(name: "Рабочий", percent: 0.7),
                    PaceOption(name: "Предел", percent: 1.0)]
        }
    }

    private var paceSection: some View {
        Section {
            HStack(spacing: 8) {
                ForEach(paceOptions, id: \.percent) { option in
                    paceCard(option)
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            // Точно — строкой под карточками: кому нужно 0.65%, тот найдёт.
            Stepper(value: $phase.weeklyRatePercent, in: 0.05...2.0, step: 0.05) {
                HStack {
                    Text("Точнее")
                    Spacer()
                    Text(verbatim: String(format: "%.2f%%", phase.weeklyRatePercent))
                        .foregroundStyle(phase.isAggressive ? Color.orange : Color.secondary)
                        .monospacedDigit()
                }
            }
            if phase.isAggressive {
                Label(phase.intent == .cut
                      ? "Быстрее процента веса в неделю — на сушке это уже за счёт мышц."
                      : "Быстрее половины процента в неделю — на наборе большая часть прибавки будет жиром.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.app(.caption))
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Темп")
        } footer: {
            explain("В процентах массы тела за неделю, а не в килограммах: одно и то же число подходит и лёгкому, и тяжёлому.").map { Text($0) }
        }
    }

    private func paceCard(_ option: PaceOption) -> some View {
        let selected = abs(phase.weeklyRatePercent - option.percent) < 0.001
        let kg = option.percent / 100 * startWeightKg * phase.intent.direction
        return Button {
            withAnimation(.snappy) { phase.weeklyRatePercent = option.percent }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(option.name)
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(verbatim: option.percent.formatted(.number.precision(.fractionLength(0...1))) + "%")
                    .font(.app(.title3, weight: .bold))
                Text(verbatim: String(format: "%+.2f %@", kg, String(localized: "кг/нед")))
                    .font(.app(.caption, weight: .semibold))
                    .foregroundStyle(selected ? PhaseLook.color(phase.intent) : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .monospacedDigit()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .tileSurface(cornerRadius: 18)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(selected ? Color.primary : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - Прогноз

    private var forecastCard: some View {
        let change = endWeightKg - startWeightKg
        return HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("К концу фазы")
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
                Text(verbatim: String(format: "%.1f %@", endWeightKg, String(localized: "кг")))
                    .font(.app(size: 28, weight: .bold))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(verbatim: String(format: "%+.1f %@", change, String(localized: "кг")))
                    .font(.app(.body, weight: .semibold))
                    .foregroundStyle(abs(change) < 0.05 ? Color.secondary : PhaseLook.color(phase.intent))
                Text(verbatim: String(format: String(localized: "от %@ кг"), String(format: "%.1f", startWeightKg)))
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
            }
        }
        .monospacedDigit()
        .padding(16)
        .tileSurface(cornerRadius: 24)
    }
}
