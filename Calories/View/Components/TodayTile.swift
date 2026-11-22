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
    /// Высота плиток приёма и плана с весом.
    ///
    /// Числом, а не по содержимому: у приёма три строки, у веса — строки и
    /// линия, и сами собой две соседки не сойдутся.
    ///
    /// Не вровень с макросами (`MacrosCard.narrowTileHeight`, 84): у макросов
    /// четыре строки, и в их высоте у приёма и плана внизу оставалось
    /// пустое место. Ряды разной высоты — меньшее из зол.
    static let height: CGFloat = 70

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
            // По центру: строк бывает две или три, и прижатые к верхней
            // кромке они оставляли бы под собой пустую полосу.
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
