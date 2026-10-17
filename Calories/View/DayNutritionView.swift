import SwiftUI
import Charts

/// Разбор дня: макросы и микронутриенты на одном экране.
///
/// Раньше про макросы рассказывали три всплывающих окошка на карточке — по
/// одному на белки, жиры и углеводы. Их приходилось открывать по очереди,
/// сравнить их между собой было нельзя, а для витаминов места в таком формате
/// не нашлось бы вовсе. Здесь всё лежит рядом и читается сверху вниз.
struct DayNutritionView: View {
    var store: CalorieStore
    var date: Date = Date()

    /// Выбранный ломоть кольца состава. Nil — выбран весь день.
    @State private var selectedPart: DayCategories.Part.ID?
    /// Угол, по которому ткнули. `chartAngleSelection` отдаёт градусы, а не
    /// сегмент, поэтому угол здесь промежуточный — сегмент из него считаем.
    @State private var selectedAngle: Double?

    private var macros: Macros {
        let day = Calendar.current.startOfDay(for: date)
        return (store.entriesByDay[day] ?? []).reduce(Macros.zero) { $0 + $1.macros }
    }

    private var micronutrients: MicronutrientDay {
        store.micronutrients(on: date)
    }

    /// Из каких категорий продуктов собран день.
    private var categories: [DayCategories.Part] {
        store.categoryBreakdown(on: date)
    }

    private var analysis: [DayAnalysis.Advice] {
        let day = Calendar.current.startOfDay(for: date)
        let entries = store.entriesByDay[day] ?? []
        return DayAnalysis.advice(.init(
            macros: macros,
            calories: entries.reduce(0) { $0 + $1.calories },
            goal: store.goal(for: date),
            proteinTarget: store.proteinTarget,
            fatTarget: store.fatTarget,
            carbsTarget: store.carbsTarget,
            weightKg: store.weightKg,
            isFast: store.isFastDay(date),
            // Сегодняшний день ещё идёт: недобор в обед — это не недобор.
            isInProgress: Calendar.current.isDateInToday(date),
            fiber: micronutrients.fiber
        ))
    }

    /// Обстоятельства дня: почему он получился таким.
    private var context: [DayAnalysis.Advice] {
        DayAnalysis.context(store.dayContext(on: date),
                            brief: ExplanationSettings.shared.level == .expert)
    }

    var body: some View {
        List {
            if !categories.isEmpty {
                Section {
                    compositionChart
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    compositionLegend
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } header: {
                    Text("Состав рациона")
                } footer: {
                    if categories.contains(where: { $0.category == nil }) {
                        explain("Доли считаются в калориях. «Неизвестно» — еда, записанная одной строкой: из чего она собрана, приложение не знает.").map { Text($0) }
                    } else {
                        explain("Доли считаются в калориях: так видно, на что действительно уходит день, а не сколько позиций в дневнике.").map { Text($0) }
                    }
                }
            }

            if !context.isEmpty {
                Section {
                    ForEach(context) { item in
                        adviceRow(item)
                    }
                } header: {
                    Text("Как прошёл день")
                } footer: {
                    explain("Сон, нагрузка, пульс и вес норму не оценивают — они объясняют, почему день получился таким.").map { Text($0) }
                }
            }

            if !analysis.isEmpty {
                Section {
                    ForEach(analysis) { item in
                        adviceRow(item)
                    }
                } header: {
                    Text("Разбор")
                }
            }

            Section {
                macroRow(.protein, value: macros.protein, target: store.proteinTarget, color: MacroKind.protein.color)
                macroRow(.fat, value: macros.fat, target: store.fatTarget, color: MacroKind.fat.color)
                macroRow(.carbs, value: macros.carbs,
                         target: store.carbsTarget ?? MacroTargets.carbsMinimum, color: MacroKind.carbs.color)
                // Клетчатка живёт здесь, а не среди витаминов: она часть
                // углеводов, её считают в граммах, как макрос, и знают о ней
                // не только продукты встроенной базы — Open Food Facts отдаёт
                // её тоже. Среди витаминов она пропадала вместе с ними, стоило
                // дню собраться из магазинной еды.
                if let fiber = micronutrients.fiber {
                    fiberRow(fiber)
                }
            } header: {
                Text("Белки, жиры, углеводы")
            }

            micronutrientSection
        }
        .glassRow()
        .listStyle(.insetGrouped)
        .scrollIndicators(.hidden)
        .screenTitle(String(localized: "Разбор дня"),
                     eyebrow: date.formatted(.dateTime.day().month(.wide)))
    }

    // MARK: - Состав и разбор

