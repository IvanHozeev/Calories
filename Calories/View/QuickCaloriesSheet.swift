import SwiftUI

/// Запись одних калорий, без продукта.
///
/// Нужна там, где нечего ни взвесить, ни назвать: гости, ресторан, чужая кухня.
/// Раньше это поле висело прямо на экране приёма пищи и мешало всё остальное
/// время, поэтому теперь оно живёт отдельно и открывается из меню.
struct QuickCaloriesSheet: View {
    var onSave: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    private var calories: Int? {
        guard let value = Int(text), value > 0 else { return nil }
        return value
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Ккал", text: $text)
                        .keyboardType(.numberPad)
                        .font(.title2.weight(.semibold))
                        .focused($focused)
                        .accessibilityIdentifier("quickCaloriesField")
                } footer: {
                    Text("Без названия и макросов — в дневник уйдёт только число.")
                }
            }
            .glassRow()
            // Заголовок короткий: «Только калории» между «Отмена» и «Сохранить»
            // не помещается и обрезается многоточием.
            .navigationTitle("Калории")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        guard let calories else { return }
                        onSave(calories)
                    }
                    .disabled(calories == nil)
                    .accessibilityIdentifier("saveQuickCalories")
                }
            }
            .onAppear { focused = true }
        }
    }
}

#Preview("QuickCaloriesSheet") {
    QuickCaloriesSheet { _ in }
}
