import SwiftUI

/// Плитка плана на «Сегодня», которая показывает вес: шапкой — фаза плана,
/// крупно — вес.
///
/// Плитка плана говорила о темпе веса словами, а сам вес лежал в профиле.
/// Теперь вес перед глазами: по тренду, линией за шесть недель и сдвигом за
/// неделю — фактом, без сравнения с планом. Жира и сухой массы здесь нет: они
/// меняются раз в неделю-две и занимали бы место впустую; они в профиле.
///
/// Не взвешивался сегодня, а утро ещё идёт — вместо сдвига кнопка
/// «Взвеситься»: отдельная подсказка под кольцом для этого больше не нужна.
struct WeightTile: View {
    /// Шапка плитки: фаза плана («Сушка»), а без плана — «Вес».
    let title: String
    /// Значок фазы перед её названием. Без плана — ничего: значок «весов»
    /// ничего не добавлял к слову «Вес».
    var symbol: String? = nil
    var symbolTint: Color = .secondary
    /// Вес по тренду. nil — взвешиваний ещё нет.
    let trendKg: Double?
    /// Сдвиг тренда за неделю, в процентах от веса. nil — истории меньше недели.
    let weeklyChangePercent: Double?
    /// Тренд за шесть недель, от давнего к свежему.
    let series: [Double]
    /// Показать «Взвеситься» вместо сдвига.
    let offersWeighIn: Bool
    var imperial: Bool = false
    var onOpen: () -> Void
    var onWeighIn: () -> Void

    private static let poundsPerKilogram = 2.20462

    private func mass(_ kg: Double) -> String {
        String(format: "%.1f", imperial ? kg * Self.poundsPerKilogram : kg)
    }

    private var unit: String { String(localized: imperial ? "фунт" : "кг") }

    /// Сдвиг в процентах от веса, а не в килограммах: темп плана задан так
    /// же («мягкий — 0,5 % в неделю»), и «−0,6 %» сразу читается против
    /// выбранного темпа, а «−0,48 кг» — только как факт. Килограммы рядом
    /// были бы лишними: сам вес и так стоит крупно.
    private var changeText: String? {
        guard let change = weeklyChangePercent else { return nil }
        return String(format: String(localized: "%@ в неделю"), String(format: "%+.1f%%", change))
    }

    var body: some View {
        // Плитка — не кнопка, а жест: внутри неё своя кнопка «Взвеситься», а
        // вложенная в кнопку кнопка тап не получает — его забирает внешняя.
        // Раньше «Взвеситься» поэтому лежала поверх плитки, прижатой к низу,
        // и не вставала по центру вместе с остальным.
        VStack(alignment: .leading, spacing: 2) {
            info
            if offersWeighIn {
                Button(action: onWeighIn) { weighInLabel }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("weightTileWeighIn")
            }
        }
        // По центру, как плитка приёма рядом.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        // Поуже, чем у плитки приёма: с кнопкой «Взвеситься» здесь три
        // строки и линия, и в 70 точек с прежними полями они не влезали.
        .padding(.vertical, 6)
        .frame(height: TodayTile.height)
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .tileSurface()
        .onTapGesture(perform: onOpen)
    }

    /// Шапка, вес с линией и сдвиг — одним элементом для VoiceOver, кнопкой,
    /// которая открывает план или экран веса.
    private var info: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.app(.caption2, weight: .bold))
                        .foregroundStyle(symbolTint)
                }
                Text(verbatim: title)
                    .font(.app(.caption2, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            HStack(alignment: .center, spacing: 8) {
                if let trendKg {
                    Text(verbatim: "\(mass(trendKg)) \(unit)")
                        .font(.app(.subheadline, weight: .semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                } else {
                    Text(verbatim: "—")
                        .font(.app(.subheadline, weight: .semibold))
                }
                Spacer(minLength: 0)
                if series.count > 1 {
                    sparkline
                        .frame(width: 56, height: 22)
                }
            }

            if !offersWeighIn, let changeText {
                Text(verbatim: changeText)
                    .font(.app(.caption2))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, onOpen)
        .accessibilityIdentifier("weightTile")
    }

    private var weighInLabel: some View {
        Label("Взвеситься", systemImage: "plus")
            .font(.app(.caption2, weight: .semibold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(.tint)
            .padding(.horizontal, 9)
            .frame(height: 18)
            .background(Color.accentColor.opacity(0.12), in: Capsule())
            .contentShape(Capsule())
    }

    /// Тренд линией, свежая точка — кружком. Пока сегодня не взвешивался,
    /// кружок пустой: сегодняшнего взвешивания на линии ещё нет.
    private var sparkline: some View {
        let heights = TrendSparkline.heights(series)
        let color = ProgressRing.kcalColors[0]
        return GeometryReader { geometry in
            let inset: CGFloat = 3
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
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                if let last = points.last {
                    Circle()
                        .fill(Color(.systemBackground))
                        .overlay(Circle().stroke(offersWeighIn ? Color.secondary : color,
                                                 style: StrokeStyle(lineWidth: 2, dash: offersWeighIn ? [2, 2] : [])))
                        .frame(width: 7, height: 7)
                        .position(last)
                }
            }
        }
        .accessibilityHidden(true)
    }
}
