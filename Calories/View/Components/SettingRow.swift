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
