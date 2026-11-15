import SwiftUI

/// Карточка тела в «Профиле»: вес, жир, сухая масса и тренд веса за полтора
/// месяца.
///
/// Сверху профиля стоит подписка, а за ней сразу параметры — числа, которые
/// правят. Но заходят в профиль и посмотреть, как идёт тело, и для этого
/// нужны три числа и направление, а не три строки списка с колёсами. Карточка
/// только показывает: править по-прежнему в параметрах ниже.
struct BodySnapshotCard: View {
    let weightKg: Double?
    let fatPercent: Double?
    let leanKg: Double?
    /// Тренд веса от давнего к свежему, кг.
    let trend: [Double]
    let weeks: Int
    /// Фунты вместо килограммов — как в настройках единиц.
    var imperial: Bool = false

    private static let poundsPerKilogram = 2.20462

    private func mass(_ kg: Double?) -> String {
        guard let kg else { return "—" }
        return String(format: "%.1f", imperial ? kg * Self.poundsPerKilogram : kg)
    }

    private var massUnit: String { String(localized: imperial ? "фунт" : "кг") }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 8) {
                metric("Вес", mass(weightKg), unit: massUnit)
                metric("Жир", fatPercent.map { String(format: "%.1f", $0) } ?? "—", unit: "%")
                metric("Сухая масса", mass(leanKg), unit: massUnit)
            }

            if TrendSparkline.heights(trend).count >= TrendSparkline.minimumPoints {
                sparkline
                if let change = TrendSparkline.change(trend) {
                    // «−3,1 кг» одной подстановкой: единица языко-зависима, и
                    // вставлять её отдельным словом в переводимую фразу нельзя.
                    let changeText = "\(String(format: "%+.1f", imperial ? change * Self.poundsPerKilogram : change)) \(massUnit)"
                    Text("\(changeText) за \(weeks) нед.")
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tileSurface(cornerRadius: 20)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("bodySnapshot")
    }

    private func metric(_ title: LocalizedStringKey, _ value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.app(.caption))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(verbatim: value)
                    .font(.app(.title2, weight: .bold))
                    .monospacedDigit()
                Text(verbatim: unit)
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Линия тренда цветом калорий, последняя точка — кружком.
    private var sparkline: some View {
        let heights = TrendSparkline.heights(trend)
        return GeometryReader { geometry in
            let inset: CGFloat = 5
            let width = geometry.size.width - inset * 2
            let height = geometry.size.height - inset * 2
            let points = heights.enumerated().map { index, level in
                CGPoint(x: inset + width * CGFloat(index) / CGFloat(max(heights.count - 1, 1)),
                        y: inset + height * (1 - CGFloat(level)))
            }
            ZStack {
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    points.dropFirst().forEach { path.addLine(to: $0) }
                }
                .stroke(ProgressRing.kcalColors[0],
                        style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                if let last = points.last {
                    Circle()
                        .fill(Color(.systemBackground))
                        .overlay(Circle().stroke(ProgressRing.kcalColors[0], lineWidth: 3))
                        .frame(width: 10, height: 10)
                        .position(last)
                }
            }
        }
        .frame(height: 44)
        .accessibilityHidden(true)
    }
}
