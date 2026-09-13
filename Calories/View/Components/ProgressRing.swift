import SwiftUI

struct RingView<Label: View>: View {
    let progress: Double
    let colors: [Color]
    let labelID: AnyHashable
    @ViewBuilder let label: () -> Label

    /// Толщина кольца одной константой: трек, дуга и её отступ обязаны совпадать,
    /// а раньше это было три числа в разных местах, которые легко разъезжались.
    private let lineWidth: CGFloat = 9

    /// Канавка, прорезанная в карточке. Раньше здесь была плоская серая обводка,
    /// а на iOS 26 — стеклянный бублик; стекло убрано намеренно. Стекло лежит
    /// поверх поверхности и преломляет то, что под ним, гравировка уходит внутрь
    /// неё — две противоположные метафоры на одном элементе спорят друг с другом,
    /// и кольцо переставало читаться как одна вещь.
    private var channel: some View {
        Circle()
            .inset(by: lineWidth / 2)
            .stroke(.channel(thickness: lineWidth), style: StrokeStyle(lineWidth: lineWidth))
    }

    /// Цвет, налитый в канавку. Дуга уже канавки на пол-пункта с каждой стороны:
    /// остаётся видна стенка, и цвет не выглядит наклеенным вровень с краями.
    ///
    /// Заливка светится, а не повторяет рельеф стенок. Рельеф физически честнее,
    /// но гасит цвет — а светящаяся заливка в прорезанной канавке живее.
    private var filling: some View {
        Circle()
            .inset(by: lineWidth / 2)
            .trim(from: 0, to: progress)
            .stroke(
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                style: StrokeStyle(lineWidth: lineWidth - 1, lineCap: .round)
            )
            .glowingFill(colors.first ?? .clear, thickness: lineWidth)
            .rotationEffect(.degrees(-90))
            .animation(.spring(response: 0.65, dampingFraction: 0.85), value: progress)
    }

    var body: some View {
        ZStack {
            channel
            filling
            label()
                .id(labelID)
                .transition(.opacity.combined(with: .scale(scale: 0.85)))
        }
        .frame(width: 220, height: 220)
        // Кольцо — фиксированные 220pt, текст внутри масштабировать некуда.
        // Ограничиваем шкалу, иначе на крупных размерах цифры вылезают за круг.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }
}

/// Кольцо дня: калории и макросы, каждый своей дугой-прогрессом.
///
/// Калории — половина круга: это главное число дня. Вторая половина делится
/// между белками, жирами и углеводами по их целям в граммах, поэтому у типичной
/// сушки самая длинная дуга углеводная, а самая короткая — жировая. Длина дуги
/// — сколько нужно съесть, заливка — сколько уже съедено. Тот же знак на иконке
/// и лаунч-скрине, только там без калорий: буква «С».
///
/// Нажатие открывает добавление приёма пищи. Еду записывают по нескольку раз
/// в день, а на план смотрят раз в неделю: самая крупная мишень экрана должна
/// обслуживать частое действие. Меню со сканером и камерой живёт на плюсе.
struct ProgressRing: View {
    let consumed: Int
    let goal: Int
    var macros: Macros = .zero
    var proteinTarget: Double? = nil
    var fatTarget: Double? = nil
    var carbsTarget: Double? = nil
    /// Что делать по нажатию — записать еду.
    let onOpen: () -> Void

    private let lineWidth: CGFloat = 12
    private let size: CGFloat = 230
    /// Зазор между дугами в градусах — с запасом на скруглённые концы.
    private let gap: Double = 11

    private struct Segment: Identifiable {
        let id: String
        let start: Double
        let end: Double
        let progress: Double
        let colors: [Color]
    }

    private static func ratio(_ value: Double, _ target: Double?) -> Double {
        guard let target, target > 0 else { return 0 }
        return min(max(value / target, 0), 1)
    }

