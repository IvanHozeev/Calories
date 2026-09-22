import Testing
import UIKit
import Foundation
import SwiftData
@testable import Calories

// MARK: - Macros

struct MacrosTests {
    // MARK: - Ведущий макрос

    @Test func chickenBreastLeadsWithProtein() {
        #expect(Macros(protein: 31, fat: 3.6, carbs: 0).leadingKind == .protein)
    }

    @Test func riceLeadsWithCarbs() {
        #expect(Macros(protein: 2.7, fat: 0.3, carbs: 28).leadingKind == .carbs)
    }

    @Test func leadershipIsCountedInCaloriesNotGrams() {
        // Яйцо: белка в граммах больше, чем жира, но жир даёт почти вдвое
        // больше калорий. Продукт жировой, и красить его в белковый цвет — врать.
        #expect(Macros(protein: 13, fat: 11, carbs: 1.1).leadingKind == .fat)
    }

    @Test func aMixedFoodHasNoLeader() {
        // Ни один макрос не даёт больше половины калорий.
        #expect(Macros(protein: 20, fat: 9, carbs: 20).leadingKind == nil)
    }

    @Test func aTraceOfOneMacroDoesNotMakeAFoodRichInIt() {
        // Огурец почти весь из углеводов по калориям, но их там три грамма.
        #expect(Macros(protein: 0.7, fat: 0.1, carbs: 3.6).leadingKind == nil)
    }

    @Test func nothingHasNoLeader() {
        #expect(Macros.zero.leadingKind == nil)
    }

    // MARK: - Границы жира

    @Test func fatBelowTheFloorIsRaisedToIt() {
        var profile = UserProfile(weightKg: 80, heightCm: 180, age: 30, sex: .male,
                                  activityLevel: .moderate, goal: .fatLoss, proteinPerKg: 2.0)
        profile.fatPerKg = 0.3
        #expect(profile.fatPerKg == MacroTargets.fatFloorPerKg)
    }

    @Test func fatAboveTheCeilingIsCappedAtIt() {
        var profile = UserProfile(weightKg: 80, heightCm: 180, age: 30, sex: .male,
                                  activityLevel: .moderate, goal: .fatLoss, proteinPerKg: 2.0)
        profile.fatPerKg = 2.0
        #expect(profile.fatPerKg == MacroTargets.fatCeilingPerKg)
    }

    @Test func aValueInsideTheBoundsIsKeptAsIs() {
        var profile = UserProfile(weightKg: 80, heightCm: 180, age: 30, sex: .male,
                                  activityLevel: .moderate, goal: .fatLoss, proteinPerKg: 2.0)
        profile.fatPerKg = 0.9
        #expect(abs(profile.fatPerKg - 0.9) < 0.0001)
    }


    @Test func addition() {
        let a = Macros(protein: 10, fat: 5, carbs: 20)
        let b = Macros(protein: 3, fat: 2, carbs: 8)
        let sum = a + b
        #expect(sum.protein == 13)
        #expect(sum.fat == 7)
        #expect(sum.carbs == 28)
    }

    @Test func zeroIsNeutral() {
        let m = Macros(protein: 5, fat: 3, carbs: 12)
        let r = m + .zero
        #expect(r.protein == 5)
        #expect(r.fat == 3)
        #expect(r.carbs == 12)
    }

    @Test func scaled() {
        let m = Macros(protein: 20, fat: 10, carbs: 40)
        let s = m.scaled(by: 200)
        #expect(s.protein == 40)
        #expect(s.fat == 20)
        #expect(s.carbs == 80)
    }

    @Test func scaledByZero() {
        let m = Macros(protein: 20, fat: 10, carbs: 40)
        let s = m.scaled(by: 0)
        #expect(s.protein == 0)
        #expect(s.fat == 0)
        #expect(s.carbs == 0)
    }
}

// MARK: - DaySummary

struct DaySummaryTests {

