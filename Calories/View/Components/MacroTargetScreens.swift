import SwiftUI

/// Норма углеводов — остаток нормы калорий после белка и жира.
///
/// Раньше это была секция в самом низу профиля, под нормами белка и жира.
/// Теперь нормы живут своими экранами, и остаток показан на каждом: меняя
/// белок или жир, человек сразу видит, сколько остаётся на углеводы.
struct CarbBudgetSection: View {
    var store: CalorieStore
    let profile: UserProfile
    let measurement: BodyMeasurement?

    var body: some View {
        let protein = profile.proteinTargetGrams(from: measurement)
        let fat = profile.fatTargetGrams
        let goal = Double(store.adaptedTodayGoal > 0 ? store.adaptedTodayGoal : store.dailyGoal)
        let locked = protein * MacroTargets.kcalPerProteinGram + fat * MacroTargets.kcalPerFatGram
        let carbs = (goal - locked) / MacroTargets.kcalPerCarbGram

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
            Text("Норма углеводов").listSectionTitle()
        } footer: {
            explain("Белок и жир заданы телом, углеводы — остаток нормы калорий. В день с повышенной нормой вырастут именно они.").map { Text($0) }
        }
    }
}

/// Норма белка: способ счёта, граммы на килограмм и итог.
struct ProteinTargetScreen: View {
    var store: CalorieStore
    @Binding var draft: ProfileDraft
    @Binding var openPicker: ProfilePicker?
    let measurement: BodyMeasurement?

    var body: some View {
        List {
            ProteinTargetSection(draft: $draft, openPicker: $openPicker, measurement: measurement)
            CarbBudgetSection(store: store, profile: draft.profile, measurement: measurement)
        }
        .glassRow()
        .listStyle(.insetGrouped)
        .scrollIndicators(.hidden)
        .contentMargins(.top, 4, for: .scrollContent)
        .screenTitle(String(localized: "Белки"))
    }
}

/// Норма жира: граммы на килограмм, предупреждение у границ и итог.
struct FatTargetScreen: View {
    var store: CalorieStore
    @Binding var draft: ProfileDraft
    @Binding var openPicker: ProfilePicker?
    let measurement: BodyMeasurement?

    var body: some View {
        List {
            FatTargetSection(draft: $draft, openPicker: $openPicker)
            CarbBudgetSection(store: store, profile: draft.profile, measurement: measurement)
        }
        .glassRow()
        .listStyle(.insetGrouped)
        .scrollIndicators(.hidden)
        .contentMargins(.top, 4, for: .scrollContent)
        .screenTitle(String(localized: "Жиры"))
    }
}

/// Выбор уровня активности: те же пять строк, но своим экраном.
struct ActivityLevelScreen: View {
    @Binding var draft: ProfileDraft
    let usesFact: Bool

    var body: some View {
        List {
            ActivityLevelSection(draft: $draft, usesFact: usesFact)
        }
        .glassRow()
        .listStyle(.insetGrouped)
        .scrollIndicators(.hidden)
        .contentMargins(.top, 4, for: .scrollContent)
        .screenTitle(String(localized: "Активность"))
    }
}
