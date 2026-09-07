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

    /// Пусто вместо нуля: подсказка «0» понятнее введённого нуля, который не
    /// отличить от намеренно указанного.
    private static func tenths(_ value: Double) -> String {
        guard value > 0 else { return "" }
        return String(format: "%g", (value * 10).rounded() / 10)
    }

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
        // До десятых: в базе лежат значения с плавающей запятой, и «%g» без
        // округления показывал «3.5999999999999996» вместо «3.6».
        _protein = State(initialValue: Self.tenths(entry.protein))
        _fat = State(initialValue: Self.tenths(entry.fat))
        _carbs = State(initialValue: Self.tenths(entry.carbs))
        _grams = State(initialValue: entry.grams.map { String(format: "%g", $0) } ?? "")
        _date = State(initialValue: entry.date)
        originalGrams = entry.grams
    }

    /// Поле макроса с постоянными подписями: какой это макрос и в чём измеряется.
    ///
    /// Раньше название стояло подсказкой поля и исчезало на первом же символе —
    /// в строке оставались три голых числа. Буква вместо слова, потому что полей
    /// три в ряд, и теми же цветами, что макросы везде в приложении: перекос
    /// тогда считывается глазом, а не прочтением.
    private func unitField(_ short: LocalizedStringKey, color: Color,
                           text: Binding<String>, field: Field) -> some View {
        HStack(spacing: 3) {
            Text(short)
                .font(.caption2.weight(.bold))
                .foregroundStyle(color)
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .focused($focusedField, equals: field)
            Text("г")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
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
                // Единицы подписями справа от каждого поля, а не в подсказке:
                // подсказка исчезает на первом символе, и в строке остаются
                // голые числа — какое из них граммы, а какое килокалории,
                // приходится вспоминать.
                HStack {
                    TextField("Калории", text: $calories)
                        .keyboardType(.numberPad)
                        .focused($focusedField, equals: .calories)
                    Text("ккал")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Divider()
                    TextField("Вес", text: $grams)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .grams)
                        .foregroundStyle(.secondary)
                        .onChange(of: grams) { _, newValue in
                            guard focusedField == .grams else { return }
                            rescale(to: number(newValue))
                        }
                    Text("г")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                // Разделитель без этого начинается от подписи с единицей: у поля
                // ввода нет своей направляющей, и её берут от первого текста.
                .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
                HStack(spacing: 10) {
                    unitField("Б", color: .blue, text: $protein, field: .protein)
                    unitField("Ж", color: .orange, text: $fat, field: .fat)
                    unitField("У", color: .purple, text: $carbs, field: .carbs)
                }
                .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
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
        .glassRow()
        .confirmationDialog("Удалить запись?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                store.delete(entry: entry)
                dismiss()
            }
            Button("Отмена", role: .cancel) {}
        }
        // Свайп вниз по списку должен убирать клавиатуру, а не упираться в неё.
        .scrollDismissesKeyboard(.interactively)
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
