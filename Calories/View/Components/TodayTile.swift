import SwiftUI

/// Плитка «Сегодня»: короткая подпись, крупное значение и строка под ним.
///
/// Полоса во всю ширину тратит её впустую: в ней три слова и стрелка, а
/// остальное — воздух. Две плитки в ряд занимают ту же высоту, что одна
/// полоса, но несут вдвое больше и читаются как два ответа на два разных
/// вопроса — «когда есть» и «куда иду», — а не как список строк.
///
/// Крупным — то, ради чего на плитку смотрят: время до приёма и неделя плана.
/// Остальное подписями, потому что подписи читают только когда заинтересовало
/// крупное.
struct TodayTile: View {
    /// Высота, общая для всех плиток «Сегодня»: приёма, плана с весом и
    /// четырёх макросов.
    ///
    /// Числом, а не по содержимому: у макросов внизу тонкая полоска, у приёма
    /// и плана — строка текста, и сами собой они никогда не сойдутся. Ряды
    /// разной высоты читаются как разные вещи, хотя это один ряд плиток —
    /// так и было: макросы стояли в 92, приём и план в 70.
    ///
    /// Задаётся по макросам: в плитке на четверть ряда четыре строки —
    /// название, число, норма и полоска, — и меньше 84 им не уместиться.
    static let height: CGFloat = 84

    let icon: String
    var tint: Color = .secondary
    /// Что это за плитка. Коротко: «Ужин», «План».
    let label: String
    /// Ради чего смотрят. Одна строка, крупно.
    let value: String
    /// Вторая строка крупного значения — между значением и подписью по размеру.
    /// Например, темп приёма под названием фазы плана.
    var value2: String? = nil
    /// Подробность под значением — её может и не быть.
    var caption: String?
    /// То же имя, что у полосы, из которой плитка выросла: по нему её ищут
    /// тесты, и терять его при смене вида нельзя.
    var identifier: String
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Image(systemName: icon)
                        .font(.app(.caption2, weight: .semibold))
                        .foregroundStyle(tint)
                    Text(verbatim: label)
                        .font(.app(.caption2))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(verbatim: value)
                    .font(.app(.subheadline, weight: .semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                // Вторая строка крупного значения — между значением и подписью
                // по размеру: например, темп под названием фазы плана.
                if let value2 {
                    Text(verbatim: value2)
                        .font(.app(.caption, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                // Подпись есть не всегда: «День закрыт» — это весь ответ,
                // добавлять к нему нечего.
                if let caption {
                    Text(verbatim: caption)
                        .font(.app(.caption2))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            // Высота у плиток общая — по макросам, в которых четыре строки, —
            // а здесь их две или три. Прижатое к верхней кромке содержимое
            // оставляло под собой пустую полосу, поэтому оно по центру: воздух
            // делится поровну сверху и снизу.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(height: Self.height)
            .contentShape(RoundedRectangle(cornerRadius: 18))
            // Стекло, собранное руками: заливка, кант и тень. Почему не
            // системное — в `TileSurface`.
            .tileSurface()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}
