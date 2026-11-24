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
    @Environment(\.colorScheme) private var colorScheme

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
            // Один блок вместо двух, как в макете: оценка дня и то, что за ней
            // стоит, читаются подряд. Сначала что с едой (белок, клетчатка,
            // «день ещё идёт»), потом обстоятельства — сон, нагрузка, вес.
            if !analysis.isEmpty || !context.isEmpty {
                Section {
                    ForEach(analysis) { item in
                        adviceRow(item)
                    }
                    ForEach(context) { item in
                        adviceRow(item)
                    }
                } header: {
                    Text("Как прошёл день").listSectionTitle()
                } footer: {
                    if !context.isEmpty {
                        explain("Сон, нагрузка, пульс и вес норму не оценивают — они объясняют, почему день получился таким.").map { Text($0) }
                    }
                }
            }

            Section {
                macroRow(.protein, value: macros.protein, target: store.proteinTarget, color: MacroKind.protein.color)
                macroRow(.fat, value: macros.fat, target: store.fatTarget, color: MacroKind.fat.color)
                macroRow(.carbs, value: macros.carbs,
                         target: store.carbsTarget ?? MacroTargets.carbsMinimum, color: MacroKind.carbs.color)
            } header: {
                Text("Белки, жиры, углеводы").listSectionTitle()
            }

            if !categories.isEmpty {
                Section {
                    compositionCard
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                } header: {
                    Text("Состав рациона").listSectionTitle()
                } footer: {
                    if categories.contains(where: { $0.category == nil }) {
                        explain("«Неизвестно» — еда, записанная одной строкой: из чего она собрана, приложение не знает. Справа — калории.").map { Text($0) }
                    } else {
                        explain("Справа — калории: так видно, на что действительно уходит день, а не сколько позиций в дневнике.").map { Text($0) }
                    }
                }
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

    /// Состав рациона: полоса по долям калорий и под ней — категории с числами.
    ///
    /// Раньше это было кольцо с выбором ломтя: красиво, но число калорий
    /// категории надо было вылавливать пальцем, а подписи дублировали проценты.
    /// Полоса показывает доли, список — сами калории; нажатие по строке по-прежнему
    /// выделяет категорию.
    private var compositionCard: some View {
        let parts = categories
        let columns = [GridItem(.flexible(), spacing: 16, alignment: .leading),
                       GridItem(.flexible(), spacing: 16, alignment: .leading)]
        return VStack(alignment: .leading, spacing: 14) {
            GeometryReader { geometry in
                let total = max(parts.reduce(0.0) { $0 + Double($1.calories) }, 1)
                let gaps = CGFloat(max(parts.count - 1, 0)) * 3
                HStack(spacing: 3) {
                    ForEach(parts) { part in
                        Capsule()
                            .fill(color(for: part))
                            .frame(width: max(6, (geometry.size.width - gaps) * CGFloat(Double(part.calories) / total)))
                            .opacity(selectedPart == nil || part.id == selectedPart ? 1 : 0.3)
                    }
                }
            }
            .frame(height: 10)
            .accessibilityHidden(true)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(parts) { part in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(color(for: part))
                            .frame(width: 10, height: 10)
                        Text(title(for: part))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(verbatim: part.calories.formatted())
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .font(.app(.subheadline))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedPart = selectedPart == part.id ? nil : part.id
                    }
                    .opacity(selectedPart == nil || part.id == selectedPart ? 1 : 0.45)
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selectedPart)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tileSurface(cornerRadius: 20)
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
            // Справочная строка без значка, но с пустым местом под него: её
            // текст стоит в одну линию с оценками, а не вылезает левее.
            Group {
                if item.tone == .info {
                    Color.clear
                } else {
                    Image(systemName: icon(for: item.tone))
                        .font(.app(.footnote))
                        .foregroundStyle(color(for: item.tone))
                }
            }
            .frame(width: 18)
            Text(verbatim: item.text)
                .font(.app(.subheadline))
                .foregroundStyle(item.tone == .info ? Color.secondary : Color.primary)
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
        case .warning: return ProgressRing.overColors[0]
        case .info:    return .secondary
        }
    }

    // MARK: - Макросы

    private func macroRow(_ kind: MacroKind, value: Double, target: Double?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 8) {
                    Circle().fill(color).frame(width: 10, height: 10)
                    Text(LocalizedStringKey(kind.title))
                }
                Spacer()
                // «112 из 136 г»: число крупно, норма и единица — подписью.
                // Чёрным в светлой теме, цветным в тёмной; цвет макроса
                // остаётся в точке и в полоске.
                Text(verbatim: String(format: "%.0f", value))
                    .font(.app(.body, weight: .semibold))
                    .foregroundStyle(colorScheme == .dark ? color : Color.primary)
                    .monospacedDigit()
                if let target {
                    Text(verbatim: String(format: String(localized: "из %lld г"), Int(target.rounded())))
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                } else {
                    Text("г")
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                }
            }

            if let target, target > 0 {
                // Тот же объём, что у полосок на «Сегодня» и у дуг кольца:
                // здесь макрос показан тем же материалом, что и везде.
                RubberBar(color: color, progress: min(value / target, 1), height: 6)
            }

            caption(for: kind, value: value)
        }
        .padding(.vertical, 4)
    }

    /// Одна строка под полоской. Граммы на килограмм — то, в чём цели и
    /// задаются: «120 г белка» ничего не говорит, пока неизвестен вес. У жира
    /// рядом рабочий минимум, у углеводов — откуда взята норма и клетчатка,
    /// которая раньше стояла отдельной строкой ниже.
    @ViewBuilder
    private func caption(for kind: MacroKind, value: Double) -> some View {
        let weight = store.weightKg.flatMap { $0 > 0 ? $0 : nil }
        switch kind {
        case .protein:
            if let weight {
                Text(String(format: String(localized: "%.2f г/кг при весе %.1f кг"), value / weight, weight))
                    .captionStyle()
            }
        case .fat:
            if let weight {
                Text(String(format: String(localized: "%1$.2f г/кг — рабочий минимум %2$.1f"),
                            value / weight, MacroTargets.fatFloorPerKg))
                    .captionStyle()
            }
        case .carbs:
            HStack(alignment: .firstTextBaseline) {
                Text(store.carbsTarget == nil
                     ? String(localized: "Минимум на день: на него работает мозг")
                     : String(localized: "Остаток нормы после белка и жира"))
                Spacer(minLength: 8)
                if let fiber = micronutrients.fiber {
                    // «≥19», когда состав известен не про весь день: клетчатка
                    // складывается, и показанное — нижняя граница.
                    Text(String(format: String(localized: "клетчатка %1$@ из %2$lld г"),
                                (micronutrients.fiberIsPartial ? "≥" : "") + "\(Int(fiber.rounded()))",
                                Int(Micronutrient.fiber.dailyValue.rounded())))
                }
            }
            .captionStyle()
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
                // Клетчатка показана выше, под углеводами.
                let items = Micronutrient.allCases.filter { $0 != .fiber }.compactMap { nutrient in
                    day.totals[nutrient].map { (nutrient, $0) }
                }
                micronutrientGrid(items, isEstimate: day.hasEstimates)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
            } header: {
                Text("Витамины и минералы").listSectionTitle()
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

    /// Витамины и минералы: две колонки, у каждого — название, процент нормы
    /// и тонкая полоска. Граммы и миллиграммы ушли: процент отвечает на
    /// вопрос «хватает ли», а число в микрограммах — нет.
    private func micronutrientGrid(_ items: [(Micronutrient, Double)], isEstimate: Bool) -> some View {
        let columns = [GridItem(.flexible(), spacing: 20, alignment: .top),
                       GridItem(.flexible(), spacing: 20, alignment: .top)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
            ForEach(items, id: \.0) { nutrient, amount in
                nutrientCell(nutrient, amount: amount, isEstimate: isEstimate)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tileSurface(cornerRadius: 20)
    }

    private func nutrientCell(_ nutrient: Micronutrient, amount: Double, isEstimate: Bool) -> some View {
        let share = amount / nutrient.dailyValue
        // У натрия шкала означает обратное: заполнилась — плохо. Поэтому он
        // оранжевый с самого начала, а не зелёный до какого-то порога. У
        // остальных меньше половины нормы — цветом жира, как «пока мало».
        let color: Color = nutrient.isCeiling
            ? (share > 1 ? ProgressRing.overColors[0] : MacroKind.fat.color)
            : (share >= 0.5 ? ProgressRing.kcalColors[0] : MacroKind.fat.color)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(nutrient.title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                Text(verbatim: (isEstimate ? "≈" : "") + "\(Int((share * 100).rounded()))%")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .font(.app(.subheadline))
            ProgressView(value: min(share, 1))
                .progressViewStyle(.engraved(color, thickness: 4))
        }
        .accessibilityElement(children: .combine)
    }

    /// Один формат на все нутриенты давал бы либо «0 мкг» у B12, либо «558.0 мг»
    /// у калия: они различаются на три порядка.
    private func formatted(_ amount: Double, _ nutrient: Micronutrient) -> String {
        let digits = amount < 10 ? 1 : 0
        return String(format: "%.\(digits)f \(nutrient.unit)", amount)
    }
}

private extension View {
    /// Подпись под строкой: мелко, вторым цветом, с цифрами одной ширины.
    func captionStyle() -> some View {
        font(.app(.caption))
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .fixedSize(horizontal: false, vertical: true)
    }
}
