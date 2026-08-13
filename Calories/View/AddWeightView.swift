import SwiftUI

struct AddWeightView: View {
    @ObservedObject var store: CalorieStore
    @Environment(\.dismiss) private var dismiss

    @State private var weightText: String
    @State private var date: Date
    @FocusState private var weightFocused: Bool

    init(store: CalorieStore, initialDate: Date = Date()) {
        self.store = store
        _date = State(initialValue: initialDate)
        let latest = store.latestWeight?.weightKg
        _weightText = State(initialValue: latest.map { String(format: "%.1f", $0) } ?? "")
    }

    private var weight: Double? {
        Double(weightText.replacingOccurrences(of: ",", with: "."))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("70.0", text: $weightText)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .focused($weightFocused)
                        Text("кг")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    DatePicker(
                        "Дата",
                        selection: $date,
                        in: ...Date(),
                        displayedComponents: .date
                    )
                }
            }
            .navigationTitle("Взвешивание")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Готово") { weightFocused = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        guard let weight, weight > 0 else { return }
                        store.addWeight(weight, date: date)
                        dismiss()
                    }
                    .disabled(weight == nil || (weight ?? 0) <= 0)
                    .fontWeight(.semibold)
                }
            }
            .onAppear { weightFocused = true }
        }
    }
}
