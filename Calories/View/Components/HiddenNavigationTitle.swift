import SwiftUI

extension View {
    /// Заголовок есть, но не виден: на корневых вкладках название и так
    /// написано в таббаре, а строка над кольцом только отнимала место.
    ///
    /// Сам `navigationTitle` остаётся — он подписывает кнопку «назад» на
    /// вложенных экранах и читается VoiceOver.
    func hiddenNavigationTitle() -> some View {
        toolbar {
            ToolbarItem(placement: .principal) {
                Color.clear.frame(width: 1, height: 1)
                    .accessibilityHidden(true)
            }
        }
    }
}

extension ToolbarContent {
    /// Элемент тулбара без стеклянной подложки, которую iOS 26 рисует под
    /// кнопками. На ранних системах подложки нет, и менять нечего.
    @ToolbarContentBuilder
    func withoutSharedBackground() -> some ToolbarContent {
        if #available(iOS 26, *) {
            sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}
