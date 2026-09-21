import SwiftUI

/// День полного голодания: отметка и что делать до и после.
///
/// Отметка нужна не ради статистики, а чтобы отличить намеренный день от
/// забытого: в базе они выглядят одинаково — записей нет, — и без отметки
/// приложение рвало серию человеку, который сделал ровно то, что собирался.
struct FastingView: View {
    var store: CalorieStore

    @State private var start = FastingView.defaultStart()
    @State private var end = FastingView.defaultStart().addingTimeInterval(25 * 3600)
    @State private var kind: FastKind = .dry

    /// Уже отмеченный пост, который правим. Ищем его один раз при открытии,
    /// а не по текущему значению пикера: иначе, сдвинув дату, человек «терял»
    /// свою отметку и заводил вторую.
    @State private var editing: FastDay?

    /// Отметка в списке относится к тому же посту, что открыт в пикерах.
    private var isEdited: Bool {
        guard let editing else { return false }
        return editing.interval.start != start || editing.interval.end != end || editing.kind != kind
    }

    /// По умолчанию — ближайший вечер: посты начинаются вечером, а не утром.
    /// Двадцать пять часов сверху — длина Йом Кипура, самого частого случая.
    private static func defaultStart(now: Date = Date()) -> Date {
        let calendar = Calendar.current
        let evening = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: now) ?? now
        return evening > now ? evening : calendar.date(byAdding: .day, value: 1, to: evening) ?? evening
    }

    private var duration: String {
        let minutes = max(0, Int(end.timeIntervalSince(start) / 60))
        let hours = minutes / 60
        return minutes % 60 == 0
            ? String(format: String(localized: "%lld ч"), hours)
            : String(format: String(localized: "%1$lld ч %2$lld мин"), hours, minutes % 60)
    }

    var body: some View {
        List {
            Section {
                // Пост редко совпадает с календарным днём: Йом Кипур идёт
                // с вечера до вечера следующего дня, и считать его сутками
                // значило бы промахнуться на полпоста.
                DatePicker("Начало", selection: $start, displayedComponents: [.date, .hourAndMinute])
                DatePicker("Конец", selection: $end, in: start..., displayedComponents: [.date, .hourAndMinute])
                HStack {
                    Text("Длительность")
                    Spacer()
                    Text(verbatim: duration)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
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
                // Кнопка одна и всегда живая: раньше у отмеченного поста её
                // не было вовсе, и правка времени в пикерах никуда не
                // сохранялась — экран возвращал прежние цифры.
                Button {
                    editing = store.markFast(from: start, to: end, kind: kind, replacing: editing)
                } label: {
                    Label(editing == nil ? "Отметить голодание" : "Сохранить изменения",
                          systemImage: editing == nil ? "moon.stars" : "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(editing != nil && !isEdited)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
                .accessibilityIdentifier("markFastDay")

                if let editing {
                    Label {
                        Text(verbatim: String(format: String(localized: "Отмечено: %1$@ — %2$@"),
                                              editing.interval.start.formatted(date: .abbreviated, time: .shortened),
                                              editing.interval.end.formatted(date: .abbreviated, time: .shortened)))
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                    }
                        .foregroundStyle(ProgressRing.kcalColors[0])
                    Button("Снять отметку", role: .destructive) {
                        store.unmarkFastDay(editing.date)
                        self.editing = nil
                    }
                }
            } footer: {
                Text("Отмеченный день не рвёт серию и входит в недельный банк калорий как есть — с нулём съеденного.")
            }

            adviceSection("Подготовка", items: FastingAdvice.preparation(for: kind))
            adviceSection("Выход", items: FastingAdvice.breakingFast(for: kind))

            Section {
                Label(FastingAdvice.medicalNote, systemImage: "cross.case")
                    .font(.app(.footnote))
                    .foregroundStyle(.secondary)
            }
        }
        .glassRow()
        .listStyle(.insetGrouped)
        .scrollIndicators(.hidden)
        .navigationTitle("Голодание")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Открываем на том посте, который идёт или ближе всего к сегодня:
            // чаще всего правят именно его.
            if let existing = store.nearestFast() {
                editing = existing
                kind = existing.kind
                start = existing.interval.start
                end = existing.interval.end
            }
        }
        .onChange(of: start) { _, newValue in
            // Конец не должен оказаться раньше начала.
            if end <= newValue { end = newValue.addingTimeInterval(25 * 3600) }
        }
    }

    private func adviceSection(_ title: LocalizedStringKey, items: [FastingAdvice.Item]) -> some View {
        Section {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: item.when)
                        .font(.app(.caption, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(verbatim: item.text)
                        .font(.app(.subheadline))
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
