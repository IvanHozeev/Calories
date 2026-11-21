import Testing
import Foundation
@testable import Calories

/// Предложение на финише онбординга и на экране Premium собирается из
/// ответов: о какой боли говорить и что из этого должно оказаться в плане.
///
/// Текст не сравниваем — набор идёт на английской локали. Сравниваем, какие
/// строки-выгоды и в каком порядке, и что ответы сделали с планом.
@Suite
struct OfferTests {
    private func kinds(_ offer: Offer) -> [OfferBenefit.Kind] { offer.benefits.map(\.kind) }

    @Test func eachObstacleLeadsWithItsOwnBenefit() {
        let leads: [(PastObstacle, OfferBenefit.Kind)] = [
            (.rebound, .keep), (.binges, .noBinges), (.noResult, .works),
            (.lostStrength, .muscle), (.firstTime, .finish),
        ]
        for (obstacle, lead) in leads {
            let offer = Offer.make(intent: .cut,
                                   answers: OfferAnswers(training: .none, obstacle: obstacle),
                                   observesTradition: false)
            #expect(kinds(offer).first == lead, "\(obstacle) должен начинаться с \(lead)")
        }
    }

    @Test func differentPainsGetDifferentHeadlines() {
        let headlines = Set(PastObstacle.allCases.map {
            Offer.make(intent: .cut, answers: OfferAnswers(training: .none, obstacle: $0),
                       observesTradition: false).headline
        })
        #expect(headlines.count == PastObstacle.allCases.count)
    }

    /// Без ответов — общее предложение, то же, что видели все до опроса.
    @Test func withoutAnswersTheOfferIsTheGeneralOne() {
        let offer = Offer.make(intent: nil, answers: nil, observesTradition: false)
        #expect(kinds(offer) == [.finish, .keep, .works, .expenditure, .noBinges])
    }

    @Test func gymGoersHearAboutStrengthWhateverTheirPain() {
        let offer = Offer.make(intent: .cut,
                               answers: OfferAnswers(training: .regular, obstacle: .binges),
                               observesTradition: false)
        #expect(kinds(offer).prefix(2) == [.noBinges, .muscle])

        let firstTimer = Offer.make(intent: .cut,
                                    answers: OfferAnswers(training: .regular, obstacle: .firstTime),
                                    observesTradition: false)
        #expect(kinds(firstTimer).first == .muscle)
    }

    @Test func kosherIsTheThirdLineForThoseWhoObserve() {
        let offer = Offer.make(intent: .cut,
                               answers: OfferAnswers(training: .none, obstacle: .rebound),
                               observesTradition: true)
        #expect(kinds(offer)[2] == .kosher)
        let without = Offer.make(intent: .cut,
                                 answers: OfferAnswers(training: .none, obstacle: .rebound),
                                 observesTradition: false)
        #expect(!kinds(without).contains(.kosher))
    }

    @Test func bulkAndMaintenanceHaveTheirOwnOffers() {
        let bulk = Offer.make(intent: .bulk, answers: OfferAnswers(training: .regular, obstacle: nil),
                              observesTradition: false)
        #expect(kinds(bulk).first == .leanBulk)
        #expect(!kinds(bulk).contains(.keep))
        let hold = Offer.make(intent: .maintenance, answers: nil, observesTradition: false)
        #expect(kinds(hold).first == .steadyWeight)
    }

    // MARK: - Что ответы делают с планом

    @Test func gymAndLostStrengthMeanMoreProteinAndAGentlerPace() {
        let couch = OfferAnswers(training: .none, obstacle: .firstTime)
        let gym = OfferAnswers(training: .regular, obstacle: .firstTime)
        let weakened = OfferAnswers(training: .sometimes, obstacle: .lostStrength)
        #expect(couch.proteinPerKg == UserProfile.defaultProteinPerKg)
        #expect(gym.proteinPerKg > couch.proteinPerKg)
        #expect(weakened.proteinPerKg > gym.proteinPerKg)
        #expect(couch.cutRatePercent == PlanIntent.cut.defaultWeeklyRatePercent)
        #expect(gym.cutRatePercent < couch.cutRatePercent)
        #expect(weakened.cutRatePercent < couch.cutRatePercent)
    }

    @Test func bingesTurnOnTheCalorieCycle() {
        #expect(OfferAnswers(training: .none, obstacle: .binges).wantsCycling)
        #expect(!OfferAnswers(training: .none, obstacle: .rebound).wantsCycling)
    }

    /// Обещали «удержать» — удержание в плане есть, и тому, у кого вес
    /// возвращался, выход из дефицита длиннее.
    @Test func aCutComesWithMaintenanceAfterIt() {
        let phases = OfferAnswers(training: .none, obstacle: .firstTime)
            .cutPhases(durationWeeks: 12, ratePercent: 0.7, dietBreakEvery: 4)
        #expect(phases.map(\.intent) == [.cut, .maintenance])
        #expect(phases[1].durationWeeks == PhaseAdvice.restWeeks(afterCutOf: 12))
        #expect(phases[0].dietBreakEvery == 4)

        let rebound = OfferAnswers(training: .none, obstacle: .rebound)
            .cutPhases(durationWeeks: 12, ratePercent: 0.7, dietBreakEvery: nil)
        #expect(rebound[1].rampWeeks > phases[1].rampWeeks)
    }

    /// «К какому дню» — день, когда вес приходит к цели, а не конец удержания.
    @Test func theRouteDateIsWhenTheWeightArrivesNotWhenTheHoldEnds() {
        let start = Calendar.current.startOfDay(for: Date())
        let plan = Plan(startDate: start, startWeightKg: 80,
                        phases: OfferAnswers(training: .none, obstacle: .firstTime)
                            .cutPhases(durationWeeks: 8, ratePercent: 0.7, dietBreakEvery: nil))
        let expected = Calendar.current.date(byAdding: .day, value: 8 * 7, to: start)!
        #expect(plan.targetReachedDate == expected)
        #expect(plan.holdWeeksAfterTarget == PhaseAdvice.restWeeks(afterCutOf: 8))
        #expect(plan.endDate > plan.targetReachedDate)
    }

    @Test func answersSurviveARelaunch() {
        let defaults = UserDefaults(suiteName: "OfferTests-\(UUID())")!
        #expect(OfferAnswers.load(from: defaults) == nil)
        let answers = OfferAnswers(training: .regular, obstacle: .rebound)
        answers.save(to: defaults)
        #expect(OfferAnswers.load(from: defaults) == answers)
    }
}
