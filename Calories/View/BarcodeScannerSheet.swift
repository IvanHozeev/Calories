import SwiftUI
import VisionKit
import Vision

struct BarcodeScannerSheet: View {
    let store: CalorieStore
    /// Nil означает режим «только сохранить в продукты» (без кнопки добавить в приём пищи)
    var onAdd: ((MealItem) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var phase: Phase = .scanning
    @State private var gramsText = "100"

    private enum Phase {
        case scanning
        case loading
        case found(BarcodeProduct)
        case notFound
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .scanning:
                    scannerView
                case .loading:
                    ProgressView("Поиск продукта…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .found(let product):
                    productForm(product)
                case .notFound:
                    notFoundView
                }
            }
            .navigationTitle("Сканер штрихкода")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // «Закрыть» — только когда камера активна
                if case .scanning = phase {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Закрыть") { dismiss() }
                    }
                }
                if case .loading = phase {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Закрыть") { dismiss() }
                    }
                }
                // «Назад» — когда показан результат или ошибка
                if case .found = phase {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Назад") { phase = .scanning; gramsText = "100" }
                    }
                }
                if case .notFound = phase {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Назад") { phase = .scanning }
                    }
                }
            }
        }
    }

    // MARK: - Scanner

    @ViewBuilder
    private var scannerView: some View {
        if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
            BarcodeCameraView { barcode in
                phase = .loading
                Task { await lookup(barcode: barcode) }
            }
            .ignoresSafeArea(edges: .bottom)
            .overlay(alignment: .bottom) {
                Text("Наведи камеру на штрихкод")
                    .font(.callout)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .padding(.bottom, 32)
            }
        } else {
            ContentUnavailableView(
                "Камера недоступна",
                systemImage: "camera.slash",
                description: Text("Сканер штрихкодов недоступен на этом устройстве.")
            )
        }
    }

    // MARK: - Product form

    private func productForm(_ product: BarcodeProduct) -> some View {
        let grams = Double(gramsText.replacingOccurrences(of: ",", with: ".")) ?? 0
        let factor = grams / 100

        return Form {
            Section("Продукт") {
                LabeledContent("Название", value: product.name)
                LabeledContent("Калории", value: "\(product.caloriesPer100g) \(String(localized: "ккал")) / 100 \(String(localized: "г"))")
                if product.protein > 0 {
                    LabeledContent("Белки", value: String(format: "%.1f \(String(localized: "г / 100 г"))", product.protein))
                }
                if product.fat > 0 {
                    LabeledContent("Жиры", value: String(format: "%.1f \(String(localized: "г / 100 г"))", product.fat))
                }
                if product.carbs > 0 {
                    LabeledContent("Углеводы", value: String(format: "%.1f \(String(localized: "г / 100 г"))", product.carbs))
                }
            }

            Section("Порция") {
                HStack {
                    TextField("100", text: $gramsText)
                        .keyboardType(.decimalPad)
                        .font(.title3.weight(.semibold))
                    Text("г")
                        .foregroundStyle(.secondary)
                }
                if grams > 0 {
                    LabeledContent("Итого", value: "\(Int((Double(product.caloriesPer100g) * factor).rounded())) \(String(localized: "ккал"))")
                        .foregroundStyle(.secondary)
                }
            }

        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) { actionBar(product, grams: grams, factor: factor) }
    }

    /// Кнопки закреплены снизу, а не лежат секцией в форме: внутри строки формы
    /// borderedProminent во всю ширину читается как синяя плашка в белой рамке,
    /// и таких плашек было две подряд. Плюс панель не уезжает, когда правишь граммы.
    @ViewBuilder
    private func actionBar(_ product: BarcodeProduct, grams: Double, factor: Double) -> some View {
        let saved = isSaved(product)

        VStack(spacing: 10) {
            if let onAdd {
                Button {
                    guard grams > 0 else { return }
                    onAdd(MealItem(
                        name: product.name,
                        calories: Int((Double(product.caloriesPer100g) * factor).rounded()),
                        macros: Macros(
                            protein: product.protein * factor,
                            fat: product.fat * factor,
                            carbs: product.carbs * factor
                        ),
                        grams: grams
                    ))
                    dismiss()
                } label: {
                    Label("Добавить в приём пищи", systemImage: "plus.circle.fill")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(grams <= 0)
            }

            if saved {
                Label("Уже в моих продуктах", systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            } else if onAdd == nil {
                // Когда добавлять в приём пищи некуда, сохранение и есть главное действие.
                Button { saveToProducts(product) } label: {
                    Label("Сохранить в мои продукты", systemImage: "bookmark")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                Button { saveToProducts(product) } label: {
                    Label("Сохранить в мои продукты", systemImage: "bookmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.bar)
    }

    private func isSaved(_ product: BarcodeProduct) -> Bool {
        store.customFoods.contains {
            $0.name.localizedCaseInsensitiveCompare(product.name) == .orderedSame
        }
    }

    private func saveToProducts(_ product: BarcodeProduct) {
        let alreadySaved = store.customFoods.contains {
            $0.name.localizedCaseInsensitiveCompare(product.name) == .orderedSame
        }
        if !alreadySaved {
            store.addCustomFood(
                name: product.name,
                caloriesPer100g: product.caloriesPer100g,
                protein: product.protein,
                fat: product.fat,
                carbs: product.carbs
            )
        }
        dismiss()
    }

    // MARK: - Not found

    private var notFoundView: some View {
        VStack(spacing: 20) {
            Image(systemName: "barcode.viewfinder")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("Продукт не найден")
                .font(.title2.weight(.semibold))
            Text("Этого штрихкода нет в базе Open Food Facts. Попробуй добавить вручную.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            Button {
                phase = .scanning
            } label: {
                Label("Сканировать снова", systemImage: "barcode.viewfinder")
                    .fontWeight(.semibold)
                    .frame(maxWidth: 260)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Network

    private func lookup(barcode: String) async {
        guard let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(barcode).json?fields=product_name,nutriments") else {
            phase = .notFound; return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (json["status"] as? Int) == 1,
                  let productDict = json["product"] as? [String: Any] else {
                phase = .notFound; return
            }
            let name = (productDict["product_name"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            let nutriments = productDict["nutriments"] as? [String: Any] ?? [:]
            let kcal = nutriments["energy-kcal_100g"] as? Double
                    ?? nutriments["energy-kcal"] as? Double
                    ?? 0
            let protein = nutriments["proteins_100g"] as? Double ?? 0
            let fat = nutriments["fat_100g"] as? Double ?? 0
            let carbs = nutriments["carbohydrates_100g"] as? Double ?? 0

            guard kcal > 0 else { phase = .notFound; return }

            let product = BarcodeProduct(
                name: name.isEmpty ? "Продукт \(barcode)" : name,
                caloriesPer100g: Int(kcal.rounded()),
                protein: protein,
                fat: fat,
                carbs: carbs
            )
            phase = .found(product)
        } catch {
            phase = .notFound
        }
    }
}

// MARK: - Model

struct BarcodeProduct {
    let name: String
    let caloriesPer100g: Int
    let protein: Double
    let fat: Double
    let carbs: Double
}

// MARK: - Camera view

private struct BarcodeCameraView: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce, .code128, .code39, .code93])],
            qualityLevel: .accurate,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {
        try? vc.startScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (String) -> Void
        private var fired = false

        init(onScan: @escaping (String) -> Void) { self.onScan = onScan }

        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !fired,
                  let item = items.first,
                  case let .barcode(b) = item,
                  let value = b.payloadStringValue else { return }
            fired = true
            scanner.stopScanning()
            onScan(value)
        }
    }
}
