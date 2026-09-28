import SwiftUI

/// Итог недели: семь дней одним разбором.
///
/// День отвечает «как я сегодня», но решает не он: вес двигается неделями,
/// расход считается по неделе, дефицит держится или срывается тоже на неделе.
/// До этого экрана человек видел семь кружков в полоске и складывал их в уме.
struct WeekReviewView: View {
    var store: CalorieStore

    private var input: WeekReview.Input { store.weekReviewInput() }

    private var lines: [WeekReview.Line] {
        WeekReview.lines(input, brief: ExplanationSettings.shared.level == .expert)
    }

    var body: some View {
        List {
            Section {
                numbers
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            Section {
                ForEach(lines) { line in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: icon(line.tone))
                            .font(.app(.footnote))
                            .foregroundStyle(color(line.tone))
                            .frame(width: 18)
                        Text(verbatim: line.text)
                            .font(.app(.footnote))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("Что это значит")
            }
        }
        .glassRow()
        .listStyle(.insetGrouped)
        .scrollIndicators(.hidden)
        .navigationTitle("Итог недели")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Три числа, ради которых сюда заходят: сколько ел, куда пошёл вес,
    /// сколько дней записано.
    private var numbers: some View {
        HStack(alignment: .top, spacing: 8) {
            cell(title: "В среднем", value: meanEaten, unit: "ккал")
            cell(title: "Вес", value: weightChange, unit: "кг")
            cell(title: "Записано", value: "\(input.loggedDays)", unit: "из 7")
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var meanEaten: String {
        guard !input.eaten.isEmpty else { return "—" }
        return "\(input.eaten.reduce(0, +) / input.eaten.count)"
    }

    private var weightChange: String {
        guard let start = input.weightStart, let end = input.weightEnd else { return "—" }
        return String(format: "%+.2f", end - start)
    }

    private func cell(title: LocalizedStringKey, value: String, unit: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.app(.caption2))
                .foregroundStyle(.tertiary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(verbatim: value)
                    .font(.app(.title3, weight: .bold))
                    .monospacedDigit()
                Text(unit)
                    .font(.app(.caption2))
                    .foregroundStyle(.tertiary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func icon(_ tone: WeekReview.Line.Tone) -> String {
        switch tone {
        case .good: return "checkmark.circle"
        case .warning: return "exclamationmark.triangle"
        case .info: return "info.circle"
        }
    }

    private func color(_ tone: WeekReview.Line.Tone) -> Color {
        switch tone {
        case .good: return ProgressRing.kcalColors[0]
        case .warning: return ProgressRing.overColors[0]
        case .info: return .secondary
        }
    }
}
