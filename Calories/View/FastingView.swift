import SwiftUI

/// День полного голодания: отметка и что делать до и после.
///
/// Отметка нужна не ради статистики, а чтобы отличить намеренный день от
/// забытого: в базе они выглядят одинаково — записей нет, — и без отметки
/// приложение рвало серию человеку, который сделал ровно то, что собирался.
struct FastingView: View {
    var store: CalorieStore

    @State private var date = Date()
    @State private var kind: FastKind = .dry

    private var marked: FastDay? { store.fastDay(on: date) }

    var body: some View {
        List {
            Section {
                DatePicker("Когда", selection: $date, displayedComponents: [.date])
                Picker("Тип", selection: $kind) {
                    ForEach(FastKind.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text(kind == .dry
                     ? "Сухое — без еды и без воды, как в Йом Кипур. Советы ниже под него."
                     : "На воде — пить можно и нужно. Это меняет половину рекомендаций.")
            }

            Section {
                if marked == nil {
                    Button {
                        store.markFastDay(date, kind: kind)
                    } label: {
                        Label("Отметить день голоданием", systemImage: "moon.stars")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                    .accessibilityIdentifier("markFastDay")
                } else {
                    Label("День отмечен", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Button("Снять отметку", role: .destructive) {
                        store.unmarkFastDay(date)
                    }
                }
            } footer: {
                Text("Отмеченный день не рвёт серию и входит в недельный банк калорий как есть — с нулём съеденного.")
            }

            adviceSection("Подготовка", items: FastingAdvice.preparation(for: kind))
            adviceSection("Выход", items: FastingAdvice.breakingFast(for: kind))

            Section {
                Label(FastingAdvice.medicalNote, systemImage: "cross.case")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .glassRow()
        .listStyle(.insetGrouped)
        .scrollIndicators(.hidden)
        .navigationTitle("Голодание")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let existing = store.fastDay(on: date) { kind = existing.kind }
        }
        .onChange(of: date) { _, newValue in
            if let existing = store.fastDay(on: newValue) { kind = existing.kind }
        }
    }

    private func adviceSection(_ title: LocalizedStringKey, items: [FastingAdvice.Item]) -> some View {
        Section {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: item.when)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(verbatim: item.text)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)
            }
        } header: {
            Text(title)
        }
    }
}
