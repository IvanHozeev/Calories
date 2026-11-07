import SwiftUI

/// Строка-настройка: знак акцентом, текст обычным цветом.
///
/// Один способ на все экраны, и это не придирка к единообразию. Знак,
/// поставленный вручную в `HStack`, не попадает в ту колонку, которую список
/// отводит значкам `Label`, — и строки разъезжаются на пару точек. Глазу этого
/// хватает: секция выглядит так, будто её собирали в два захода.
///
/// Поэтому даже строки со своим содержимым справа — весом, трендом, датой —
/// собираются как `Label` с содержимым в подписи, а не как `HStack` со значком
/// первым элементом.
func settingLabel(_ title: LocalizedStringKey, systemImage: String) -> some View {
    Label {
        Text(title).foregroundStyle(Color.primary)
    } icon: {
        Image(systemName: systemImage).foregroundStyle(.tint)
    }
}

/// То же, но с произвольным содержимым вместо простой подписи: строка веса
/// несёт тренд и число, строка замеров — дату.
func settingLabel<Content: View>(systemImage: String,
                                 @ViewBuilder content: () -> Content) -> some View {
    Label {
        content()
    } icon: {
        Image(systemName: systemImage).foregroundStyle(.tint)
    }
}

/// Строка-настройка со знаком-буквой вместо символа системы.
///
/// Нужна там, где подходящего символа у системы нет: знаки пола, например,
/// среди них отсутствуют, а «♂» и «♀» понятны без перевода.
func settingLabel(_ title: LocalizedStringKey, glyph: String) -> some View {
    Label {
        Text(title).foregroundStyle(Color.primary)
    } icon: {
        SettingGlyph(glyph: glyph)
    }
}

/// Знак-буква в колонке значков.
///
/// Буква там ведёт себя не как символ системы, и поставить её «как есть» не
/// выходит: символ рисуется заметно крупнее текста вокруг и выравнивается по
/// своей середине, а буква набирается в размер текста и садится на базовую
/// линию. В строке это видно сразу — знак мелкий и стоит ниже соседних.
///
/// Поэтому буква набирается крупнее подписи и ставится в квадрат той же
/// высоты, какую занимает символ: тогда она попадает и в колонку значков, и
/// в линию с остальными. Размер привязан к размеру текста — на крупном
/// шрифте знак растёт вместе со строкой.
private struct SettingGlyph: View {
    let glyph: String
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 22

    var body: some View {
        Text(verbatim: glyph)
            .font(.app(size: side))
            .foregroundStyle(.tint)
            .frame(width: side, height: side)
    }
}
