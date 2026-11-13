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
                Text("С днём рождения!")
                    .font(.app(.subheadline, weight: .semibold))
                Text(age.map { String(format: String(localized: "Сегодня тебе %lld. Ешь в удовольствие: один день не решает, решает тренд."), $0) }
                     ?? String(localized: "Ешь в удовольствие: один день не решает, решает тренд."))
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