    /// Кольцо состава: по категориям продуктов, в середине — калории дня.
    ///
    /// Раньше здесь делились белки, жиры и углеводы — то же самое, что тремя
    /// строками ниже, только кружком. Категории отвечают на другой вопрос:
    /// чего в рационе не было вовсе.
    private var compositionChart: some View {
        let parts = categories
        let shown = parts.first { $0.id == selectedPart }
        return Chart(parts) { part in
            // Выбранный сегмент выходит из кольца наружу и тянет на себя
            // внимание, остальные приглушаются. Двигаем внешний радиус, а не
            // толщину: кольцо остаётся кольцом, просто один ломоть выдвинут.
            SectorMark(angle: .value("Калории", part.calories),
                       innerRadius: .ratio(0.62),
                       outerRadius: .ratio(part.id == selectedPart ? 1.0 : 0.92),
                       angularInset: 1.5)
                .cornerRadius(4)
                .foregroundStyle(color(for: part))
                .opacity(selectedPart == nil || part.id == selectedPart ? 1 : 0.35)
        }
        .chartLegend(.hidden)
        .chartAngleSelection(value: $selectedAngle)
        .frame(height: 190)
        .overlay {
            // В середине — либо день целиком, либо выбранная категория.
            // Ради этого числа по сегменту и жмут: доля в процентах есть в
            // подписи, а калорий этой категории не было нигде.
            VStack(spacing: 2) {
                Text(verbatim: "\(shown?.calories ?? parts.reduce(0) { $0 + $1.calories })")
                    .font(.app(size: 26, weight: .bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(verbatim: shown.map { title(for: $0) } ?? String(localized: "ккал"))
                    .font(.app(.caption2))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 24)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selectedPart)
        // Касание — в категорию: `chartAngleSelection` отдаёт не сегмент, а
        // значение, в котором отложена дуга, и найти ломоть приходится самим.
        .onChange(of: selectedAngle) { _, value in
            let pick = value.flatMap { self.part(atValue: $0, in: parts) }
            selectedPart = pick == selectedPart ? nil : pick
        }
        .padding(.bottom, 4)
    }

    /// Какой сегмент лежит под этим касанием.
    ///
    /// Приходит не угол в градусах, а значение в единицах дуги — у нас это
    /// калории, накопленные от начала круга. Сперва я делил круг на триста
    /// шестьдесят и сравнивал с ними: всё, что дальше трёхсот шестидесяти
    /// килокалорий, проваливалось мимо цикла и выбирало последний ломоть —
    /// то есть любое касание выбирало одно и то же.
    private func part(atValue value: Double, in parts: [DayCategories.Part]) -> DayCategories.Part.ID? {
        var cursor = 0.0
        for part in parts {
            cursor += Double(part.calories)
            if value <= cursor { return part.id }
        }
        return parts.last?.id
    }

    /// Подписи под кольцом: сеткой, а не строкой — категорий бывает под
    /// десяток, и в одну строку они не помещаются.
    private var compositionLegend: some View {
        let columns = [GridItem(.adaptive(minimum: 130), spacing: 8, alignment: .leading)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(categories) { part in
                HStack(spacing: 5) {
                    Circle()
                        .fill(color(for: part))
                        .frame(width: 7, height: 7)
                    Text(title(for: part))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(verbatim: "\(Int((part.share * 100).rounded()))%")
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
                // Подпись — такая же дверь к числу, как и сам ломоть: попасть
                // пальцем в узкий сегмент на два процента нельзя, а в строку
                // под кольцом можно.
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedPart = selectedPart == part.id ? nil : part.id
                }
                .opacity(selectedPart == nil || part.id == selectedPart ? 1 : 0.45)
            }
        }
        .font(.app(.caption2))
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selectedPart)
    }

    private func color(for part: DayCategories.Part) -> Color {
        // «Неизвестно» было почти прозрачным — настолько, что выбранным оно
        // выглядело так же, как погашенным, и нажатие по нему читалось как
        // «ничего не случилось». Серый остаётся серым, но ломтём, а не дымкой.
        part.category?.color ?? Color.secondary.opacity(0.55)
    }

    private func title(for part: DayCategories.Part) -> String {
        part.category?.title ?? String(localized: "Неизвестно")
    }

    private func adviceRow(_ item: DayAnalysis.Advice) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon(for: item.tone))
                .font(.app(.footnote))
                .foregroundStyle(color(for: item.tone))
                .frame(width: 18)
            Text(verbatim: item.text)
                .font(.app(.footnote))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private func icon(for tone: DayAnalysis.Advice.Tone) -> String {
        switch tone {
        case .good:    return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info:    return "info.circle"
        }
    }

    private func color(for tone: DayAnalysis.Advice.Tone) -> Color {
        switch tone {
        case .good:    return ProgressRing.kcalColors[0]
        case .warning: return .orange
        case .info:    return .secondary
        }
    }

    // MARK: - Макросы

