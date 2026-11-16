import SwiftUI

/// Подсказка под кольцом: стеклянная плашка, которая отвечает пальцу.
///
/// Раньше подсказку убирали смахиванием влево. Жест был невидимым: о нём
/// надо было знать заранее, и его путали с прокруткой. Теперь справа крестик,
/// как у баннеров в системных приложениях и мессенджерах, а смахивания нет.
///
/// Пока палец держит плашку, она пружиной подрастает и коротко отзывается
/// вибрацией, а отпущенная возвращается и выполняет своё действие. Так видно,
/// что плашка живая, ещё до того, как что-то открылось. Подсказка без
/// действия («норма набрана») тоже подрастает: её можно закрыть, и отклик
/// говорит, что палец до неё дотянулся.
struct HintCard<Content: View>: View {
    var onTap: (() -> Void)?
    var onClose: (() -> Void)?
    /// Имя для тестов и VoiceOver: у каждой подсказки своё.
    var identifier: String = "hintCard"
    @ViewBuilder var content: Content

    @State private var pressed = false

    /// Насколько подрастает плашка под пальцем. Четыре процента заметны, но
    /// не наезжают на соседей: между подсказками шестнадцать точек.
    static var pressedScale: CGFloat { 1.04 }

    var body: some View {
        // Крестик — соседом плашки по строке, а не слоем поверх неё.
        // Распознаватель нажатия ловит касания во всей своей рамке, и
        // крестик поверх плашки до касания не доходил: оно проваливалось в
        // строку списка и открывало разбор дня.
        HStack(alignment: .top, spacing: 0) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 14)
                .padding(.trailing, onClose == nil ? 14 : 4)
                .padding(.vertical, 7)
                .frame(maxHeight: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                // Нажатие ловит системный распознаватель, а не жест SwiftUI.
                // Жест с нулевым порогом забирал касание у списка, и
                // прокрутка, начатая с подсказки, не шла. Этот работает
                // вместе с прокруткой: пока палец стоит, плашка подросла;
                // отпустил на месте — действие, хоть сразу, хоть после долгого
                // удержания; уехал — это была прокрутка, и ничего не
                // открывается.
                .gesture(HintPressGesture(onPressChanged: { pressed = $0 },
                                          onRelease: { onTap?() }))
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(onTap == nil ? [] : .isButton)
                .accessibilityAction { onTap?() }
                .accessibilityIdentifier(identifier)

            if let onClose {
                // Столбик во всю высоту плашки: касание у правого края,
                // выше или ниже значка, тоже закрывает, а не проваливается.
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.app(.caption, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 40, height: 32)
                        .frame(maxHeight: .infinity, alignment: .center)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Скрыть до завтра"))
                .accessibilityIdentifier("hintClose")
            }
        }
        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .tileSurface(cornerRadius: 18)
        .scaleEffect(pressed ? Self.pressedScale : 1)
        .animation(.spring(response: 0.32, dampingFraction: 0.58), value: pressed)
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.6), trigger: pressed) { _, isPressed in
            isPressed
        }
    }
}

/// Нажатие, которое не мешает прокрутке.
///
/// Распознаватель удержания с нулевой задержкой начинается сразу при касании,
/// а позволение работать одновременно с другими оставляет списку его
/// прокрутку. Сдвиг меряется в координатах окна: при прокрутке содержимое
/// едет вместе с пальцем, и в своих координатах палец бы «стоял на месте».
struct HintPressGesture: UIGestureRecognizerRepresentable {
    var onPressChanged: (Bool) -> Void
    var onRelease: () -> Void

    /// Дальше этого палец уже прокручивает, а не нажимает.
    static var slop: CGFloat { 10 }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()
        recognizer.minimumPressDuration = 0
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        let coordinator = context.coordinator
        let point = recognizer.location(in: nil)
        switch recognizer.state {
        case .began:
            coordinator.start = point
            coordinator.moved = false
            onPressChanged(true)
        case .changed:
            guard !coordinator.moved, let start = coordinator.start else { return }
            if hypot(point.x - start.x, point.y - start.y) > Self.slop {
                coordinator.moved = true
                onPressChanged(false)
            }
        case .ended:
            onPressChanged(false)
            if !coordinator.moved { onRelease() }
            coordinator.start = nil
        case .cancelled, .failed:
            onPressChanged(false)
            coordinator.start = nil
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var start: CGPoint?
        var moved = false

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
