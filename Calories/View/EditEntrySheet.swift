import SwiftUI

struct EditEntrySheet: View {
    var store: CalorieStore
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
    @State private var confirmingDelete = false

    /// Исходная порция — от неё считаем пропорцию при правке веса.
    private let originalGrams: Double?

    private func number(_ text: String) -> Double {
        Double(text.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private var draftMacros: Macros {
        Macros(protein: number(protein), fat: number(fat), carbs: number(carbs))
    }

    private var draftCalories: Int { Int(number(calories)) }

    /// Пересчитывает калории и БЖУ пропорционально новому весу.
    /// Самая частая правка записи — «съел больше, чем записал», и вручную пересчитывать
    /// четыре числа никто не станет.
    private func rescale(to newGrams: Double) {
        guard let originalGrams, originalGrams > 0, newGrams > 0 else { return }
        let factor = newGrams / originalGrams
        calories = "\(Int((Double(entry.calories) * factor).rounded()))"
        protein = String(format: "%g", (entry.protein * factor * 10).rounded() / 10)
        fat = String(format: "%g", (entry.fat * factor * 10).rounded() / 10)
        carbs = String(format: "%g", (entry.carbs * factor * 10).rounded() / 10)
    }

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
        originalGrams = entry.grams
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
            Section {
                VStack(spacing: 10) {
                    Text(verbatim: "\(draftCalories) \(String(localized: "ккал"))")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.green)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .contentTransition(.numericText())
                    MacroTags(macros: draftMacros)
                    if draftMacros.protein > 0 || draftMacros.fat > 0 || draftMacros.carbs > 0 {
                        MacroSplitBar(macros: draftMacros)
                            .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .animation(.easeInOut(duration: 0.2), value: draftCalories)
            }
            .listRowBackground(Color.clear)

            Section {
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
                        .onChange(of: grams) { _, newValue in
                            guard focusedField == .grams else { return }
                            rescale(to: number(newValue))
                        }
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
            } header: {
                Text("Приём пищи")
            } footer: {
                if originalGrams != nil {
                    Text("При изменении веса калории и БЖУ пересчитываются пропорционально.")
                }
            }

            Section {
                Button("Удалить запись", role: .destructive) {
                    confirmingDelete = true
                }
                .frame(maxWidth: .infinity)
            }
        }
        .confirmationDialog("Удалить запись?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                store.delete(entry: entry)
                dismiss()
            }
            Button("Отмена", role: .cancel) {}
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
