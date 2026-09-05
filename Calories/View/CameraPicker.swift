import SwiftUI
import UIKit

/// Съёмка фотографии. SwiftUI своего снимающего экрана не даёт, поэтому
/// оборачиваем UIKit — задача ровно на один экран, свой городить незачем.
struct CameraPicker: UIViewControllerRepresentable {
    var onCaptured: (Data) -> Void

    @Environment(\.dismiss) private var dismiss

    /// На симуляторе камеры нет, и кнопку съёмки там показывать не надо —
    /// иначе она открывает пустой чёрный экран и выглядит поломкой.
    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: CameraPicker

        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            // Сжимаем перед отправкой: снимок с камеры весит мегабайты, а модели
            // хватает и меньшего — иначе разбор в кафе с плохой сетью не дождаться.
            if let image = info[.originalImage] as? UIImage,
               let data = image.jpegData(compressionQuality: 0.7) {
                parent.onCaptured(data)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