    private func entry(_ kcal: Int, protein: Double = 0, fat: Double = 0, carbs: Double = 0) -> FoodEntry {
        FoodEntry(name: "test", calories: kcal, macros: Macros(protein: protein, fat: fat, carbs: carbs))
    }

    @Test func totalCalories_empty() {
        let s = DaySummary(date: .now, entries: [], goal: 2000)
        #expect(s.totalCalories == 0)
    }

    @Test func totalCalories_summed() {
        let s = DaySummary(date: .now, entries: [entry(400), entry(600)], goal: 2000)
        #expect(s.totalCalories == 1000)
    }

    @Test func difference_under() {
        let s = DaySummary(date: .now, entries: [entry(1500)], goal: 2000)
        #expect(s.difference == -500)
    }

    @Test func difference_over() {
        let s = DaySummary(date: .now, entries: [entry(2500)], goal: 2000)
        #expect(s.difference == 500)
    }

    @Test func totalMacros_aggregated() {
        let s = DaySummary(
            date: .now,
            entries: [
                entry(0, protein: 10, fat: 5, carbs: 20),
                entry(0, protein: 30, fat: 15, carbs: 60)
            ],
            goal: 2000
        )
        #expect(s.totalMacros.protein == 40)
        #expect(s.totalMacros.fat == 20)
        #expect(s.totalMacros.carbs == 80)
    }
}

// MARK: - UserProfile

struct UserProfileTests {

    private func profile(
        age: Int = 30,
        heightCm: Double = 175,
        weightKg: Double = 75,
        sex: Sex = .male,
        activity: ActivityLevel = .moderate,
        goal: Goal = .maintenance
    ) -> UserProfile {
        UserProfile(
            weightKg: weightKg,
            heightCm: heightCm,
            age: age,
            sex: sex,
            activityLevel: activity,
            goal: goal,
            proteinPerKg: UserProfile.defaultProteinPerKg
        )
    }

    @Test func bmr_male() {
        let bmr = profile(age: 30, heightCm: 175, weightKg: 75, sex: .male).bmr
        #expect(abs(bmr - 1699) < 5)
    }

    @Test func bmr_female() {
        let bmr = profile(age: 30, heightCm: 165, weightKg: 60, sex: .female).bmr
        #expect(abs(bmr - 1320) < 5)
    }

    @Test func tdee_greaterThanBmr() {
        let p = profile(activity: .sedentary)
        #expect(p.tdee > p.bmr)
    }

    @Test func calorieTarget_fatLoss() {
        let p = profile(goal: .fatLoss)
        #expect(p.calorieTarget < Int(p.tdee))
    }

    @Test func calorieTarget_maintenance() {
        let p = profile(goal: .maintenance)
        #expect(p.calorieTarget == Int(p.tdee.rounded()))
    }

    @Test func calorieTarget_muscleGain() {
        let p = profile(goal: .muscleGain)
        #expect(p.calorieTarget > Int(p.tdee))
    }

    @Test func proteinTarget_positive() {
        let p = profile(weightKg: 80)
        #expect(p.proteinTargetGrams(from: nil) > 0)
    }

    @Test func bmi_correct() {
        let p = profile(heightCm: 175, weightKg: 75)
        #expect(abs(p.bmi - 24.49) < 0.1)
    }

    @Test func navyBodyFat_male_nonNil() {
        let p = profile(sex: .male)
        let m = BodyMeasurement(date: Date())
        m.beltCm = 85       // у мужчин метод берёт уровень пупка
        m.neckCm = 37
        #expect(p.navyBodyFat(from: m) != nil)
        #expect(p.navyBodyFat(from: m)! > 0)
    }

    @Test func navyBodyFat_nil_whenWaistEqualsNeck() {
        let p = profile(sex: .male)
        let m = BodyMeasurement(date: Date())
        m.beltCm = 37
        m.neckCm = 37
        #expect(p.navyBodyFat(from: m) == nil)
    }

