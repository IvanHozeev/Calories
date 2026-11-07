import SwiftUI

/// Секция нормы углеводов: остаток дневной нормы калорий после белка и жира.
///
/// Белок и жир заданы телом, углеводы — это то, что осталось от нормы калорий.
/// Если белок и жир уже превышают норму, показывается предупреждение вместо числа.
struct MacroBudgetSection: View {
    let profile: UserProfile
    let measurement: BodyMeasurement?
    let adaptedTodayGoal: Int
    let dailyGoal: Int

    var body: some View {
        let protein = profile.proteinTargetGrams(from: measurement)
        let fat = profile.fatTargetGrams
        let goal = Double(adaptedTodayGoal > 0 ? adaptedTodayGoal : dailyGoal)
        let locked = protein * MacroTargets.kcalPerProteinGram + fat * MacroTargets.kcalPerFatGram
        let carbs = (goal - locked) / MacroTargets.kcalPerCarbGram

        // Белок и жир здесь не повторяем: их «итого» стоит двумя секциями выше,
        // в самих нормах, где их и задают. Новое число тут одно — углеводы,
        // которых никто не задаёт: они остаток нормы калорий.
        Section {
            if carbs > 0 {
                MacroBudgetRow("Углеводы", grams: carbs, color: MacroKind.carbs.color)
            } else {
                Label(
                    String(
                        format: String(localized: "Белок и жир не помещаются в норму: не хватает %d ккал. Подними калораж или опусти норму белка."),
                        Int((locked - goal).rounded())
                    ),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.app(.footnote))
                .foregroundStyle(.orange)
            }
        } header: {
            Text("Норма углеводов")
        } footer: {
            explain("Белок и жир заданы телом, углеводы — остаток нормы калорий. В день с повышенной нормой вырастут именно они.").map { Text($0) }
        }
    }
}
