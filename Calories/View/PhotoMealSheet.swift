import SwiftUI
import PhotosUI

/// Съёмка тарелки и разбор её моделью.
///
/// Результат намеренно уходит в обычный черновик приёма пищи, а не на свой
/// экран подтверждения: распознанное — это заготовка, которую правят теми же
/// движениями, что и введённое руками. Отдельный экран заставлял бы учить
/// второй способ делать то же самое.
struct PhotoMealSheet: View {
    /// Отдаём наверх то, что распознали. Решение, что с этим делать, принимает
    /// экран приёма пищи — здесь мы только смотрим на фото.
    var onRecognized: ([MealItem]) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var pickerItem: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var isRecognizing = false
    @State private var showingCamera = false
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let imageData, let image = UIImage(data: imageData) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 260)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .listRowInsets(EdgeInsets())
                    } else {
                        // Съёмка первой: за столом снимают здесь и сейчас,
                        // а из галереи разбирают то, что сняли раньше.
                        if CameraPicker.isAvailable {
                            Button {
                                showingCamera = true
                            } label: {
                                Label("Снять", systemImage: "camera")
                            }
                        }
                        PhotosPicker(selection: $pickerItem, matching: .images) {
                            Label("Выбрать из галереи", systemImage: "photo.on.rectangle")
                        }
                    }
                } footer: {
                    Text("Оценка по фотографии приблизительная: вес порции и то, сколько ушло масла, по снимку не видно. Считай её черновиком, который нужно поправить, а не измерением.")
                }

                if let failure {
                    Section {
                        Label(failure, systemImage: "exclamationmark.triangle")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if imageData != nil {
                    Section {
                        Button("Выбрать другое фото") {
                            imageData = nil
                            pickerItem = nil
                            failure = nil
                        }
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .glassRow()
            .listStyle(.insetGrouped)
            .navigationTitle("Фото еды")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
            // Разбор — то, ради чего на экран и зашли, поэтому он внизу под большим
            // пальцем, как «В приём пищи» на экране порции, а не надписью в тулбаре.
            .safeAreaInset(edge: .bottom) {
                if imageData != nil {
                    Button {
                        guard !isRecognizing else { return }
                        Task { await recognize() }
                    } label: {
                        Group {
                            if isRecognizing {
                                HStack(spacing: 10) {
                                    ProgressView()
                                    Text("Разбираем фото...")
                                }
                            } else {
                                Label("Разобрать", systemImage: "sparkles")
                            }
                        }
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    // Не .disabled: он гасит заливку, и кнопка на время разбора
                    // читается как мёртвая. Повторное нажатие отсекает сам обработчик.
                    .allowsHitTesting(!isRecognizing)
                    .accessibilityIdentifier("recognizePhoto")
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 10)
                    .background(.bar)
                }
            }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraPicker { data in
                    imageData = data
                    failure = nil
                }
                .ignoresSafeArea()
            }
            .onChange(of: pickerItem) { _, newValue in
                guard let newValue else { return }
                Task {
                    imageData = try? await newValue.loadTransferable(type: Data.self)
                    failure = nil
                }
            }
        }
    }

    private func recognize() async {
        guard let imageData else { return }
        isRecognizing = true
        failure = nil
        do {
            let items = try await GeminiVisionService.recognize(imageData: imageData)
            guard !items.isEmpty else {
                failure = String(localized: "На фото не видно еды.")
                isRecognizing = false
                return
            }
            onRecognized(items)
            dismiss()
        } catch {
            failure = error.localizedDescription
        }
        isRecognizing = false
    }
}