    /// Регрессия: процент жира показывался разными числами на двух экранах,
    /// потому что профиль хранил собственную копию обхватов. Теперь источник
    /// один, и результат зависит только от переданного замера.
    @Test func bodyFat_isTheSameNumberEverywhere() {
        let p = profile(heightCm: 180, sex: .male)
        let m = BodyMeasurement(date: Date())
        m.beltCm = 88
        m.neckCm = 40

        let direct = p.bodyFatPercentage(from: m)
        #expect(p.isNavyMethod(from: m))

        // То же значение, что уходит в отчёт о замерах
        let reported = BodyAnalysis.insights(measurement: m, profile: p)
            .first { $0.id == "bodyFat" }?.value
        #expect(reported == String(format: "%.1f%%", direct))

        // И то же, что берёт FFMI — он тоже считается от процента жира
        #expect(BodyAnalysis.ffmi(weightKg: p.weightKg, heightCm: p.heightCm,
                                  bodyFatPercent: direct) != nil)
    }

    @Test func bodyFat_fallsBackToBmiWithoutGirths() {
        let p = profile(sex: .male)
        let empty = BodyMeasurement(date: Date())
        #expect(!p.isNavyMethod(from: empty))
        #expect(!p.isNavyMethod(from: nil))
        // Дойренберг считается от ИМТ, поэтому замер на него не влияет вовсе
        #expect(p.bodyFatPercentage(from: empty) == p.bodyFatPercentage(from: nil))
        #expect(p.bodyFatPercentage(from: nil) > 0)
    }
}

// MARK: - Plan

struct PlanTests {

    private func plan(
        startWeightKg: Double = 80,
        targetWeightKg: Double = 75,
        durationWeeks: Int = 10,
        cyclingEnabled: Bool = false
    ) -> Plan {
        Plan(
            startDate: Date(),
            durationWeeks: durationWeeks,
            startWeightKg: startWeightKg,
            targetWeightKg: targetWeightKg,
            cyclingEnabled: cyclingEnabled
        )
    }

    // MARK: - Переход между фазами

    @Test func aRampMovesTheTargetGraduallyInsteadOfInOneStep() {
        let plan = chained([
            PlanPhase(intent: .cut, durationWeeks: 4, weeklyRatePercent: 0.7),
            PlanPhase(intent: .maintenance, durationWeeks: 4, rampWeeks: 2)
        ])
        let cal = Calendar.current
        let deficitTarget = plan.calorieTarget(for: cal.date(byAdding: .day, value: 3, to: plan.startDate)!, tdee: 2500)
        let firstDayOfRamp = plan.calorieTarget(for: cal.date(byAdding: .day, value: 28, to: plan.startDate)!, tdee: 2500)
        let middleOfRamp = plan.calorieTarget(for: cal.date(byAdding: .day, value: 35, to: plan.startDate)!, tdee: 2500)
        let afterRamp = plan.calorieTarget(for: cal.date(byAdding: .day, value: 45, to: plan.startDate)!, tdee: 2500)

        #expect(firstDayOfRamp == deficitTarget, "Первый день перехода — ещё прежняя норма")
        #expect(middleOfRamp > deficitTarget && middleOfRamp < afterRamp, "Середина перехода — между двумя нормами")
        #expect(afterRamp == 2500, "После перехода — норма поддержания")
    }

    @Test func withoutARampTheTargetJumpsOnTheFirstDay() {
        let plan = chained([
            PlanPhase(intent: .cut, durationWeeks: 4, weeklyRatePercent: 0.7),
            PlanPhase(intent: .maintenance, durationWeeks: 4)
        ])
        let firstDay = Calendar.current.date(byAdding: .day, value: 28, to: plan.startDate)!
        #expect(plan.calorieTarget(for: firstDay, tdee: 2500) == 2500)
    }

