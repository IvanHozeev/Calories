import SwiftUI

/// Разбор расхождения: куда делся вес, который должен был уйти.
///
/// Экран отвечает на вопрос, из-за которого бросают: «я всё делаю правильно, а
/// вес стоит». Он ничего не предсказывает — он раскладывает уже случившееся на
/// слагаемые, каждое из которых измерено: еда против нормы, движение против
/// обычного, расход по формуле против расхода по факту. Что не разложилось,
/// так и называется необъяснённым.
struct StallReportView: View {
    var store: CalorieStore

    private var report: StallReport.Result { StallReport.make(store.stallInput()) }

    var body: some View {
        List {
            summary
            if report.tooLittleData {
                Section {
                    Text("Данных за две недели слишком мало, чтобы разбирать: без регулярных взвешиваний и записей считать нечего.")
                        .font(.app(.callout))
                } header: {
                    Text("Пока нечего считать")
                }
            } else {
                causes
            }
            if !report.remarks.isEmpty { remarks }
        }
        .glassRow()
        .listStyle(.insetGrouped)
        .navigationTitle("Разбор расхождения")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Три числа, ради которых сюда заходят: сколько должно было уйти, сколько
    /// ушло и какова разница.
    private var summary: some View {
        Section {
            ResultRow(title: "Планировалось", value: kg(report.plannedKg))
            ResultRow(title: "Вышло", value: kg(report.actualKg))
            ResultRow(title: "Расхождение", value: kg(report.gapKg), highlighted: true)
        } header: {
            Text("За две недели")
        } footer: {
            explain("Темп по плану против темпа по тренду веса. Тренд, а не последнее взвешивание: вода даёт больше килограмма разброса, и по одному утру судить нельзя.").map { Text($0) }
        }
    }

    private var causes: some View {
        Section {
            if report.causes.isEmpty {
                Text("Заметных причин не нашлось: еда и движение держались плана.")
                    .font(.app(.callout))
                    .foregroundStyle(.secondary)
            }
            ForEach(report.causes) { cause in
                row(text: cause.text, kg: cause.kg, tone: .primary)
            }
            if abs(report.unexplainedKg) >= StallReport.notableKg {
                row(text: String(localized: "Необъяснённое: вода, гликоген, точность весов и ленты"),
                    kg: report.unexplainedKg, tone: .secondary)
            }
        } header: {
            Text("Из чего сложилось")
        } footer: {
            explain("Килограммы рядом с причиной — её вклад в расхождение за эти две недели. Плюс значит «тянуло вес вверх».").map { Text($0) }
        }
    }

    private func row(text: String, kg value: Double, tone: HierarchicalShapeStyle) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(verbatim: text)
                .font(.app(.callout))
                .foregroundStyle(tone)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Text(verbatim: kg(value))
                .font(.app(.callout, weight: .semibold))
                .monospacedDigit()
                // Цвет по направлению, а не по «хорошо и плохо»: вверх — туда,
                // куда вес тянуло, вниз — откуда.
                .foregroundStyle(value > 0 ? Color.orange : Color.green)
        }
        .padding(.vertical, 2)
    }

    private var remarks: some View {
        Section {
            ForEach(report.remarks, id: \.self) { remark in
                Label {
                    Text(verbatim: remark)
                        .font(.app(.callout))
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Что мешает считать точнее")
        }
    }

    private func kg(_ value: Double) -> String {
        String(format: "%+.2f \(String(localized: "кг"))", value)
    }
}