    private func macroRow(_ kind: MacroKind, value: Double, target: Double?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(LocalizedStringKey(kind.title))
                Spacer()
                Text(String(format: "%.0f \(String(localized: "г"))", value))
                    .font(.app(.body, weight: .semibold))
                    .foregroundStyle(color)
                    .monospacedDigit()
                if let target {
                    Text(verbatim: "/ \(Int(target.rounded()))")
                        .font(.app(.caption))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }

            // Граммы на килограмм — то, в чём цели и задаются. Без пересчёта
            // «120 г белка» ничего не говорит: много это или мало, зависит от веса.
            if kind != .carbs, let weightKg = store.weightKg, weightKg > 0 {
                Text(String(format: String(localized: "%.2f г/кг при весе %.1f кг"), value / weightKg, weightKg))
                    .font(.app(.caption2))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Text(note(for: kind))
                .font(.app(.caption2))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }

    /// Клетчатка той же строкой, что макросы: граммы, цель и зачем она.
    private func fiberRow(_ amount: Double) -> some View {
        let target = Micronutrient.fiber.dailyValue
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Клетчатка")
                Spacer()
                Text(String(format: "%.0f \(String(localized: "г"))", amount))
                    .font(.app(.body, weight: .semibold))
                    .foregroundStyle(MacroKind.carbs.color)
                    .monospacedDigit()
                Text(verbatim: "/ \(Int(target.rounded()))")
                    .font(.app(.caption))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            explain("Входит в углеводы, но калорий почти не даёт. Держит сытость и кишечник; на дефиците про неё забывают первой.").map { Text($0) }
                .font(.app(.caption2))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }

    private func note(for kind: MacroKind) -> String {
        switch kind {
        case .protein:
            return String(localized: "Норма белка из профиля — от веса или от сухой массы, смотря что выбрано.")
        case .fat:
            return String(localized: "Норма жира из профиля. Ниже 0.5 г/кг рискуешь гормонами — жир нужен телу постоянно.")
        case .carbs:
            return store.carbsTarget == nil
                ? String(localized: "130 г/день — RDA, минимум глюкозы для работы мозга, не зависит от веса.")
                : String(localized: "Остаток дневной нормы после белка и жира — то, чем управляешь ты.")
        }
    }

    // MARK: - Витамины и минералы

    /// Витамины показываются, только когда есть что показать.
    ///
    /// Раньше секция стояла всегда и чаще всего объясняла, почему чисел нет:
    /// у своей еды и товаров из Open Food Facts микронутриентов не бывает.
    /// Человек, который ест в основном свои продукты, видел этот абзац каждый
    /// день — то есть экран разбора заканчивался извинением вместо разбора.
    @ViewBuilder
    private var micronutrientSection: some View {
        let day = micronutrients
        if day.totalCalories > 0, day.isTrustworthy {
            Section {
                // Клетчатка показана выше, вместе с макросами.
                ForEach(Micronutrient.allCases.filter { $0 != .fiber }) { nutrient in
                    if let amount = day.totals[nutrient] {
                        nutrientRow(nutrient, amount: amount, isEstimate: day.hasEstimates)
                    }
                }
            } header: {
                Text("Витамины и минералы")
            } footer: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: String(localized: "Посчитано по %lld%% съеденного за день."),
                                Int((day.coverage * 100).rounded())))
                    // Про оценку говорим прямо: знак «≈» сам по себе объясняет
                    // только то, что число неточное, а не откуда оно взялось.
                    if day.hasEstimates {
                        Text("Часть состава перенесена с похожей еды — это оценка.")
                    }
                }
            }
        }
    }

    private func nutrientRow(_ nutrient: Micronutrient, amount: Double,
                             isEstimate: Bool = false) -> some View {
        let share = amount / nutrient.dailyValue
        // У натрия шкала означает обратное: заполнилась — плохо. Поэтому он
        // оранжевый с самого начала, а не зелёный до какого-то порога.
        let color: Color = nutrient.isCeiling
            ? (share > 1 ? .red : .orange)
            : (share >= 1 ? .green : .blue)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(nutrient.title)
                Spacer()
                Text(verbatim: (isEstimate ? "≈ " : "") + formatted(amount, nutrient))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Text(verbatim: "\(Int((share * 100).rounded()))%")
                    .font(.app(.caption, weight: .semibold))
                    .foregroundStyle(color)
                    .monospacedDigit()
            }
            ProgressView(value: min(share, 1))
                .progressViewStyle(.engraved(color))
        }
        .padding(.vertical, 2)
    }

    /// Один формат на все нутриенты давал бы либо «0 мкг» у B12, либо «558.0 мг»
    /// у калия: они различаются на три порядка.
    private func formatted(_ amount: Double, _ nutrient: Micronutrient) -> String {
        let digits = amount < 10 ? 1 : 0
        return String(format: "%.\(digits)f \(nutrient.unit)", amount)
    }
}
