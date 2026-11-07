import SwiftUI

/// Тап ловится всей строкой, а не только её содержимым.
///
/// `.buttonStyle(.plain)` в списке ловит тап только по своему содержимому —
/// тап по пустой части строки уходит в никуда. Этот модификатор чинит это:
/// `.contentShape(Rectangle())` делает всю строку попадаемой, а
/// `.onTapGesture` вешает на неё действие.
///
/// Использовать вместо пары `.contentShape(Rectangle())` +
/// `.onTapGesture { ... }`.
extension View {
    func tappableRow(_ action: @escaping () -> Void) -> some View {
        self.contentShape(Rectangle())
            .onTapGesture { action() }
    }
}
