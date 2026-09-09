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

/// Кольцо калорий за день. Нажатие открывает добавление приёма пищи.
///
/// Раньше кольцо переключалось по нажатию между калориями и тремя макросами.
/// Пользы в этом не было: те же белки, жиры и углеводы стоят на карточке прямо
/// под кольцом, с целями и без единого нажатия, — а кольцо тем временем занимало
/// собой самый заметный жест экрана под то, что и так на виду.
///
/// Теперь оно ведёт туда, куда чаще всего и надо. Еду записывают по нескольку
/// раз в день, а на план смотрят раз в неделю: самая крупная мишень экрана
/// должна обслуживать частое действие, а не редкое. И на «остаток 2183»
/// естественный ответ — записать съеденное, а не открыть план; план открывается
/// строкой под кольцом, где он и подписан.
///
/// Ведёт сразу в добавление, а не в меню: меню со сканером и камерой живёт
/// на плюсе в тулбаре, а кольцо даёт самый короткий путь к самому частому.
struct ProgressRing: View {
    let consumed: Int
    let goal: Int
    /// Что делать по нажатию — записать еду.
    let onOpen: () -> Void

    private var progress: Double {
        guard goal > 0 else { return 0 }
        return min(Double(consumed) / Double(goal), 1.0)
    }

    private var colors: [Color] {
        consumed > goal ? [.orange, .red] : [.green, .mint]
    }

    var body: some View {
        RingView(progress: progress, colors: colors, labelID: consumed) {
            centerLabel
        }
        .contentShape(Circle())
        .onTapGesture(perform: onOpen)
        // Своей подписи нет намеренно: VoiceOver читает содержимое кольца
        // («Остаток 2183 из 2582 ккал»), и это точнее любой общей фразы.
        // А «Добавить еду» тут ещё и совпало бы с пунктом меню на плюсе —
        // и то, и другое стало бы не найти по имени.
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