    private var segments: [Segment] {
        let calorieProgress = goal > 0 ? min(Double(consumed) / Double(goal), 1) : 0
        let calorieColors: [Color] = consumed > goal ? [.orange, .red] : [.mint, .green]

        // Доли макросов — по граммам целей. Без целей (профиль не заполнен)
        // поровну; совсем крошечной дуге не даём пропасть — её не разглядеть.
        let targets = [proteinTarget ?? 0, fatTarget ?? 0, carbsTarget ?? 0]
        let total = targets.reduce(0, +)
        let rawShares = total > 0 ? targets.map { $0 / total } : [1.0 / 3, 1.0 / 3, 1.0 / 3]
        let floored = rawShares.map { max($0, 0.08) }
        let shares = floored.map { $0 / floored.reduce(0, +) }

        var result = [Segment(id: "kcal", start: gap / 2, end: 180 - gap / 2,
                              progress: calorieProgress, colors: calorieColors)]
        let macroParts: [(String, Double, [Color])] = [
            ("protein", Self.ratio(macros.protein, proteinTarget), [.cyan, .blue]),
            ("fat", Self.ratio(macros.fat, fatTarget), [.yellow, .orange]),
            ("carbs", Self.ratio(macros.carbs, carbsTarget), [.pink, .purple]),
        ]
        var cursor = 180.0
        for (index, part) in macroParts.enumerated() {
            let span = 180 * shares[index]
            result.append(Segment(id: part.0, start: cursor + gap / 2, end: cursor + span - gap / 2,
                                  progress: part.1, colors: part.2))
            cursor += span
        }
        return result
    }

    var body: some View {
        ZStack {
            ForEach(segments) { segment in
                RingArc(start: segment.start, end: segment.end)
                    .stroke(.channel(thickness: lineWidth),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                if segment.progress > 0 {
                    RingArc(start: segment.start,
                            end: segment.start + (segment.end - segment.start) * segment.progress)
                        .stroke(LinearGradient(colors: segment.colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                                style: StrokeStyle(lineWidth: lineWidth - 1, lineCap: .round))
                        .glowingFill(segment.colors.last ?? .clear, thickness: lineWidth)
                }
            }
            .padding(lineWidth / 2)
            .animation(.spring(response: 0.65, dampingFraction: 0.85), value: consumed)
            .animation(.spring(response: 0.65, dampingFraction: 0.85), value: macros)

            centerLabel
                .id(consumed)
                .transition(.opacity.combined(with: .scale(scale: 0.85)))
        }
        .frame(width: size, height: size)
        // Размер кольца фиксирован, текст внутри масштабировать некуда.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .contentShape(Circle())
        .onTapGesture(perform: onOpen)
        // Своей подписи нет намеренно: VoiceOver читает содержимое кольца
        // («Остаток 2183 из 2582 ккал»), и это точнее любой общей фразы.
        // А «Добавить еду» тут ещё и совпало бы с пунктом меню на плюсе.
        .accessibilityIdentifier("addFromRing")
        .accessibilityAddTraits(.isButton)
    }

    private var centerLabel: some View {
        // Крупным идёт остаток, а не съеденное: смотрят на кольцо ради одного
        // вопроса — сколько ещё можно. Съеденное осталось, но ушло вниз: это
        // справка, а не то, ради чего сюда смотрят.
        let remaining = goal - consumed
        let overGoal = remaining < 0
        return VStack(spacing: 2) {
            Text(overGoal ? "Перебор" : "Остаток")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(overGoal ? .red : .green)
            Text("\(abs(remaining))")
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundStyle(overGoal ? Color.red : Color.primary)
                .contentTransition(.numericText())
            Text("из \(goal) ккал")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("съедено \(consumed)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .contentTransition(.numericText())
        }
    }
}

/// Дуга кольца. Углы — в градусах от 12 часов по часовой стрелке.
/// Анимируется по концу, чтобы заливка росла, а не перескакивала.
private struct RingArc: Shape {
    var start: Double
    var end: Double

    var animatableData: Double {
        get { end }
        set { end = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(center: CGPoint(x: rect.midX, y: rect.midY),
                    radius: min(rect.width, rect.height) / 2,
                    startAngle: .degrees(start - 90),
                    endAngle: .degrees(end - 90),
                    clockwise: false)
        return path
    }
}
