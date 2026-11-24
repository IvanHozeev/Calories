import SwiftUI

/// Одна капсула с тем же тонким объёмом, что у дуг кольца дня (`RubberArcs`): почти ровный
/// цвет, блик по верху, тонкий тёмный борт снизу вместо толщины и короткая мягкая тень.
///
/// Всё в долях высоты, поэтому капсула любой высоты остаётся тем же предметом. Цвет — цвет
/// макроса, один и тот же на дуге, на полоске и в названии продукта.
struct RubberCapsule: View {
    let color: Color
    var height: CGFloat = 6

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack(alignment: .top) {
            // Борт: та же капсула темнее и чуть ниже — толщина.
            Capsule().fill(color.mix(with: .black, by: 0.30))
                .offset(y: height * 0.14)
            Capsule().fill(LinearGradient(
                colors: [color.mix(with: .white, by: 0.14), color, color.mix(with: .black, by: 0.06)],
                startPoint: .top, endPoint: .bottom))
            // Блик по верху, мягкий.
            Capsule().fill(.white.opacity(0.38))
                .frame(height: height * 0.28)
                .padding(.horizontal, height * 0.3)
                .padding(.top, height * 0.12)
                .blur(radius: height * 0.08)
        }
        .frame(height: height)
        .shadow(color: scheme == .dark ? .black.opacity(0.5) : Color(red: 70 / 255, green: 55 / 255, blue: 40 / 255).opacity(0.25),
                radius: height * 0.3, x: 0, y: height * 0.35)
    }
}

/// Полоска прогресса из такой капсулы на плоской бледной дорожке.
struct RubberBar: View {
    let color: Color
    /// Доля заливки, 0…1.
    let progress: Double
    var height: CGFloat = 6
    var trackOpacity: Double = 0.18

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let fill = max(width * min(max(progress, 0), 1), height)
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(trackOpacity))
                if progress > 0 {
                    RubberCapsule(color: color, height: height)
                        .frame(width: fill)
                        .animation(.spring(response: 0.65, dampingFraction: 0.85), value: progress)
                }
            }
        }
        .frame(height: height)
    }
}
