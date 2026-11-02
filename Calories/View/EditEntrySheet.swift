import SwiftUI

struct EditEntrySheet: View {
    var store: CalorieStore
    let entry: FoodEntry
    var isEmbedded: Bool = false
    @Environment(\.dismiss) private var dismiss

    @State private var date: Date
    @State private var confirmingDelete = false

    /// Приём правится по частям: у каждой свой вес, и калории с БЖУ
    /// пересчитываются по ней одной.
    ///
    /// Частей бывает и одна — запись из единственного продукта это тот же
    /// приём, просто короткий. Раньше у неё был свой вид: четыре поля ввода
    /// вместо строки, и один и тот же экран выглядел по-разному в зависимости
    /// от того, сколько в записи еды.
    @State private var parts: [EntryComponent]
    /// Часть, которой правят вес: индекс открытого экрана порции.
    @State private var editingPart: Int?
    /// Сколько каждая часть весила и стоила изначально — база для пропорции.
    private let basis: [EntryComponent]

    /// Составной приём хранит состав отдельно; у записи из одного продукта
    /// состава нет — и дописывать его при правке веса не нужно.
    private let isComposed: Bool

    private var partsCalories: Int { parts.reduce(0) { $0 + $1.calories } }
    private var partsMacros: Macros { parts.reduce(Macros.zero) { $0 + $1.macros } }

    init(store: CalorieStore, entry: FoodEntry, isEmbedded: Bool = false) {
        self.store = store
        self.entry = entry
        self.isEmbedded = isEmbedded
        _date = State(initialValue: entry.date)
        // `composition`, а не `components`: у записи из одного продукта он
        // пуст, и она сама себе единственная часть.
        basis = entry.composition
        _parts = State(initialValue: entry.composition)
        isComposed = !entry.components.isEmpty
    }

    var body: some View {
        if isEmbedded {
            formContent
        } else {
            NavigationStack { formContent }
        }
    }

