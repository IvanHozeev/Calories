import SwiftUI

/// Открытка в день рождения — над подсказками «Сегодня».
///
/// Приложение знает дату рождения ради расчёта обмена, и в этот день было бы
/// странно встретить человека подсказкой «сегодня перебор». Открытка говорит
/// то, что приложение и так думает: один день недели не решает, решает тренд.
/// Смахивается влево, как подсказки, и до завтра.
struct BirthdayCard: View {
    /// Сколько исполнилось; nil — если по дате посчитать нельзя.
    let age: Int?

    @State private var appeared = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "gift.fill")
                .font(.app(.title2))
                .foregroundStyle(ProgressRing.kcalColors[0])
                .symbolEffect(.bounce, value: appeared)
            VStack(alignment: .leading, spacing: 3) {
                Text("С днём рождения!")
                    .font(.app(.headline))
                if let age {
                    Text(verbatim: String(format: String(localized: "Сегодня тебе %lld. Ешь в удовольствие: один день не решает, решает тренд."), age))
                        .font(.app(.subheadline))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Ешь в удовольствие: один день не решает, решает тренд.")
                        .font(.app(.subheadline))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("birthdayCard")
        .onAppear { appeared = true }
    }
}
