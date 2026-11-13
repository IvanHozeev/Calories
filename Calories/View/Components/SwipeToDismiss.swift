import SwiftUI

/// Смахивание влево, чтобы убрать подсказку.
///
/// Системный свайп строки здесь недоступен: подсказка живёт внутри общего
/// блока первого экрана, а не своей строкой списка. Поэтому жест свой, но
/// ведёт себя как системный: строка едет за пальцем влево, а отпущенная
/// дальше трети ширины улетает; ближе — возвращается на место.
///
/// Ловим только горизонтальное движение: вертикальное принадлежит прокрутке
/// экрана, и подсказка не должна мешать листать.
struct SwipeToDismiss<Content: View>: View {
    var onDismiss: () -> Void
    @ViewBuilder var content: Content

    @State private var offset: CGFloat = 0
    @State private var width: CGFloat = 320

    var body: some View {
        content
            .offset(x: offset)
            .opacity(1 - min(0.6, Double(-offset / max(width, 1))))
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .simultaneousGesture(
                DragGesture(minimumDistance: 16)
                    .onChanged { value in
                        // Только влево и только когда жест горизонтальный.
                        guard abs(value.translation.width) > abs(value.translation.height),
                              value.translation.width < 0 else { return }
                        offset = value.translation.width
                    }
                    .onEnded { value in
                        let horizontal = abs(value.translation.width) > abs(value.translation.height)
                        if horizontal, value.predictedEndTranslation.width < -width / 3 {
                            withAnimation(.snappy) { offset = -width }
                            onDismiss()
                        } else {
                            withAnimation(.snappy) { offset = 0 }
                        }
                    }
            )
            .accessibilityAction(named: Text("Скрыть до завтра"), onDismiss)
    }
}
