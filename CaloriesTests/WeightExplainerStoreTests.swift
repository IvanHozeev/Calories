import Testing
import Foundation
import SwiftData
@testable import Calories

/// Объяснитель веса на данных дневника: решения владельца от 13.11.
@MainActor
@Suite(.serialized)
struct WeightExplainerStoreTests {
    private let container: ModelContainer
    private let store: CalorieStore
    private let calendar = Calendar.current

    init() throws {
        container = try ModelContainer(
            for: FoodEntry.self, FoodItem.self, WeightEntry.self, GoalRecord.self, Dish.self,
            BodyMeasurement.self, FastDay.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        store = CalorieStore(context: container.mainContext,
                             defaults: TestDefaults.make(), groupDefaults: nil)
    }

    private func at(_ hour: Int, _ minute: Int = 0, daysAgo: Int) -> Date {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: Date()))!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    /// Две недели ровного веса 80 и ровной еды: 200 г углеводов в 13:00.
    private func seedSteadyFortnight() {
        for daysAgo in 1...40 {
            store.addWeight(80, date: at(7, daysAgo: daysAgo))
            store.add(name: "Обед", calories: 2000, macros: Macros(protein: 100, fat: 60, carbs: 200),
                      date: at(13, daysAgo: daysAgo))
        }
    }

    /// Вес — первое взвешивание за день: вечернее после ужина не в счёт.
    @Test func theFirstWeighingOfTheDayCounts() throws {
        seedSteadyFortnight()
        store.addWeight(81, date: at(7, daysAgo: 0))
        store.addWeight(82.5, date: at(21, daysAgo: 0))
        let today = try #require(store.weightExplainerInput().today)
        #expect(abs(today.residualKg - 1.0) < 0.001)
    }

    /// Поздний ужин — ближе чем за три часа до отбоя из расписания.
    @Test func aLateMealIsCountedFromBedtime() throws {
        seedSteadyFortnight()
        store.add(name: "Ужин", calories: 500, date: at(22, 30, daysAgo: 1))
        store.addWeight(81, date: at(7, daysAgo: 0))
        let bedtime = at(23, 30, daysAgo: 0)
        let today = try #require(store.weightExplainerInput(sleep: bedtime).today)
        #expect(abs(today.lateHours - 2.0) < 0.001)
        let earlyBed = at(21, 0, daysAgo: 0)
        #expect(abs((store.weightExplainerInput(sleep: earlyBed).today?.lateHours ?? 0) - 4.5) < 0.001)
    }

    /// Углеводы — против личного среднего, а не против нормы.
    @Test func carbsAreComparedWithThePersonalMean() throws {
        seedSteadyFortnight()
        store.add(name: "Паста", calories: 600, macros: Macros(protein: 20, fat: 10, carbs: 150),
                  date: at(14, daysAgo: 1))
        store.addWeight(81, date: at(7, daysAgo: 0))
        let today = try #require(store.weightExplainerInput().today)
        #expect(abs(today.carbsDeltaG - 150) < 0.001)
    }

    /// Строка говорит «похоже на воду» и не говорит про жир.
    @Test func theHintTalksAboutWaterNotFat() {
        let explanation = WeightExplainer.Explanation(
            residualKg: 0.8, contributions: [.init(factor: .carbs, kg: 0.6), .init(factor: .lateMeal, kg: 0.2)])
        let hint = DayHint.weight(explanation, now: Date()).first
        #expect(hint?.source == .weightExplainer)
        #expect(hint?.urgency == 80)
        #expect(hint?.action == nil)
        #expect(hint?.title.lowercased().contains("fat") == false)
        #expect(hint?.title.contains("+0.8") == true || hint?.title.contains("+0,8") == true)
    }
}
