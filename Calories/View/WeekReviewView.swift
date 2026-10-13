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

    /// Почему предлагается именно это число.
    private func reason(for proposal: Int) -> String {
        let delta = proposal - store.dailyGoal
        let measured = store.smoothedTDEE ?? store.adaptiveTDEE?.tdee
        guard let measured else {
            return String(format: String(localized: "Расчёт плана на эту неделю даёт на %lld ккал в день больше."), delta)
        }
        return String(format: delta > 0
                      ? String(localized: "Измеренный расход — %1$lld ккал в день: при нём план сходится на %2$lld ккал больше нынешней нормы.")
                      : String(localized: "Измеренный расход — %1$lld ккал в день: при нём план сходится на %2$lld ккал меньше нынешней нормы."),
                      Int(measured.rounded()), abs(delta))
    }

    /// «7 – 13 октября»: неделя, о которой речь. Итог считается за последние
    /// семь дней, а не за календарную неделю, — и подпись должна говорить то же.
    static func weekRange(now: Date = Date(), calendar: Calendar = .current) -> String {
        let start = calendar.date(byAdding: .day, value: -6, to: now) ?? now
        let sameMonth = calendar.component(.month, from: start) == calendar.component(.month, from: now)
        let from = start.formatted(sameMonth ? .dateTime.day() : .dateTime.day().month(.wide))
        return "\(from) – \(now.formatted(.dateTime.day().month(.wide)))"
    }

    var body: some View {
        List {
            Section {
                ScreenTitle(title: Self.weekRange())
                    .asScreenTitleRow()
            }

            Section {
                numbers
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            // Договор о норме — здесь, а не само собой.
            //
            // Норма идёт за измеренным расходом, и это правильно. Неправильно
            // было менять её молча: человек жил с числом, которое ехало у него
            // за спиной. Раз в неделю приложение показывает, что посчитало, и
            // спрашивает — а до ответа держит прежнее.
            if let proposal = store.proposedGoal {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(verbatim: "\(store.dailyGoal)")
                                .font(.app(.title3, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .strikethrough()
                            Image(systemName: "arrow.right")
                                .font(.app(.footnote))
                                .foregroundStyle(.tertiary)
                            Text(verbatim: "\(proposal) \(String(localized: "ккал"))")
                                .font(.app(.title3, weight: .bold))
                                .monospacedDigit()
                            Spacer()
                        }
                        Text(verbatim: reason(for: proposal))
                            .font(.app(.caption))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 12) {
                            Button("Оставить как есть") { store.keepCurrentGoal() }
                                .buttonStyle(.bordered)
                            Button("Принять") { store.acceptProposedGoal() }
                                .buttonStyle(.borderedProminent)
                                .accessibilityIdentifier("acceptGoalProposal")
                        }
                    }
                    .padding(.vertical, 2)
                } header: {
                    Text("Норма на следующую неделю")
                } footer: {
                    explain("До ответа норма остаётся прежней. Приложение считает расход по дневнику и весам, но менять число, с которым ты живёшь, без твоего ведома оно не должно.").map { Text($0) }
                }
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
        // Какая именно неделя — над названием: «итог недели» без дат одинаково
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
