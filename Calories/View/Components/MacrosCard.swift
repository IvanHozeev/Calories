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
    /// Клетчатка известна не по всему дню — показанное число нижнее.
    var fiberIsPartial: Bool = false
    let weightKg: Double?
    /// Макросы, которые отстают от темпа дня.
    ///
    /// Тогда в углу плитки появляется стрелка цвета макроса, а подпись
    /// остаётся названием: показатель не теряет имя, пока отстаёт.
    var behindMacros: Set<MacroKind> = []
    /// Открыть разбор дня. Раньше на карточке жили три всплывающих окошка —
    /// по одному на макрос. Их приходилось открывать по очереди, сравнить их
    /// между собой было нельзя, а витаминам в таком формате места нет вовсе.
    var onOpen: () -> Void = {}
    /// Имя сегодняшней тяжёлой тренировки из соседнего приложения — или nil.
    ///
    /// Нужно для одной вещи: тихо подсветить углеводы в день ног или спины.
    /// Строкой это уже пробовали — она занимала ряд и требовала чтения;
    /// значок в углу плитки говорит то же самое и не отнимает места ни у
    /// кольца, ни у глаза.
    var gymDayName: String? = nil
    /// Какой макрос сейчас ведущий — тот, что ещё не закрыт.
    ///
    /// Нужен не для расчёта, а для внимания: колонка ведущего чуть заметнее,
    /// а закрытие макроса видно как событие — иначе смена цвета по всему
    /// приложению читается как сбой, пока не поймаешь правило.
    var focus: MacroKind? = nil

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    /// Выше плиток приёма и плана: в ней три строки, и число теперь крупнее.
    private static let tileHeight: CGFloat = 74
    /// Плитка на четверть ряда: название, число, норма и полоска — четыре
    /// строки вместо трёх. Вровень с плитками приёма и плана над ней.
    private static let narrowTileHeight: CGFloat = TodayTile.height

    var body: some View {
        // Четыре отдельные плитки, а не одна карточка с четырьмя колонками.
        //
        // Карточка читалась одним предметом — «макросы», — и чтобы узнать про
        // белок, глаз сперва находил карточку, потом колонку в ней. Плитки
        // стоят вровень с «приёмом» и «планом» ниже: четыре ответа на четыре
        // вопроса, каждый сам по себе.
        //
        // Один ряд: в нём каждой достаётся около восьмидесяти точек, и
        // «319 / 434 г» в одну строку не помещается — поэтому в узкой плитке
        // норма стоит строкой под числом («из 434 г»). На крупном шрифте
        // плитки идут столбиком, как и раньше.
        let isBig = dynamicTypeSize.isAccessibilitySize
        return Group {
            if isBig {
                VStack(spacing: 10) { tiles }
            } else {
                HStack(spacing: 8) { tiles }
            }
        }
        // Анимации здесь не на всём ряду, а на полосках и цвете подписи (ниже).
        // На ряду целиком пружина ловила и перестройку самой строки списка —
        // когда рядом исчезала подсказка и всё уезжало вверх, три плитки из
        // четырёх застревали на полпути и наезжали на карточки выше.
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
        let isBehind = behindMacros.contains(kind)
        // Подпись — всегда название. Пока отставание меняло её на «Добавь
        // белка», показатель терял имя, а оранжевый цвет призыва совпадал с
        // цветом жиров. Отставание теперь отдельным значком цвета самого
        // макроса, а призыв словами — у голоса.
        return tile(title: kind.title,
                    value: value,
                    target: target(for: kind),
                    color: kind.color,
                    isLeading: focus == kind,
                    hint: isBehind ? (symbol: kind == .carbs ? "arrow.up" : "arrow.down",
                                      label: kind.shortageTitle) : nil,
                    gymDay: kind == .carbs ? gymDayName : nil,
                    // Имя — одной плитке, а не всем четырём.
                    //
                    // На обёртке его наследовал каждый из четырёх кнопок, и поиск по
                    // нему находил четыре элемента вместо одного. Ведут они в одно
                    // место, так что хватает и одной: белок стоит первым.
                    identifier: kind == .protein ? "openDayNutrition" : nil)
    }

    /// Клетчатка — цветом углеводов: она их часть, и своего цвета у неё нет.
    private var fiberTile: some View {
        tile(title: String(localized: "Клетчатка"),
             value: fiber,
             target: Micronutrient.fiber.dailyValue,
             color: MacroKind.carbs.color,
             isLeading: false,
             // «Не меньше», когда состав известен не про весь день: клетчатка
             // складывается, и показанное — нижняя граница.
             prefix: fiberIsPartial ? "≥" : nil)
    }

    /// Одна плитка: подпись, число с целью и полоска под ними.
    ///
    /// Пока про день известно мало, вместо числа прочерк: ноль здесь означал
    /// бы «не ел», а на деле мы просто не знаем — клетчатку отдаёт не всякий
    /// источник.
    private func tile(title: String, value: Double?, target: Double?,
                      color: Color, isLeading: Bool,
                      hint: (symbol: String, label: String)? = nil,
                      gymDay: String? = nil,
                      prefix: String? = nil, identifier: String? = nil) -> some View {
        let progress = (value.flatMap { v in target.map { $0 > 0 ? min(v / $0, 1) : 0 } }) ?? 0
        let narrow = !dynamicTypeSize.isAccessibilitySize
        return Button(action: onOpen) {
            VStack(alignment: .leading, spacing: narrow ? 3 : 5) {
                HStack(spacing: narrow ? 4 : 6) {
                    // Цвет макроса — точкой у названия и полоской внизу: так
                    // он узнаётся и при чёрном числе. В плитке на четверть
                    // ряда точка мельче, чтобы «Углеводы» и «Клетчатка»
                    // не обрезались многоточием.
                    Circle()
                        .fill(color)
                        .frame(width: narrow ? 6 : 8, height: narrow ? 6 : 8)
                    Text(verbatim: title)
                        .font(.app(.caption))
                        // Подпись ведущего макроса — его цветом: приложение
                        // подсказывает, куда смотреть, не добавляя ни строчки.
                        .foregroundStyle(isLeading ? color : Color.secondary)
                        .animation(.easeInOut(duration: 0.5), value: isLeading)
                        .lineLimit(1)
                        .minimumScaleFactor(narrow ? 0.6 : 0.8)
                }

                if narrow {
                    // Число и под ним норма: в плитке на четверть ряда рядом
                    // они не помещаются. Значки — справа от числа, а не в углу
                    // плитки: наверху им места не хватало, и они налезали на
                    // название.
                    VStack(alignment: .leading, spacing: 0) {
                        // Значок — вплотную к числу и по его середине: у правой
                        // кромки на базовой линии он отрывался от числа и
                        // проседал вниз.
                        HStack(alignment: .center, spacing: 5) {
                            Text(verbatim: value.map { v in
                                let number = String(format: "%.0f", v)
                                return prefix.map { "\($0)\(number)" } ?? number
                            } ?? "—")
                                .font(.app(.title3, weight: .bold))
                                .foregroundStyle(colorScheme == .dark ? color : Color.primary)
                                .contentTransition(.numericText())
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            marks(hint: hint, gymDay: gymDay, color: color)
                            Spacer(minLength: 0)
                        }
                        if let target {
                            Text(verbatim: String(format: String(localized: "из %lld г"), Int(target.rounded())))
                                .font(.app(.caption2))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                } else {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(verbatim: value.map { v in
                        let number = String(format: "%.0f", v)
                        return prefix.map { "\($0)\(number)" } ?? number
                    } ?? "—")
                        .font(.app(.title3, weight: .bold))
                        // В светлой теме число чёрное: голубой и персиковый
                        // на белом читаются заметно хуже, а число — то, ради
                        // чего плитку и смотрят. В тёмной цвет читается и
                        // остаётся числом макроса.
                        .foregroundStyle(colorScheme == .dark ? color : Color.primary)
                        .contentTransition(.numericText())
                    if let target {
                        Text(verbatim: "/ \(Int(target.rounded()))")
                            .font(.app(.caption))
                            .foregroundStyle(.secondary)
                    }
                    Text("г")
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    marks(hint: hint, gymDay: gymDay, color: color)
                }
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                }

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(color.opacity(0.18))
                        Capsule().fill(color)
                            .frame(width: geometry.size.width * progress)
                            .animation(.spring(response: 0.65, dampingFraction: 0.85), value: progress)
                    }
                }
                .frame(height: 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, narrow ? 8 : 14)
            .padding(.vertical, 10)
            .frame(height: narrow ? Self.narrowTileHeight : Self.tileHeight)
            .contentShape(RoundedRectangle(cornerRadius: 18))
            // Стекло, собранное руками: заливка, кант и тень. Почему не
            // системное — в `TileSurface`.
            .tileSurface()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier ?? "")
    }

    /// Значки плитки: отставание стрелкой цвета макроса, тяжёлый день —
    /// гантелью. Стоят справа от числа.
    @ViewBuilder
    private func marks(hint: (symbol: String, label: String)?, gymDay: String?, color: Color) -> some View {
        HStack(spacing: 4) {
            if let hint {
                Image(systemName: hint.symbol)
                    .font(.app(.caption2, weight: .bold))
                    .foregroundStyle(color)
                    .accessibilityLabel(Text(verbatim: hint.label))
                    .accessibilityIdentifier("macroBehind")
            }
            if let gymDay {
                GymAccent(color: color)
                    .accessibilityLabel(Text(verbatim: gymDay))
            }
        }
        .fixedSize()
    }

    private func target(for kind: MacroKind) -> Double? {
        switch kind {
        case .protein: return proteinTarget
        case .fat: return fatTarget
        case .carbs: return carbsTarget ?? MacroTargets.carbsMinimum
        }
    }
}


/// Тихий акцент на углеводах в тяжёлый день.
///
/// Пульс, а не мигание: значок дышит — медленно светлеет и темнеет, чуть
/// меняясь в размере. Этого хватает, чтобы глаз сам нашёл плитку, и мало,
/// чтобы это стало раздражать к вечеру. Движение идёт только пока значок на
/// экране: уехал — анимация уехала с ним.
private struct GymAccent: View {
    let color: Color
    @State private var breathing = false

    var body: some View {
        Image(systemName: "dumbbell.fill")
            .font(.app(.caption2))
            .foregroundStyle(color)
            .opacity(breathing ? 1 : 0.45)
            .scaleEffect(breathing ? 1.08 : 0.94)
            .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true),
                       value: breathing)
            .onAppear { breathing = true }
            .accessibilityHidden(false)
    }
}
