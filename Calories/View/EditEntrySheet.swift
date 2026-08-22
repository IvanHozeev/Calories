import SwiftUI

struct EditEntrySheet: View {
    @ObservedObject var store: CalorieStore
    let entry: FoodEntry
    var isEmbedded: Bool = false
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var calories: String
    @State private var protein: String
    @State private var fat: String
    @State private var carbs: String
    @State private var grams: String
    @State private var date: Date

    private enum Field: Hashable { case name, calories, grams, protein, fat, carbs }
    @FocusState private var focusedField: Field?

    init(store: CalorieStore, entry: FoodEntry, isEmbedded: Bool = false) {
        self.store = store
        self.entry = entry
        self.isEmbedded = isEmbedded
        _name = State(initialValue: entry.name)
        _calories = State(initialValue: "\(entry.calories)")
        _protein = State(initialValue: entry.protein > 0 ? String(format: "%g", entry.protein) : "")
        _fat = State(initialValue: entry.fat > 0 ? String(format: "%g", entry.fat) : "")
        _carbs = State(initialValue: entry.carbs > 0 ? String(format: "%g", entry.carbs) : "")
        _grams = State(initialValue: entry.grams.map { String(format: "%g", $0) } ?? "")
        _date = State(initialValue: entry.date)
    }

    var body: some View {
        if isEmbedded {
            formContent
        } else {
            NavigationStack { formContent }
        }
    }

    private var formContent: some View {
        Form {
            Section("Приём пищи") {
                TextField("Название", text: $name)
                    .focused($focusedField, equals: .name)
                HStack {
                    TextField("Калории", text: $calories)
                        .keyboardType(.numberPad)
                        .focused($focusedField, equals: .calories)
                    Divider()
                    TextField("Вес, г", text: $grams)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .grams)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    TextField("Белки, г", text: $protein)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .protein)
                    TextField("Жиры, г", text: $fat)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .fat)
                    TextField("Углеводы, г", text: $carbs)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .carbs)
                }
                DatePicker(
                    "Дата и время",
                    selection: $date,
                    in: ...Date(),
                    displayedComponents: [.date, .hourAndMinute]
                )
            }
        }
        .navigationTitle("Редактировать")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !isEmbedded {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                CheckmarkButton {
                    guard let cal = Int(calories),
                          !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    let macros = Macros(
                        protein: Double(protein.replacingOccurrences(of: ",", with: ".")) ?? 0,
                        fat: Double(fat.replacingOccurrences(of: ",", with: ".")) ?? 0,
                        carbs: Double(carbs.replacingOccurrences(of: ",", with: ".")) ?? 0
                    )
                    let gramsValue = Double(grams.replacingOccurrences(of: ",", with: "."))
                    store.updateEntry(entry, name: name, calories: cal, macros: macros, grams: gramsValue, date: date)
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || Int(calories) == nil)
                .fontWeight(.semibold)
            }
        }
    }
}