    /// Строка части — та же, что в составе блюда.
    ///
    /// Здесь стояла своя: калории серым и без единицы, зажатые между
    /// названием и полем ввода веса. «180» без «ккал» — не число, а загадка,
    /// и два списка, которые читают одними глазами, выглядели по-разному.
    /// Теперь вес подписью под названием, калории справа со словом —
    /// ровно как ингредиент блюда.
    private func partRow(_ index: Int) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: parts[index].name)
                    .font(.app(.body, weight: .semibold))
                    .multilineTextAlignment(.leading)
                // Вес известен не всегда: у распознанного по фото или
                // записанного порцией его нет вовсе — и править там нечего.
                Text(verbatim: basis[index].grams == nil
                     ? String(localized: "порция")
                     : String(format: "%g \(String(localized: "г"))", parts[index].grams ?? 0))
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(verbatim: "\(parts[index].calories) \(String(localized: "ккал"))")
                .foregroundStyle(.secondary)
        }
        // Тап, а не свайп: экран порции здесь тот же, что при добавлении, —
        // с ценой ста граммов, макросами и шагом веса. Свайп прятал правку
        // за жестом, о котором неоткуда узнать, и отдавал ей одно поле там,
        // где человек привык видеть весь продукт.
        .contentShape(Rectangle())
        .onTapGesture {
            guard basis[index].grams != nil else { return }
            editingPart = index
        }
    }

    /// Часть в виде продукта «на сто граммов» — экран порции считает от него.
    ///
    /// Своих чисел на сто граммов у части нет: она записана тем весом,
    /// которым её съели. Пересчитываем обратно.
    private func per100g(_ part: EntryComponent, grams: Double) -> FoodItem {
        let factor = 100 / grams
        return FoodItem(name: part.name,
                        caloriesPer100g: Int((Double(part.calories) * factor).rounded()),
                        protein: part.macros.protein * factor,
                        fat: part.macros.fat * factor,
                        carbs: part.macros.carbs * factor)
    }

    /// Пересчитывает одну часть под новый вес — пропорционально её исходным
    /// числам, а не числам приёма целиком.
    private func rescalePart(_ index: Int, to newGrams: Double) {
        guard newGrams > 0 else { return }
        parts[index] = basis[index].scaled(toGrams: newGrams)
    }

    private var formContent: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    Text(verbatim: "\(partsCalories) \(String(localized: "ккал"))")
                        .font(.app(size: 34, weight: .bold))
                        .foregroundStyle(.green)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .contentTransition(.numericText())
                    MacroTags(macros: partsMacros)
                    if partsMacros.protein > 0 || partsMacros.fat > 0 || partsMacros.carbs > 0 {
                        MacroSplitBar(macros: partsMacros)
                            .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .animation(.easeInOut(duration: 0.2), value: partsCalories)
            }
            .listRowBackground(Color.clear)

            // Дата и время — сразу под итогом и своей секцией.
            //
            // Это не часть приёма, а его место в дне: раньше строка стояла
            // в хвосте, за составом и полями, и правили её чаще, чем всё
            // остальное вместе взятое — записал задним числом, поправил час.
            //
            // Подпись ушла в заголовок секции, а строка осталась двум
            // колёсикам: день слева, час справа. Подпись и два колёсика в
            // одной строке делили её на три неравные части, и строка читалась
            // теснее, чем в ней было смысла.
            Section {
                // Одно колёсико на обе половины, а не два по краям строки.
                //
                // Колёсико даты держит ширину под самую длинную форму — под
                // «1 нояб. 2026 г.» — и прижимает к её правому краю то, что
                // показывает сейчас. Поэтому «28.10.2026» отъезжало от левого
                // края строки, а «1 нояб. 2026 г.» нет: обе капсулы кончались
                // в одной точке, а начинались в разных. Ни выключкой, ни
                // `fixedSize` это не лечится — ширину выбирает сам контрол.
                //
                // С одним колёсиком система ставит капсулы вплотную друг к
                // другу и сама отвечает за промежуток между ними.
                HStack {
                    DatePicker("Дата и время", selection: $date, in: ...Date(),
                               displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                    Spacer(minLength: 0)
                }
            } header: {
                Text("Дата и время")
            }

            // Приём правится по частям — одна в нём или шесть.
            Section {
                ForEach(parts.indices, id: \.self) { index in
                    partRow(index)
                }
            } header: {
                Text("Приём пищи")
            } footer: {
                explain("Тап по части открывает её экран порции: калории и БЖУ пересчитываются пропорционально новому весу, а итог складывается заново.").map { Text($0) }
            }

            Section {
                Button("Удалить запись", role: .destructive) {
                    confirmingDelete = true
                }
                .frame(maxWidth: .infinity)
            }
        }
        .glassRow()
        // Обычное окно подтверждения, а не «диалог действий»: последний на
        // iOS 26 всплывает пузырём у края экрана — с одной кнопкой «Удалить»,
        // без видимой отмены и поверх собственного заголовка. Для одного
        // вопроса с двумя ответами правильное место — по центру.
        .navigationDestination(item: $editingPart) { index in
            if index < parts.count, let grams = parts[index].grams, grams > 0 {
                FoodQuantityView(food: per100g(parts[index], grams: grams),
                                 grams: grams,
                                 addTitle: "Готово",
                                 isPushed: true) { edited in
                    rescalePart(index, to: edited.grams ?? grams)
                    // Закрываем сами: экран показан из этого состояния,
                    // убрать его надо тем же, чем открыли.
                    editingPart = nil
                }
            }
        }
        .alert("Удалить запись?", isPresented: $confirmingDelete) {
            Button("Отмена", role: .cancel) {}
            Button("Удалить", role: .destructive) {
                store.delete(entry: entry)
                dismiss()
            }
        }
        // Без пояснения: «запись исчезнет, и день пересчитается» — это и
        // есть удаление записи, о котором спрашивает заголовок.

        // Свайп вниз по списку должен убирать клавиатуру, а не упираться в неё.
        .scrollDismissesKeyboard(.interactively)
        .screenTitle(entry.name.isEmpty ? String(localized: "Редактировать") : entry.name,
                     eyebrow: entry.name.isEmpty ? nil : String(localized: "Редактировать"),
                     lines: 2,
                     cancelTitle: isEmbedded ? nil : String(localized: "Отмена"),
                     trailingButtons: 1)
        .toolbar {
            if !isEmbedded {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                CheckmarkButton {
                    // Итог складывается из частей, а не берётся из полей:
                    // своих чисел у приёма нет ни когда частей шесть, ни
                    // когда она одна.
                    let total = parts.compactMap(\.grams).reduce(0, +)
                    store.updateEntry(entry,
                                      name: entry.name,
                                      calories: partsCalories,
                                      macros: partsMacros,
                                      grams: total > 0 ? total : nil,
                                      date: date,
                                      // Состав дописываем только тому, у кого
                                      // он был: записи из одного продукта он
                                      // не нужен, она сама себе состав.
                                      components: isComposed ? parts : nil)
                    dismiss()
                }
                .fontWeight(.semibold)
            }
        }
    }
}
