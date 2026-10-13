import SwiftUI

/// Заголовок экрана как содержимое, а не как хром.
///
/// Системный инлайн-заголовок стоит мелким по центру шапки и уезжает под
/// кнопки на длинном названии — «PPL x2 Hard-Light wa…». Крупный системный
/// умеет только название и ничего больше, а экрану обычно нужна ещё строка
/// контекста: какая это неделя, какой день, какая фаза. Она лежала карточкой
/// ниже и повторяла то, что и так ясно из заголовка.
///
/// Заголовок внутри списка решает оба: название читается целиком и крупно,
/// контекст стоит над ним одной строкой, и вместе они уезжают прокруткой,
/// освобождая экран содержимому.
///
/// Тише, чем у соседнего приложения: там чёрный вес и фирменный цвет надписи
/// сверху, здесь обычный жирный и серый — у Calories язык спокойнее, и кричать
/// заголовком тут нечем.
struct ScreenTitle: View {
    let title: String
    /// Строка над названием: даты, неделя плана, день недели.
    var eyebrow: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let eyebrow {
                Text(verbatim: eyebrow.uppercased())
                    .font(.app(.caption2, weight: .semibold))
                    .kerning(0.6)
                    .foregroundStyle(.tertiary)
            }
            Text(verbatim: title)
                .font(.app(.largeTitle, weight: .bold))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
        .padding(.bottom, 2)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// «6 – 12 октября»: неделя, о которой речь. Месяц пишется один раз, когда
    /// оба конца в нём же.
    static func weekRange(from start: Date, calendar: Calendar = .current) -> String {
        let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
        let sameMonth = calendar.component(.month, from: start) == calendar.component(.month, from: end)
        let from = start.formatted(sameMonth ? .dateTime.day() : .dateTime.day().month(.wide))
        return "\(from) – \(end.formatted(.dateTime.day().month(.wide)))"
    }
}

extension View {
    /// Заголовок-строка списка: без подложки, разделителя и отступов ячейки.
    func asScreenTitleRow() -> some View {
        listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
    }
}
