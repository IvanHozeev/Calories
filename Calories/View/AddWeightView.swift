import SwiftUI

struct AddWeightView: View {
    var store: CalorieStore
    @Environment(\.dismiss) private var dismiss

    @State private var wholeKg: Int
    /// Сотые кило шагом 0,05. Весы с точностью до 50 г — обычное дело, и
    /// округлять их показания до 100 г значит терять половину деления.
    @State private var hundredths: Int
    @State private var date: Date

    init(store: CalorieStore, initialDate: Date = Date()) {
        self.store = store
        _date = State(initialValue: initialDate)
        let kg = store.latestWeight?.weightKg ?? 70.0
        _wholeKg = State(initialValue: max(30, min(150, Int(kg))))
        let fraction = Int((kg * 100).rounded()) % 100
        _hundredths = State(initialValue: min(95, fraction / Self.hundredthsStep * Self.hundredthsStep))
    }

    private var weight: Double {
        Double(wholeKg) + Double(hundredths) / 100.0
    }

    private static let hundredthsStep = 5

    /// Высота листа: ровно под «Когда» и колёса, плюс немного воздуха снизу.
    ///
    /// Константой, а не числом на каждом показе: экранов, откуда взвешиваются,
    /// два — «Сегодня» и профиль, — и они уже разъезжались (в профиле лист был
    /// `.medium` и обрезал колёса).
    static let sheetHeight: CGFloat = 370

    /// Как пишется дробная часть на колесе: «0», «05», «1», «15»… — то есть
    /// ровно то, что стоит после запятой, без хвостового нуля.
    private static func fractionLabel(_ hundredths: Int) -> String {
        hundredths % 10 == 0 ? "\(hundredths / 10)" : String(format: "%02d", hundredths)
    }

    /// Вес записью: одна цифра после запятой, вторая — только если она есть.
    /// Иначе 76,15 показывалось бы как 76,2, а 76,1 — как 76,10.
    static func format(_ kg: Double) -> String {
        let hundredths = Int((kg * 100).rounded())
        return hundredths % 10 == 0
            ? String(format: "%.1f", kg)
            : String(format: "%.2f", kg)
    }

    var body: some View {
        NavigationStack {
            Form {
                // «Когда» первым: дату правят реже веса, но, если правят,
                // искать её ниже колёс приходилось прокруткой — а лист
                // открывается ровно под свою высоту.
                Section {
                    DatePicker(
                        "Когда",
                        selection: $date,
                        in: ...Date(),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }

                Section {
                    HStack(spacing: 0) {
                        Picker("", selection: $wholeKg) {
                            ForEach(30...150, id: \.self) { kg in
                                Text("\(kg)").tag(kg)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(maxWidth: .infinity, maxHeight: 150)
                        .clipped()

                        Text(",")
                            .font(.app(.title2, weight: .semibold))

                        Picker("", selection: $hundredths) {
                            ForEach(Array(stride(from: 0, through: 95, by: Self.hundredthsStep)), id: \.self) { h in
                                Text(verbatim: Self.fractionLabel(h)).tag(h)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(width: 70, height: 150)
                        .clipped()

                        Text("кг")
                            .font(.app(.body))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 8)
                    }
                }

            }
            .glassRow()
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
