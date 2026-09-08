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

struct ProgressRing: View {
    let consumed: Int
    let goal: Int
    let macros: Macros
    let proteinTarget: Double?
    let fatTarget: Double?
    let carbsTarget: Double

    @State private var mode: Mode = .calories

    private enum Mode: CaseIterable {
        case calories, protein, fat, carbs
    }

    private var ringProgress: Double {
        switch mode {
        case .calories:
            guard goal > 0 else { return 0 }
            return min(Double(consumed) / Double(goal), 1.0)
        case .protein:
            guard let t = proteinTarget, t > 0 else { return 0 }
            return min(macros.protein / t, 1.0)
        case .fat:
            guard let t = fatTarget, t > 0 else { return 0 }
            return min(macros.fat / t, 1.0)
        case .carbs:
            guard carbsTarget > 0 else { return 0 }
            return min(macros.carbs / carbsTarget, 1.0)
        }
    }

    private var ringColors: [Color] {
        switch mode {
        case .calories: return consumed > goal ? [.orange, .red] : [.green, .mint]
        case .protein:  return [.blue, .blue.opacity(0.6)]
        case .fat:      return [.orange, .orange.opacity(0.6)]
        case .carbs:    return [.purple, .purple.opacity(0.6)]
        }
    }

    var body: some View {
        RingView(progress: ringProgress, colors: ringColors, labelID: mode) {
            centerLabel
        }
        .onTapGesture {
            let all = Mode.allCases
            let next = all[(all.firstIndex(of: mode)! + 1) % all.count]
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                mode = next
            }
        }
    }

    @ViewBuilder
    private var centerLabel: some View {
        switch mode {
        case .calories:
            let remaining = goal - consumed
            VStack(spacing: 2) {
                Text("\(consumed)")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Text("из \(goal) ккал")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(remaining >= 0 ? "\(remaining) осталось" : "перебор \(-remaining)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(remaining >= 0 ? .green : .red)
                    .contentTransition(.numericText())
            }
        case .protein:
            macroCenter("Белок", value: macros.protein, target: proteinTarget, color: .blue)
        case .fat:
            macroCenter("Жиры", value: macros.fat, target: fatTarget, color: .orange)
        case .carbs:
            macroCenter("Углеводы", value: macros.carbs, target: carbsTarget > 0 ? carbsTarget : nil, color: .purple)
        }
    }

    private func macroCenter(_ name: String, value: Double, target: Double?, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(LocalizedStringKey(name))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(color)
            Text("\(Int(value)) г")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
            Text(target.map { "из \(Int($0)) г" } ?? "нет цели")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
