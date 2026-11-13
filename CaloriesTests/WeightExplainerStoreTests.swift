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

    /// История, где вес следует за вчерашними углеводами: 0,004 кг на грамм.
    private func seedCarbSensitiveHistory() {
        let deltas: [Double] = (0..<45).map { Double(($0 * 37) % 300) - 150 }   // от −150 до +150, без случайности
        for daysAgo in stride(from: 45, through: 1, by: -1) {
            let delta = deltas[daysAgo - 1]
            store.add(name: "Еда", calories: 2000, macros: Macros(protein: 100, fat: 60, carbs: 200 + delta),
                      date: at(13, daysAgo: daysAgo))
        }
        for daysAgo in stride(from: 44, through: 0, by: -1) {
            let yesterdayDelta = deltas[daysAgo]       // день daysAgo+1
            store.addWeight(80 + 0.004 * yesterdayDelta, date: at(7, daysAgo: daysAgo))
        }
    }

    /// Днём прогноза нет: еда ещё не съедена.
    @Test func noForecastDuringTheDay() {
        seedCarbSensitiveHistory()
        store.add(name: "Паста", calories: 900, macros: Macros(protein: 30, fat: 20, carbs: 350), date: at(12, daysAgo: 0))
        #expect(store.weightForecast(now: at(14, daysAgo: 0), sleep: at(23, daysAgo: 0)) == nil)
    }

    /// Вечером, за три часа до отбоя, — прогноз по съеденному сегодня.
    @Test func anEveningForecastFollowsTodaysCarbs() throws {
        seedCarbSensitiveHistory()
        store.add(name: "Паста", calories: 900, macros: Macros(protein: 30, fat: 20, carbs: 350), date: at(12, daysAgo: 0))
        let result = try #require(store.weightForecast(now: at(20, 30, daysAgo: 0), sleep: at(23, daysAgo: 0)))
        #expect(result.forecast.residualKg > 0.4)
        #expect(result.forecast.contributions.first?.factor == .carbs)
        #expect(abs(result.trendKg - 80) < 0.5)
    }

    /// Строка говорит про воду и называет ожидаемый вес.
    @Test func theForecastHintNamesTheWeightAndWater() {
        let forecast = WeightExplainer.Forecast(residualKg: 0.6, contributions: [.init(factor: .carbs, kg: 0.6)])
        let hint = DayHint.forecast(forecast, trendKg: 80.3, now: Date()).first
        #expect(hint?.urgency == DayHint.Urgency.weightForecast)
        #expect(hint?.title.contains("80.9") == true || hint?.title.contains("80,9") == true)
        #expect(hint?.title.lowercased().contains("fat") == false)
    }
}
