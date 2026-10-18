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
    /// Высота, общая для всех плиток «Сегодня».
    ///
    /// Числом, а не по содержимому: у макросов внизу тонкая полоска, у приёма
    /// и плана — строка текста, и сами собой они никогда не сойдутся. Ряды
    /// разной высоты читаются как разные вещи, хотя это один ряд плиток.
    ///
    /// Задаётся по макросам — по самой низкой, — а приём и план ужимаются под
    /// неё. Наоборот было бы проще, но тогда шесть плиток занимают пол-экрана
    /// ради двух строк текста в двух из них.
    static let height: CGFloat = 70

    let icon: String
    var tint: Color = .secondary
    /// Что это за плитка. Коротко: «Ужин», «План».
    let label: String
    /// Ради чего смотрят. Одна строка, крупно.
    let value: String
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
                    .font(.app(.headline))
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                // Место под подпись держим всегда: без неё одна плитка
                // оказывалась ниже другой, и пара переставала быть парой.
                Text(verbatim: caption ?? " ")
                    .font(.app(.caption2))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            // Высота — по содержимому, без заданного минимума: плитка
            // в девяносто две точки стояла полупустой, и пара читалась как
            // две дырки в экране. Растягиваем только до соседки, чтобы
            // квадраты остались парой, когда у одной значение в две строки.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(height: Self.height)
            .contentShape(RoundedRectangle(cornerRadius: 18))
            .liquidGlass(in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}