    @Test func onlyAnIncreaseInCaloriesCountsAsSettling() {
        let cal = Calendar.current
        let up = chained([
            PlanPhase(intent: .cut, durationWeeks: 4, weeklyRatePercent: 0.7),
            PlanPhase(intent: .maintenance, durationWeeks: 4)
        ])
        let down = chained([
            PlanPhase(intent: .maintenance, durationWeeks: 4),
            PlanPhase(intent: .cut, durationWeeks: 4, weeklyRatePercent: 0.7)
        ])
        let justAfter = { (p: Plan) in cal.date(byAdding: .day, value: 29, to: p.startDate)! }
        #expect(up.isSettling(on: justAfter(up)), "После подъёма калорий возвращается вода")
        #expect(!down.isSettling(on: justAfter(down)), "Уход в дефицит воду не возвращает")
        // Через три недели после перехода вода уже не оправдание.
        #expect(!up.isSettling(on: cal.date(byAdding: .day, value: 28 + 21, to: up.startDate)!))
    }

    @Test func aPhaseFromBeforeRampsDecodesWithoutOne() throws {
        let legacy = """
        {"intent": "cut", "durationWeeks": 8, "weeklyRatePercent": 0.7}
        """
        let phase = try JSONDecoder().decode(PlanPhase.self, from: Data(legacy.utf8))
        #expect(phase.rampWeeks == 0)
        #expect(phase.durationWeeks == 8)
    }

    @Test func aRampCannotOutlastItsOwnPhase() {
        let phase = PlanPhase(intent: .maintenance, durationWeeks: 2, rampWeeks: 8)
        #expect(phase.rampWeeks == 2)
    }

    // MARK: - Состав за фазу

    /// 77 кг, потеряно `lostKg`, из них жира `fatOfItKg`.
    private func composition(startKg: Double, deltaKg: Double, fatDeltaKg: Double) -> CompositionChange {
        let endKg = startKg + deltaKg
        let startFatKg = startKg * 0.20
        let endFatKg = startFatKg + fatDeltaKg
        return CompositionChange(
            fromDate: Date().addingTimeInterval(-60 * 86_400),
            toDate: Date(),
            startWeightKg: startKg,
            endWeightKg: endKg,
            startFatPercent: startFatKg / startKg * 100,
            endFatPercent: endFatKg / endKg * 100
        )
    }

    @Test func aBulkThatWentToFatIsNotCalledFine() {
        // Плюс три килограмма, и почти всё это жир. Прежний вердикт, не знавший
        // намерения, докладывал «сухая масса держится» — то есть что всё хорошо.
        let change = composition(startKg: 77, deltaKg: 3, fatDeltaKg: 2.8)
        #expect(change.verdict == .withinNoise, "Сама по себе сухая укладывается в погрешность")
        #expect(change.verdict(for: .bulk) == .costly, "Но для набора это провал")
        #expect(change.verdict(for: .cut) != .costly, "А тот же состав на сушке — другой разговор")
    }

    @Test func aCutThatKeptMuscleWorked() {
        let change = composition(startKg: 77, deltaKg: -4, fatDeltaKg: -3.8)
        #expect(change.verdict(for: .cut) == .worked)
    }

    @Test func aCutThatAteMuscleIsCostly() {
        // Сухой массы минус 3 кг при погрешности метода около 2.3 — это больше
        // того, что метод способен наврать.
        let change = composition(startKg: 77, deltaKg: -6, fatDeltaKg: -3)
        #expect(change.verdict(for: .cut) == .costly)
    }

    /// Настоящий случай с телефона: за диет-брейк вес +0.7 кг, жир −2.2,
    /// сухая +3.0. Приложение объявляло это «отработала дорого» — то есть
    /// называло худшим лучшее, что вообще может случиться.
    @Test func fatDownAndMuscleUpIsTheBestOutcome() {
        let change = composition(startKg: 76, deltaKg: 0.7, fatDeltaKg: -2.2)
        #expect(change.isRecomposition)
        #expect(change.verdict(for: .maintenance) == .recomposition)
        #expect(change.verdict(for: .cut) == .recomposition, "И на сушке это она же")
        #expect(change.verdict(for: .bulk) == .recomposition)
    }

