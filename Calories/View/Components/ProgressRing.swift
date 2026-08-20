import SwiftUI

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
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.15), lineWidth: 18)

            Circle()
                .trim(from: 0, to: ringProgress)
                .stroke(
                    LinearGradient(
                        colors: ringColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 18, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.65, dampingFraction: 0.85), value: ringProgress)

            centerLabel
                .id(mode)
                .transition(.opacity.combined(with: .scale(scale: 0.85)))
        }
        .frame(width: 220, height: 220)
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
            Text(name)
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
