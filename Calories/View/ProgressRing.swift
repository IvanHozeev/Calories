import SwiftUI

struct ProgressRing: View {
    let progress: Double
    let consumed: Int
    let goal: Int

    private var overGoal: Bool { consumed > goal }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.15), lineWidth: 18)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(
                        colors: overGoal ? [.orange, .red] : [.green, .mint],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 18, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.5), value: progress)

            VStack(spacing: 4) {
                Text("\(consumed)")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text("из \(goal) ккал")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 220, height: 220)
    }
}