    /// «Жиром — −302% изменения веса» — арифметически верная бессмыслица:
    /// вес вырос, а жира стало меньше, и доли тут нет никакой.
    @Test func thereIsNoFatShareWhenFatAndWeightWentOppositeWays() {
        let change = composition(startKg: 76, deltaKg: 0.7, fatDeltaKg: -2.2)
        #expect(change.fatShareOfChange == nil)

        // А когда они идут в одну сторону, доля осмысленна.
        let honest = composition(startKg: 76, deltaKg: -4, fatDeltaKg: -3)
        #expect(honest.fatShareOfChange != nil)
    }

    /// На поддержании важно не то, сдвинулся ли вес, а чем он сдвинулся:
    /// пара килограммов воды и гликогена — обычная неделя, набранный жир —
    /// разошедшаяся с расходом норма.
    @Test func maintenanceJudgesWhatTheWeightWasMadeOf() {
        let water = composition(startKg: 76, deltaKg: 1.2, fatDeltaKg: 0.1)
        #expect(water.verdict(for: .maintenance) == .worked)

        let fat = composition(startKg: 76, deltaKg: 3.5, fatDeltaKg: 3.4)
        #expect(fat.verdict(for: .maintenance) == .costly)
    }

    @Test func aWeightThatDidNotMoveIsStalledOnEitherSide() {
        let change = composition(startKg: 77, deltaKg: 0.2, fatDeltaKg: 0.1)
        #expect(change.verdict(for: .cut) == .stalled)
        #expect(change.verdict(for: .bulk) == .stalled)
        // На поддержании неподвижный вес — это и есть успех.
        #expect(change.verdict(for: .maintenance) == .worked)
    }

    @Test func maintenanceThatDriftedIsNotFine() {
        let change = composition(startKg: 77, deltaKg: 2.5, fatDeltaKg: 2.0)
        #expect(change.verdict(for: .maintenance) == .costly)
    }

    @Test func theShareGoingToFatIsUnknownWhileTheWeightStands() {
        #expect(composition(startKg: 77, deltaKg: 0.2, fatDeltaKg: 0.1).fatShareOfChange == nil)
        let moved = composition(startKg: 77, deltaKg: -4, fatDeltaKg: -3)
        #expect(abs((moved.fatShareOfChange ?? 0) - 0.75) < 0.001)
    }

    // MARK: - Фазы

    private func chained(_ phases: [PlanPhase], startWeightKg: Double = 80,
                         startingDaysAgo: Int = 0) -> Plan {
        let start = Calendar.current.date(byAdding: .day, value: -startingDaysAgo, to: Date())!
        return Plan(startDate: start, startWeightKg: startWeightKg, phases: phases)
    }

    @Test func aPlanFromBeforePhasesBecomesOnePhaseWithTheSameNumbers() throws {
        // План хранится в UserDefaults как JSON. Если он перестанет
        // декодироваться, у человека с активной сушкой она просто исчезнет.
        let legacy = """
        {"startDate": 760000000, "durationWeeks": 10, "startWeightKg": 80,
         "targetWeightKg": 75, "cyclingEnabled": false, "weekendStyle": "satSun"}
        """
        let plan = try JSONDecoder().decode(Plan.self, from: Data(legacy.utf8))
        #expect(plan.phases.count == 1)
        #expect(plan.phases[0].intent == .cut)
        #expect(plan.durationWeeks == 10)
        // Целевой вес теперь выводится из темпа, а не хранится, — и обязан
        // совпасть со старым до килограмма, иначе цель у человека «поедет».
        #expect(abs(plan.targetWeightKg - 75) < 0.001)
        #expect(abs(plan.weeklyRateKg - (-0.5)) < 0.001)
    }

