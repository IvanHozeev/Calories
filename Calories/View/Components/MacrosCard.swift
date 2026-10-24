import SwiftUI

/// Макросы за день одной стеклянной плашкой под кольцом.
///
/// В стиле строки плана и недели: без белой карточки, тихо, цвет — только у
/// цифр и тонких полосок, и это те же цвета, что у дуг кольца. Белая карточка
/// с крупными системными цветами была самым тяжёлым пятном под кольцом.
struct MacrosCard: View {
    let macros: Macros
    let proteinTarget: Double?
    let fatTarget: Double?
    /// Остаток нормы после белка и жира. nil — целей ещё нет, показываем минимум.
    var carbsTarget: Double? = nil
    /// Клетчатка за день — nil, когда про день известно слишком мало.
    ///
    /// Четвёртой, а не среди витаминов: её считают в граммах, как макрос, и
    /// недобирают её чаще, чем любой из трёх, — именно потому, что её нигде
    /// не было видно, пока не откроешь разбор.
    var fiber: Double? = nil
    let weightKg: Double?
    /// Открыть разбор дня. Раньше на карточке жили три всплывающих окошка —
    /// по одному на макрос. Их приходилось открывать по очереди, сравнить их
    /// между собой было нельзя, а витаминам в таком формате места нет вовсе.
    var onOpen: () -> Void = {}
    /// Какой макрос сейчас ведущий — тот, что ещё не закрыт.
    ///
    /// Нужен не для расчёта, а для внимания: колонка ведущего чуть заметнее,
    /// а закрытие макроса видно как событие — иначе смена цвета по всему
    /// приложению читается как сбой, пока не поймаешь правило.
    var focus: MacroKind? = nil

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // Четыре отдельные плитки, а не одна карточка с четырьмя колонками.
        //
        // Карточка читалась одним предметом — «макросы», — и чтобы узнать про
        // белок, глаз сперва находил карточку, потом колонку в ней. Плитки
        // стоят вровень с «приёмом» и «планом» ниже: четыре ответа на четыре
        // вопроса, каждый сам по себе.
        //
        // Два ряда, а не один: в строке из четырёх каждой достаётся восемьдесят
        // семь точек, и «319 / 434 г» туда уже не помещается.
        let isBig = dynamicTypeSize.isAccessibilitySize
        return Group {
            if isBig {
                VStack(spacing: 10) { tiles }
            } else {
                Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                    GridRow {
                        macroTile(.protein, value: macros.protein)
                        macroTile(.fat, value: macros.fat)
                    }
                    GridRow {
                        macroTile(.carbs, value: macros.carbs)
                        fiberTile
                    }
                }
            }
        }
        // Полоски ходят вместе с дугами кольца, той же пружиной.
        .animation(.spring(response: 0.65, dampingFraction: 0.85), value: macros)
        // Смена ведущего макроса — отдельное, более медленное движение: это
        // смена смысла, а не изменение числа.
        .animation(.easeInOut(duration: 0.5), value: focus)
    }

    /// Те же четыре плитки подряд — для крупного шрифта.
    @ViewBuilder
    private var tiles: some View {
        macroTile(.protein, value: macros.protein)
        macroTile(.fat, value: macros.fat)
        macroTile(.carbs, value: macros.carbs)
        fiberTile
    }

    private func macroTile(_ kind: MacroKind, value: Double) -> some View {
        tile(title: LocalizedStringKey(kind.title),
             value: value,
             target: target(for: kind),
             color: kind.color,
             isLeading: focus == kind,
             // Имя — одной плитке, а не всем четырём.
             //
             // На обёртке его наследовал каждый из четырёх кнопок, и поиск по
             // нему находил четыре элемента вместо одного. Ведут они в одно
             // место, так что хватает и одной: белок стоит первым.
             identifier: kind == .protein ? "openDayNutrition" : nil)
    }

    /// Клетчатка — цветом углеводов: она их часть, и своего цвета у неё нет.
    private var fiberTile: some View {
        tile(title: "Клетчатка",
             value: fiber,
             target: Micronutrient.fiber.dailyValue,
             color: MacroKind.carbs.color,
             isLeading: false)
    }

    /// Одна плитка: подпись, число с целью и полоска под ними.
    ///
    /// Пока про день известно мало, вместо числа прочерк: ноль здесь означал
    /// бы «не ел», а на деле мы просто не знаем — клетчатку отдаёт не всякий
    /// источник.
    private func tile(title: LocalizedStringKey, value: Double?, target: Double?,
                      color: Color, isLeading: Bool, identifier: String? = nil) -> some View {
        let progress = (value.flatMap { v in target.map { $0 > 0 ? min(v / $0, 1) : 0 } }) ?? 0
        return Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.app(.caption2))
                    // Подпись ведущего макроса — его цветом: приложение
                    // подсказывает, куда смотреть, не добавляя ни строчки.
                    .foregroundStyle(isLeading ? color : Color.secondary.opacity(0.6))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(verbatim: value.map { String(format: "%.0f", $0) } ?? "—")
                        .font(.app(.headline))
                        .foregroundStyle(color)
                        .contentTransition(.numericText())
                    if let target {
                        Text(verbatim: "/ \(Int(target.rounded()))")
                            .font(.app(.caption2))
                            .foregroundStyle(.tertiary)
                    }
                    Text("г")
                        .font(.app(.caption2))
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                }
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(color.opacity(0.18))
                        Capsule().fill(color)
                            .frame(width: geometry.size.width * progress)
                    }
                }
                .frame(height: 3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(height: TodayTile.height)
            .contentShape(RoundedRectangle(cornerRadius: 18))
            // Стекло, собранное руками: заливка, кант и тень. Почему не
            // системное — в `TileSurface`.
            .tileSurface()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier ?? "")
    }

    private func target(for kind: MacroKind) -> Double? {
        switch kind {
        case .protein: return proteinTarget
        case .fat: return fatTarget
        case .carbs: return carbsTarget ?? MacroTargets.carbsMinimum
        }
    }
}

