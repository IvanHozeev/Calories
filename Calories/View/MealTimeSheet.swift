import SwiftUI

/// Когда именно был приём пищи.
///
/// Меняют это редко — почти всегда еда записывается тогда же, когда съедена, —
/// поэтому на самом экране приёма пищи никакого поля нет: оно занимало строку
/// ради случая, который почти не наступает.
struct MealTimeSheet: View {
    @Binding var date: Date

    @Environment(\.dismiss) private var dismiss
    @State private var draft: Date

    init(date: Binding<Date>) {
        _date = date
        _draft = State(initialValue: date.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // Время, а не только дата: поел и записал через час — приём пищи
                    // должен встать на то время, когда он был, иначе «вчерашний обед»
                    // попадёт в дневник ночью и перепутает картину дня.
                    DatePicker(
                        "Когда",
                        selection: $draft,
                        in: ...Date(),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.graphical)

                    Button("Сейчас") { draft = Date() }
                }
            }
            .glassRow()
            .navigationTitle("Когда")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        date = draft
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview("MealTimeSheet") {
    MealTimeSheet(date: .constant(Date()))
}