    @Test func encodingKeepsTheOldFieldsReadable() throws {
        let plan = chained([PlanPhase(intent: .cut, durationWeeks: 10, weeklyRatePercent: 0.625)])
        let json = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(plan)) as! [String: Any]
        #expect(json["phases"] != nil)
        // Старые поля остаются в файле ради глазами читаемой резервной копии.
        #expect(json["durationWeeks"] as? Int == 10)
        #expect(abs((json["targetWeightKg"] as? Double ?? 0) - 75) < 0.01)
    }

    @Test func theChainDecidesWhereTheWeightEndsUp() {
        // Сушка, выход в поддержание, набор: поддержание вес не двигает,
        // а набор считается уже от того, сколько осталось после сушки.
        let plan = chained([
            PlanPhase(intent: .cut, durationWeeks: 10, weeklyRatePercent: 0.5),
            PlanPhase(intent: .maintenance, durationWeeks: 4),
            PlanPhase(intent: .bulk, durationWeeks: 10, weeklyRatePercent: 0.3)
        ])
        let afterCut = 80 - 80 * 0.005 * 10
        #expect(abs(plan.weight(atStartOfPhaseAt: 1) - afterCut) < 0.001)
        #expect(abs(plan.weight(atStartOfPhaseAt: 2) - afterCut) < 0.001)
        #expect(abs(plan.targetWeightKg - (afterCut + afterCut * 0.003 * 10)) < 0.001)
        #expect(plan.durationWeeks == 24)
    }

    @Test func theRateIsAShareOfTheWeightAtThePhaseStartNotThePlanStart() {
        let plan = chained([
            PlanPhase(intent: .cut, durationWeeks: 10, weeklyRatePercent: 1.0),
            PlanPhase(intent: .cut, durationWeeks: 10, weeklyRatePercent: 1.0)
        ])
        let afterFirst = 80 - 80 * 0.01 * 10  // 72
        // Тот же процент даёт меньше килограммов, когда человек стал легче, —
        // ради этого темп и задан процентом, а не килограммами.
        let secondPhaseWeekly = plan.weeklyRateKg(on: Calendar.current.date(byAdding: .day, value: 11 * 7, to: plan.startDate)!)
        #expect(abs(secondPhaseWeekly - (-afterFirst * 0.01)) < 0.001)
    }

    @Test func theDayTakesItsTargetFromThePhaseItFallsIn() {
        let plan = chained([
            PlanPhase(intent: .cut, durationWeeks: 4, weeklyRatePercent: 0.7),
            PlanPhase(intent: .maintenance, durationWeeks: 4)
        ])
        let cal = Calendar.current
        let inCut = cal.date(byAdding: .day, value: 3, to: plan.startDate)!
        let inMaintenance = cal.date(byAdding: .day, value: 5 * 7, to: plan.startDate)!
        #expect(plan.calorieTarget(for: inCut, tdee: 2500) < 2500)
        // Поддержание — это ровно TDEE, а не «дефицит поменьше».
        #expect(plan.calorieTarget(for: inMaintenance, tdee: 2500) == 2500)
    }

    @Test func aDateOutsideThePlanBelongsToNoPhase() {
        let plan = chained([PlanPhase(intent: .cut, durationWeeks: 2, weeklyRatePercent: 0.5)])
        let after = Calendar.current.date(byAdding: .day, value: 30, to: plan.startDate)!
        #expect(plan.phaseIndex(on: after) == nil)
        #expect(plan.phaseIndex(on: Calendar.current.date(byAdding: .day, value: -1, to: plan.startDate)!) == nil)
    }

    @Test func retargetingChangesTheRateOfTheLastPhaseAndNothingElse() {
        let plan = chained([
            PlanPhase(intent: .cut, durationWeeks: 10, weeklyRatePercent: 0.5),
            PlanPhase(intent: .cut, durationWeeks: 10, weeklyRatePercent: 0.5)
        ])
        let updated = plan.retargeted(to: 70)
        #expect(updated.phases[0] == plan.phases[0], "Прошедшие фазы трогать нельзя")
        #expect(updated.durationWeeks == plan.durationWeeks, "Срок не менялся — менялась цель")
        #expect(abs(updated.targetWeightKg - 70) < 0.001)
    }

    @Test func aChainOfDifferentIntentsIsNotCalledLossOrGain() {
        let mixed = chained([
            PlanPhase(intent: .cut, durationWeeks: 8, weeklyRatePercent: 0.7),
            PlanPhase(intent: .bulk, durationWeeks: 8, weeklyRatePercent: 0.3)
        ])
        let onlyCut = chained([PlanPhase(intent: .cut, durationWeeks: 8, weeklyRatePercent: 0.7)])
        let onlyBulk = chained([PlanPhase(intent: .bulk, durationWeeks: 8, weeklyRatePercent: 0.3)])
        // Сравниваем строки между собой, а не с русским текстом: тесты идут
        // на английской локали, и литерал здесь проверял бы перевод, а не логику.
        #expect(mixed.title != onlyCut.title)
        #expect(mixed.title != onlyBulk.title)
        #expect(onlyCut.title != onlyBulk.title)
    }

    @Test func anAggressivePhaseIsJudgedByItsOwnIntent() {
        // 0.8% в неделю — рабочий дефицит и набор, где большая часть прибавки
        // будет жиром. Один порог на оба был бы невнимательностью.
        let cut = PlanPhase(intent: .cut, durationWeeks: 8, weeklyRatePercent: 0.8)
        let bulk = PlanPhase(intent: .bulk, durationWeeks: 8, weeklyRatePercent: 0.8)
        #expect(!cut.isAggressive)
        #expect(bulk.isAggressive)
    }

    @Test func anIntentDecidesTheSignSoARateCannotContradictIt() {
        let phase = PlanPhase(intent: .cut, durationWeeks: 8, weeklyRatePercent: -0.7)
        #expect(phase.weeklyRatePercent == 0.7)
        #expect(phase.weeklyRateKg(fromWeightKg: 80) < 0)
    }

    @Test func weeklyRate_loss() {
        let p = plan(startWeightKg: 80, targetWeightKg: 75, durationWeeks: 10)
        #expect(abs(p.weeklyRateKg - (-0.5)) < 0.01)
    }

    @Test func weeklyRate_gain() {
        let p = plan(startWeightKg: 70, targetWeightKg: 75, durationWeeks: 10)
        #expect(abs(p.weeklyRateKg - 0.5) < 0.01)
    }

    @Test func totalWeightChange_negative() {
        let p = plan(startWeightKg: 80, targetWeightKg: 75)
        #expect(abs(p.totalWeightChangeKg - (-5)) < 0.01)
    }

    @Test func dailyCalorieTarget_belowTdee_forDeficit() {
        let p = plan(startWeightKg: 80, targetWeightKg: 75, durationWeeks: 10)
        let target = p.dailyCalorieTarget(tdee: 2500)
        #expect(target < 2500)
        #expect(target > 0)
    }

    @Test func isAggressivePace_true() {
        let p = plan(startWeightKg: 80, targetWeightKg: 70, durationWeeks: 4)
        #expect(p.isAggressivePace(relativeToWeightKg: 80))
    }

    @Test func isAggressivePace_false() {
        let p = plan(startWeightKg: 80, targetWeightKg: 78, durationWeeks: 10)
        #expect(!p.isAggressivePace(relativeToWeightKg: 80))
    }

    @Test func cyclingTarget_equalsBaseWhenDisabled() {
        let p = plan(cyclingEnabled: false)
        let base = p.dailyCalorieTarget(tdee: 2500)
        let onDate = p.calorieTarget(for: Date(), tdee: 2500)
        #expect(onDate == base)
    }

    @Test func cyclingTarget_differsAcrossDaysWhenEnabled() {
        let p = plan(cyclingEnabled: true)
        let breakdown = p.weeklyCalorieBreakdown(tdee: 2500)
        let calories = breakdown.map(\.calories)
        #expect(Set(calories).count > 1)
    }
}
