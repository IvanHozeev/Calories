import SwiftUI

/// Как прошла неделя по макросам.
///
/// Смысл в том, чтобы видеть две разные вещи рядом: белок, который надо набирать
/// каждый день одинаково, и углеводы, которые ходят вслед за нормой калорий.
/// Поэтому попадания считаются только по белку — остальное показано средними.
struct MacroWeekSection: View {
    let days: [MacroDay]

    /// Сегодня в среднее не входит: день ещё не закончен, и незаконченный день
    /// тянул бы среднее вниз, изображая недобор там, где его нет.
    private var counted: [MacroDay] {
        days.filter { $0.hasEntries && !Calendar.current.isDateInToday($0.date) }
    }

    private func average(_ value: (MacroDay) -> Double) -> Double {
        guard !counted.isEmpty else { return 0 }
        return counted.reduce(0) { $0 + value($1) } / Double(counted.count)
    }

    var body: some View {
        if !days.isEmpty {
            Section {
                strip

                if counted.isEmpty {
                    Text("Пока нет законченных дней с записями")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    row("Попадания по белку",
                        value: "\(counted.filter(\.hitProtein).count) / \(counted.count)",
                        color: counted.allSatisfy(\.hitProtein) ? .green : .orange)
                    row("Белки",
                        value: grams(average { $0.macros.protein }, of: average(\.proteinTarget)),
                        color: average { $0.macros.protein } >= average(\.proteinTarget) ? .green : .orange)
                    row("Жиры",
                        value: grams(average { $0.macros.fat }, of: average(\.fatTarget)),
                        color: .secondary)
                    row("Углеводы",
                        value: grams(average { $0.macros.carbs }, of: average(\.carbsTarget)),
                        color: .secondary)
                }
            } header: {
                Text("Макросы за неделю")
            } footer: {
                Text("Белок засчитан, только когда набран целиком. Сегодня в среднее не входит — день ещё не закончен.")
            }
        }
    }

    private func grams(_ value: Double, of target: Double) -> String {
        "\(Int(value.rounded())) / \(Int(target.rounded())) \(String(localized: "г"))"
    }

    private func row(_ title: LocalizedStringKey, value: String, color: Color) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(verbatim: value)
                .font(.body.weight(.semibold))
                .foregroundStyle(color)
                .monospacedDigit()
        }
    }

    /// Неделя одной полосой: сразу видно, где провалы, а где ряд подряд.
    private var strip: some View {
        HStack(spacing: 6) {
            ForEach(days) { day in
                VStack(spacing: 6) {
                    Text(verbatim: day.date.formatted(.dateTime.weekday(.narrow)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color(for: day))
                        .frame(height: 26)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text(verbatim: day.date.formatted(.dateTime.weekday(.wide))))
                .accessibilityValue(day.hasEntries
                                    ? (day.hitProtein ? Text("Белок набран") : Text("Белок не набран"))
                                    : Text("Нет записей"))
            }
        }
        .padding(.vertical, 4)
    }

    private func color(for day: MacroDay) -> Color {
        guard day.hasEntries else { return .gray.opacity(0.25) }
        return day.hitProtein ? .green : .orange
    }
}
