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
    /// Когда сняты замеры, из которых считаются жир и сухая масса.
    var measuredOn: Date? = nil
    /// Вес — на экран взвешиваний, жир и сухая масса — на замеры. Плитки
    /// нажимаются: смотреть на число и не мочь его поправить было бы странно.
    var onOpenWeight: () -> Void = {}
    var onOpenBody: () -> Void = {}

    private static let poundsPerKilogram = 2.20462

    private func mass(_ kg: Double?) -> String {
        guard let kg else { return "—" }
        return String(format: "%.1f", imperial ? kg * Self.poundsPerKilogram : kg)
    }

    private var massUnit: String { String(localized: imperial ? "фунт" : "кг") }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 8) {
                metric("Вес", mass(weightKg), unit: massUnit, action: onOpenWeight)
                    .accessibilityIdentifier("openWeight")
                metric("Жир", fatPercent.map { String(format: "%.1f", $0) } ?? "—", unit: "%",
                       action: onOpenBody)
                    .accessibilityIdentifier("openBodyFat")
                metric("Сухая масса", mass(leanKg), unit: massUnit, action: onOpenBody)
                    .accessibilityIdentifier("openLeanMass")
            }

            if TrendSparkline.heights(trend).count >= TrendSparkline.minimumPoints {
                sparkline
            }

            // Подпись под графиком: слева — изменение, справа — когда сняты
            // замеры. Без графика подпись всё равно нужна: по ней видно,
            // свежие ли числа жира и сухой массы.
            HStack {
                if TrendSparkline.heights(trend).count >= TrendSparkline.minimumPoints,
                   let change = TrendSparkline.change(trend) {
                    // «−3,1 кг» одной подстановкой: единица языко-зависима, и
                    // вставлять её отдельным словом в переводимую фразу нельзя.
                    let changeText = "\(String(format: "%+.1f", imperial ? change * Self.poundsPerKilogram : change)) \(massUnit)"
                    Text("\(changeText) за \(weeks) нед.")
                }
                Spacer(minLength: 8)
                if let measuredOn {
                    Text(String(format: String(localized: "замеры %@"),
                                measuredOn.formatted(.dateTime.day().month(.wide))))
                }
            }
            .font(.app(.caption))
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tileSurface(cornerRadius: 20)
    }

    private func metric(_ title: LocalizedStringKey, _ value: String, unit: String,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.app(.caption))
                .foregroundStyle(Color.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(verbatim: value)
                    .font(.app(.title2, weight: .bold))
                    .foregroundStyle(Color.primary)
                    .monospacedDigit()
                Text(verbatim: unit)
                    .font(.app(.caption))
                    .foregroundStyle(Color.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
        .contentShape(Rectangle())
        }
        // Системный стиль без обводки, а не `.plain`: три кнопки в одной
        // строке списка с `.plain` отдают тап строке целиком, и нажималась
        // сразу вся тройка. Подписи красим явно — этот стиль красит акцентом.
        .buttonStyle(.borderless)
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
