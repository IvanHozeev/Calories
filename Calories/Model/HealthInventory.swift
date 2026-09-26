@preconcurrency import HealthKit
import Foundation
import Observation

/// Что вообще лежит в «Здоровье» и от кого.
///
/// Браслеты обещают на коробке многое, а в Apple Health доезжает не всё и не
/// каждый день: у одного пишется сон и молчит вариабельность, у другого
/// наоборот, у третьего данные приходят пачками с опозданием на сутки. Строить
/// на этом расчёты вслепую — значит нарисовать карточку, которая у половины
/// людей окажется пустой.
///
/// Поэтому сначала разведка: этот отчёт показывает по каждому виду данных,
/// сколько дней из последних тридцати он покрывает, когда был последний раз и
/// кто его пишет. Экран отладочный, но сам отчёт — обычный код: он же
/// понадобится, чтобы решать, показывать ли человеку карточку состояния.
@Observable
@MainActor
final class HealthInventory {
    struct Row: Identifiable {
        let id: String
        /// Как называть человеку: «Сон», «Пульс в покое».
        let title: String
        /// Сколько дней из окна покрыто данными.
        let days: Int
        /// Последний день с данными.
        let latest: Date?
        /// Пример значения — чтобы видеть не только «есть», но и «похоже на правду».
        let sample: String?
        /// Кто пишет: имена источников.
        let sources: [String]
    }

    /// Сколько дней назад смотрим.
    static let window = 30

    private let healthStore = HKHealthStore()
    private(set) var rows: [Row] = []
    private(set) var isChecking = false
    private(set) var failure: String?

    /// Все виды данных, которые нам интересны, в порядке полезности.
    private var probes: [(id: String, title: String)] {
        [
            ("steps", String(localized: "Шаги")),
            ("activeEnergy", String(localized: "Активные калории")),
            ("workouts", String(localized: "Тренировки")),
            ("restingHeartRate", String(localized: "Пульс в покое")),
            ("sleep", String(localized: "Сон")),
            ("hrv", String(localized: "Вариабельность пульса")),
            ("bodyFat", String(localized: "Процент жира"))
        ]
    }

    private static let readTypes: Set<HKObjectType> = [
        HKQuantityType(.stepCount),
        HKQuantityType(.activeEnergyBurned),
        HKQuantityType(.restingHeartRate),
        HKQuantityType(.heartRateVariabilitySDNN),
        HKQuantityType(.bodyFatPercentage),
        HKCategoryType(.sleepAnalysis),
        HKObjectType.workoutType()
    ]

    func check() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            failure = String(localized: "«Здоровье» на этом устройстве недоступно")
            return
        }
        isChecking = true
        failure = nil
        defer { isChecking = false }
        do {
            try await healthStore.requestAuthorization(toShare: [], read: Self.readTypes)
        } catch {
            failure = error.localizedDescription
            return
        }
        let start = Calendar.current.date(byAdding: .day, value: -Self.window, to: Date()) ?? Date()
        var found: [Row] = []
        for probe in probes {
            found.append(await row(for: probe.id, title: probe.title, since: start))
        }
        rows = found
    }

    private func row(for id: String, title: String, since start: Date) async -> Row {
        let samples: [HKSample]
        switch id {
        case "steps":            samples = await fetch(HKQuantityType(.stepCount), since: start)
        case "activeEnergy":     samples = await fetch(HKQuantityType(.activeEnergyBurned), since: start)
        case "restingHeartRate": samples = await fetch(HKQuantityType(.restingHeartRate), since: start)
        case "hrv":              samples = await fetch(HKQuantityType(.heartRateVariabilitySDNN), since: start)
        case "bodyFat":          samples = await fetch(HKQuantityType(.bodyFatPercentage), since: start)
        case "sleep":            samples = await fetch(HKCategoryType(.sleepAnalysis), since: start)
        default:                 samples = await fetch(HKObjectType.workoutType(), since: start)
        }
        let calendar = Calendar.current
        let days = Set(samples.map { calendar.startOfDay(for: $0.startDate) }).count
        let sources = Array(Set(samples.map(\.sourceRevision.source.name))).sorted()
        return Row(id: id, title: title, days: days,
                   latest: samples.map(\.startDate).max(),
                   sample: Self.sample(from: samples), sources: sources)
    }

    private func fetch(_ type: HKSampleType, since start: Date) async -> [HKSample] {
        await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: HKQuery.predicateForSamples(withStart: start, end: Date()),
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, samples, _ in
                continuation.resume(returning: samples ?? [])
            }
            healthStore.execute(query)
        }
    }

    /// Пример последнего значения человеческими словами.
    private static func sample(from samples: [HKSample]) -> String? {
        guard let last = samples.first else { return nil }
        if let workout = last as? HKWorkout {
            let minutes = Int((workout.duration / 60).rounded())
            return String(format: String(localized: "%lld мин"), minutes)
        }
        if let quantity = last as? HKQuantitySample {
            if quantity.quantityType == HKQuantityType(.restingHeartRate) {
                return String(format: String(localized: "%lld уд/мин"),
                              Int(quantity.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))))
            }
            if quantity.quantityType == HKQuantityType(.heartRateVariabilitySDNN) {
                return String(format: String(localized: "%lld мс"),
                              Int(quantity.quantity.doubleValue(for: .secondUnit(with: .milli))))
            }
            if quantity.quantityType == HKQuantityType(.bodyFatPercentage) {
                return String(format: String(localized: "%lld%%"),
                              Int((quantity.quantity.doubleValue(for: .percent()) * 100).rounded()))
            }
        }
        if let category = last as? HKCategorySample {
            let hours = category.endDate.timeIntervalSince(category.startDate) / 3600
            return String(format: String(localized: "%@ ч"), String(format: "%.1f", hours))
        }
        return nil
    }

    /// Насколько этому виду данных можно доверять как ежедневному.
    ///
    /// Не украшение: по этому же правилу решается, строить ли на данных
    /// расчёт. Две трети окна — примерно та плотность, при которой среднее
    /// перестаёт зависеть от того, синхронизировался браслет вчера или нет.
    static func isDense(days: Int, window: Int = window) -> Bool {
        Double(days) >= Double(window) * 2 / 3
    }
}
