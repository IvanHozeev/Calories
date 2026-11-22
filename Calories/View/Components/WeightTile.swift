import SwiftUI

/// Плитка плана на «Сегодня», которая показывает вес: шапкой — фаза плана и
/// её неделя, под ней вес со сдвигом, справа — линия за шесть недель.
///
/// Во всю ширину под кольцом: места хватает и на неделю плана, и на линию
/// покрупнее. Цели плана здесь нет — она на экране плана.
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
    /// Справа в шапке: «неделя 6 из 12». Без плана — ничего.
    var week: String? = nil
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
        //
        // В две колонки, а не в три ряда: слева шапка и вес со сдвигом в
        // одну строку, справа линия. Высота — по более высокой из
        // колонок, а не сумма рядов: в рядах плитка выходила почти вдвое
        // выше макросов над ней.
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                header
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    weightLine
                    if offersWeighIn {
                        Button(action: onWeighIn) { weighInLabel }
                            .buttonStyle(.plain)
                            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                            .accessibilityIdentifier("weightTileWeighIn")
                    } else if let changeText {
                        Text(verbatim: changeText)
                            .font(.app(.caption))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            }
            Spacer(minLength: 0)
            if series.count > 1 {
                sparkline
                    .frame(width: 112, height: 32)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .tileSurface()
        .onTapGesture(perform: onOpen)
        .accessibilityElement(children: .contain)
    }

    /// Шапка: значок и название фазы, за ними неделя плана.
    private var header: some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.app(.caption, weight: .bold))
                    .foregroundStyle(symbolTint)
            }
            Text(verbatim: title)
                .font(.app(.caption, weight: .semibold))
                .foregroundStyle(.secondary)
            if let week {
                Text(verbatim: "· \(week)")
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, onOpen)
        .accessibilityIdentifier("weightTile")
    }

    private var weightLine: some View {
        Group {
            if let trendKg {
                Text(verbatim: "\(mass(trendKg)) \(unit)")
            } else {
                Text(verbatim: "—")
            }
        }
        .font(.app(.title3, weight: .bold))
        .monospacedDigit()
        .lineLimit(1)
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
                .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                if let last = points.last {
                    Circle()
                        .fill(Color(.systemBackground))
                        .overlay(Circle().stroke(offersWeighIn ? Color.secondary : color,
                                                 style: StrokeStyle(lineWidth: 2, dash: offersWeighIn ? [2, 2] : [])))
                        .frame(width: 9, height: 9)
                        .position(last)
                }
            }
        }
        .accessibilityHidden(true)
    }
}
