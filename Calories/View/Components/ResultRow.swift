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

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(highlighted ? .primary : .secondary)
            Spacer()
            Text(value)
                .font(highlighted ? .body.weight(.semibold) : .body)
                .foregroundStyle(highlighted ? .green : .primary)
        }
    }
}
