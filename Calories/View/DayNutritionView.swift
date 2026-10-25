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
                    fiberRow(fiber, isPartial: micronutrients.fiberIsPartial)
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
        // Тап мимо кольца снимает выбор.
        //
        // Выбранный ломоть — состояние, из которого нужен выход, и искать для
        // него вторую кнопку незачем: выход там же, где в любом приложении, —
        // нажать рядом. Жест висит на списке, а не на отдельной подложке:
        // вложенные жесты срабатывают первыми, поэтому нажатие по самому
        // кольцу, по строке подписи или по любой ячейке списка достаётся им,
        // а сюда доходит только то, что мимо.
        .onTapGesture {
            if selectedPart != nil {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    selectedPart = nil
                }
            }
        }
        // Выбор сам отпускает через четыре секунды.
        //
        // Столько нужно, чтобы прочитать число и название, и мало настолько,
        // чтобы кольцо не осталось выбранным, когда человек уже читает строки
        // ниже. Отсчёт начинается заново на каждом новом ломте: `task(id:)`
        // отменяет прежний, и переход с куска на кусок не копит таймеров.
        .task(id: selectedPart) {
            guard selectedPart != nil else { return }
            try? await Task.sleep(for: .seconds(Self.selectionHoldSeconds))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                selectedPart = nil
            }
        }
    }

    /// Сколько держится выбранный ломоть, прежде чем отпустить сам.
    private static let selectionHoldSeconds: Double = 4

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
            //
            // Ломти толще и с круглыми концами — форма соседнего приложения,
            // где кольцо собрано из отдельных кусков, а не разрезано на доли.
            // Разница в том, что читается: дольки пирога глаз сравнивает по
            // площади, а куски кольца — по длине, и длину он сравнивает лучше.
            SectorMark(angle: .value("Калории", part.calories),
                       innerRadius: .ratio(Self.innerRatio),
                       outerRadius: .ratio(part.id == selectedPart ? 1.0 : 0.94),
                       angularInset: 2.5)
                // Конечное скругление, а не бесконечное: пока едет внешний
                // радиус выбранного ломтя, бесконечное вырождает сектор, и на
                // кадрах перехода кольцо рассыпается в шипы.
                .cornerRadius(12)
                .foregroundStyle(color(for: part))
                .opacity(selectedPart == nil || part.id == selectedPart ? 1 : 0.35)
        }
        .chartLegend(.hidden)
        .frame(height: 190)
        // Значки и попадания — из одной геометрии.
        //
        // Аннотация центрует значок по рамке сектора, а не по его дуге: у
        // ломтя на четверть круга рамка почти квадратная, и середина её лежит
        // в стороне от самой дуги. А `chartAngleSelection` знает только угол,
        // поэтому нажатие в дырку посередине или мимо кольца всё равно
        // попадало «в ломоть» — отсюда и кривые попадания. Считаем сами, зато
        // один раз: и значок, и палец меряются одним кругом.
        .chartOverlay { proxy in
            GeometryReader { geometry in
                let frame = proxy.plotFrame.map { geometry[$0] } ?? .zero
                let radius = min(frame.width, frame.height) / 2
                ZStack {
                    ForEach(iconPlacements(in: parts)) { placement in
                        Image(systemName: placement.icon)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.18), radius: 1, y: 0.5)
                            .opacity(selectedPart == nil || placement.id == selectedPart ? 1 : 0.35)
                            .position(point(at: placement.turn,
                                            radius: radius * (Self.innerRatio + 0.94) / 2,
                                            in: frame))
                    }
                }
                .allowsHitTesting(false)

                // Нажатием, а не протяжкой: протяжка над кольцом забирала бы
                // прокрутку списка, а выбор ломтя она всё равно не улучшает.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        select(at: location, center: CGPoint(x: frame.midX, y: frame.midY),
                               radius: radius, in: parts)
                    }
            }
        }
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
        .padding(.bottom, 4)
    }

    /// Точка на круге: доля оборота от двенадцати часов по часовой стрелке.
    private func point(at turn: Double, radius: CGFloat, in frame: CGRect) -> CGPoint {
        let angle = turn * 2 * .pi - .pi / 2
        return CGPoint(x: frame.midX + radius * cos(angle),
                       y: frame.midY + radius * sin(angle))
    }

    /// Выбирает ломоть под пальцем — если палец вообще на кольце.
    private func select(at location: CGPoint, center: CGPoint,
                        radius: CGFloat, in parts: [DayCategories.Part]) {
        let dx = location.x - center.x
        let dy = location.y - center.y
        let distance = sqrt(dx * dx + dy * dy)
        // Дырка посередине и поле вокруг кольца — это «мимо», и нажатие туда
        // снимает выбор, а не выбирает ближайшее по углу.
        guard distance >= radius * Self.innerRatio * 0.85, distance <= radius * 1.08 else {
            selectedPart = nil
            return
        }
        let turn = (atan2(dy, dx) + .pi / 2 + 2 * .pi).truncatingRemainder(dividingBy: 2 * .pi) / (2 * .pi)
        let pick = part(atTurn: turn, in: parts)
        selectedPart = pick == selectedPart ? nil : pick
    }

    /// Какой ломоть занимает эту долю оборота.
    private func part(atTurn turn: Double, in parts: [DayCategories.Part]) -> DayCategories.Part.ID? {
        let total = parts.reduce(0.0) { $0 + Double($1.calories) }
        guard total > 0 else { return nil }
        var cursor = 0.0
        for part in parts {
            cursor += Double(part.calories) / total
            if turn <= cursor { return part.id }
        }
        return parts.last?.id
    }

    /// Толщина кольца долей от радиуса. Чем куски толще, тем больше они
    /// читаются кусками, а не дольками разрезанного круга.
    private static let innerRatio: Double = 0.58
    /// Уже этой доли круга значок не ставим: на двух процентах он сядет
    /// поверх соседнего ломтя и оба станут нечитаемыми.
    private static let minimumShareForIcon: Double = 0.07

    /// Где на кольце стоит значок категории.
    private struct IconPlacement: Identifiable {
        let id: DayCategories.Part.ID
        let icon: String
        /// Середина ломтя в долях оборота, от двенадцати часов по часовой.
        let turn: Double
    }

    private func iconPlacements(in parts: [DayCategories.Part]) -> [IconPlacement] {
        let total = parts.reduce(0.0) { $0 + Double($1.calories) }
        guard total > 0 else { return [] }
        var cursor = 0.0
        return parts.compactMap { part in
            let share = Double(part.calories) / total
            let middle = cursor + share / 2
            cursor += share
            guard share >= Self.minimumShareForIcon, let icon = part.category?.icon else { return nil }
            return IconPlacement(id: part.id, icon: icon, turn: middle)
        }
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
    private func fiberRow(_ amount: Double, isPartial: Bool) -> some View {
        let target = Micronutrient.fiber.dailyValue
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Клетчатка")
                Spacer()
                // «Не меньше», когда состав известен не про весь день:
                // клетчатка складывается, поэтому показанное — нижняя
                // граница, а не оценка.
                Text(String(format: isPartial ? "≥ %.0f \(String(localized: "г"))"
                                              : "%.0f \(String(localized: "г"))", amount))
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
