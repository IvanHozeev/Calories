import SwiftUI

/// Строка расчёта: подпись слева, значение справа.
///
/// Была трижды скопирована — в плане, в редакторе плана и в профиле, — и
/// разошлась ровно настолько, чтобы это мешало: в одном месте параметры
/// назывались по-разному. Главное в ней не вёрстка, а правило выделения:
/// подсвеченная строка — это итог, к которому человек шёл, и он зелёный и
/// плотнее по начертанию, а остальные строки тише подписи.
struct ResultRow: View {
    let title: LocalizedStringKey
    let value: String
    var highlighted = false
    /// Уточнение под числом: отклонение от плана, коридор дат, погрешность.
    ///
    /// Раньше каждое такое уточнение было отдельной строкой, и экран плана
    /// превращался в таблицу из семи чисел, где главное тонуло среди
    /// производного. Под своим числом оно читается как его часть и места
    /// занимает вдвое меньше.
    var caption: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(highlighted ? .primary : .secondary)
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(value)
                    .font(highlighted ? .body.weight(.semibold) : .body)
                    .foregroundStyle(highlighted ? .green : .primary)
                if let caption {
                    Text(verbatim: caption)
                        .font(.app(.caption2))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}
