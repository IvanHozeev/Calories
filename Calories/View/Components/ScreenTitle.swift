import SwiftUI

/// Заголовок экрана: название и строка контекста над ним.
///
/// Системный инлайн-заголовок стоит мелким по центру шапки и умеет только
/// название. А экрану обычно нужна ещё строка: какая это неделя, какой день,
/// какая фаза. Она лежала карточкой ниже и повторяла то, что и так ясно из
/// заголовка.
///
/// Живёт в шапке, в слоте `principal`. Слот — это уже промежуток между
/// кнопками: он начинается после «назад» и кончается перед теми, что справа.
/// Но своей ширины он не предлагает и центрует всё, что уже него. Поэтому
/// заголовку выдаётся ровно ширина промежутка и велено стоять у его левого
/// края — см. `inBar`.
///
/// Тише, чем у соседнего приложения: там чёрный вес и фирменный цвет надписи
/// сверху, здесь обычный жирный — у Calories язык спокойнее, и кричать
/// заголовком тут нечем.
struct ScreenTitle: View {
    let title: String
    /// Строка над названием: даты, неделя плана, день недели.
    var eyebrow: String? = nil
    /// Строка под названием — там, где название общее, а уточнение частное:
    /// «Сегодня» и какое именно сегодня.
    var subtitle: String? = nil
    /// В шапке, а не в содержимом: две плотные строки в сорок четыре точки.
    /// Перестаёт быть крупным — и взамен перестаёт уезжать прокруткой.
    var isCompact = false
    /// Сколько строк отдать названию в шапке. Две, помельче, — тем, что иначе
    /// приедут туда многоточием.
    var compactLines = 1
    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 0 : 2) {
            if let eyebrow {
                Text(verbatim: eyebrow.uppercased())
                    .font(.app(.caption2, weight: .semibold))
                    .kerning(0.6)
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(1)
            }
            Text(verbatim: title)
                .font(.app(isCompact ? (compactLines > 1 ? .subheadline : .title3) : .largeTitle,
                           weight: .bold))
                .lineLimit(isCompact ? compactLines : 2)
                .minimumScaleFactor(0.7)
            if let subtitle {
                Text(verbatim: subtitle)
                    .font(.app(.caption2))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // В шапке — отступ от кнопки «назад»: слот начинается сразу за ней,
        // и заголовок прилипал к шеврону вплотную.
        .padding(.leading, isCompact ? 10 : 0)
        .padding(.top, isCompact ? 0 : 4)
        .padding(.bottom, isCompact ? 0 : 2)
        .accessibilityElement(children: .combine)
        // Именем панели становится имя того, что в ней стоит. Собранная из двух
        // строк подпись делала панель «13 ОКТЯБРЯ, РАЗБОР ДНЯ» — найти шапку по
        // названию экрана после этого было нечем, ни тесту, ни человеку.
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityValue(Text(verbatim: eyebrow ?? subtitle ?? ""))
        .accessibilityAddTraits(.isHeader)
    }

    /// Ширина промежутка между кнопками шапки — та, которую заголовок забирает
    /// себе, чтобы встать у его левого края, а не по центру.
    ///
    /// Отдельный отступ под «назад» сверх этого — ровно то, что отодвигало
    /// каждый заголовок вправо: слот и так начинается после кнопки. А взять всю
    /// панель целиком — наоборот, увести его за левый край.
    func inBar(back: Bool = true, trailingButtons: Int = 0) -> some View {
        let width = UIScreen.main.bounds.width - 48
            - (back ? 44 : 0)
            - CGFloat(trailingButtons) * 46
        return frame(width: max(120, width), alignment: .leading)
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

    /// Заголовок экрана в шапке: название и строка контекста над ним.
    ///
    /// Системный заголовок при этом прячется — два заголовка в одной шапке
    /// спорят за одно место, и побеждает не тот, что нужен.
    func screenTitle(_ title: String,
                     eyebrow: String? = nil,
                     lines: Int = 1,
                     backButton: Bool = true,
                     trailingButtons: Int = 0) -> some View {
        navigationTitle(title)
            .hiddenNavigationTitle()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    ScreenTitle(title: title, eyebrow: eyebrow,
                                isCompact: true, compactLines: lines)
                        .inBar(back: backButton, trailingButtons: trailingButtons)
                }
            }
    }
}
