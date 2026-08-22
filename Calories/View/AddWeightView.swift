import SwiftUI

struct AddWeightView: View {
    var store: CalorieStore
    @Environment(\.dismiss) private var dismiss

    @State private var wholeKg: Int
    @State private var tenths: Int
    @State private var date: Date

    init(store: CalorieStore, initialDate: Date = Date()) {
        self.store = store
        _date = State(initialValue: initialDate)
        let kg = store.latestWeight?.weightKg ?? 70.0
        _wholeKg = State(initialValue: max(30, min(150, Int(kg))))
        _tenths = State(initialValue: min(9, Int((kg * 10).truncatingRemainder(dividingBy: 10))))
    }

    private var weight: Double {
        Double(wholeKg) + Double(tenths) / 10.0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 0) {
                        Picker("", selection: $wholeKg) {
                            ForEach(30...150, id: \.self) { kg in
                                Text("\(kg)").tag(kg)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(maxWidth: .infinity)
                        .clipped()

                        Text(",")
                            .font(.title2.weight(.semibold))

                        Picker("", selection: $tenths) {
                            ForEach(0...9, id: \.self) { t in
                                Text("\(t)").tag(t)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(width: 60)
                        .clipped()

                        Text("кг")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 8)
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
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        store.addWeight(weight, date: date)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
