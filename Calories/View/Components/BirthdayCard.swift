import SwiftUI

/// Открытка в день рождения — строкой под кольцом.
///
/// Приложение знает дату рождения ради расчёта обмена, и в этот день было бы
/// странно встретить человека подсказкой «сегодня перебор». Открытка говорит
/// то, что приложение и так думает: один день не решает, решает тренд.
///
/// Компактная, в высоту строки взвешивания: под кольцом каждая строка
/// отнимает место у знака дня, и праздник не должен его съедать.
/// Смахивается влево, как подсказки, и до завтра.
struct BirthdayCard: View {
    /// Сколько исполнилось; nil — если по дате посчитать нельзя.
    let age: Int?

    @State private var appeared = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "gift.fill")
                .font(.app(.subheadline))
                .foregroundStyle(ProgressRing.kcalColors[0])
                .symbolEffect(.bounce, value: appeared)
            VStack(alignment: .leading, spacing: 1) {
                Text(age.map { String(format: String(localized: "С днём рождения! Тебе %lld"), $0) }
                     ?? String(localized: "С днём рождения!"))
                    .font(.app(.subheadline, weight: .semibold))
                    .lineLimit(1)
                Text("Один день не решает, решает тренд")
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("birthdayCard")
        .onAppear { appeared = true }
    }
}
