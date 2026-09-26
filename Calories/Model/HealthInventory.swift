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
        /// Данные посуточные: у времени в `latest` смысла нет, это начало суток.
        var isDaily: Bool = false
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
            ("heartRate", String(localized: "Пульс")),
            ("sleep", String(localized: "Сон")),
            ("hrv", String(localized: "Вариабельность пульса")),
            ("weight", String(localized: "Вес")),
            ("bodyFat", String(localized: "Процент жира"))
        ]
    }

    private static let readTypes: Set<HKObjectType> = [
        HKQuantityType(.stepCount),
        HKQuantityType(.activeEnergyBurned),
        HKQuantityType(.restingHeartRate),
        HKQuantityType(.heartRate),
        HKQuantityType(.bodyMass),
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
        // Ровно столько суток, сколько обещано: окно начинается с начала дня,
        // иначе суточных корзин выходит на одну больше, чем дней в окне, и
        // отчёт показывает «31 / 30».
        let today = Calendar.current.startOfDay(for: Date())
        let start = Calendar.current.date(byAdding: .day, value: -(Self.window - 1), to: today) ?? today
        var found: [Row] = []
        for probe in probes {
            found.append(await row(for: probe.id, title: probe.title, since: start))
        }
        rows = found
    }

    private func row(for id: String, title: String, since start: Date) async -> Row {
        // Пульс браслет пишет непрерывно — за месяц это десятки тысяч проб, и
        // тащить их в память ради одного «есть или нет» незачем. Числовые
        // величины считаем посуточной статистикой, а пробы читаем только там,
        // где иначе нельзя: у сна и тренировок важна длительность каждой.
        switch id {
        case "steps":
            return await quantityRow(id, title, HKQuantityType(.stepCount), .cumulativeSum,
                                     unit: .count(), format: { String(format: String(localized: "%lld шагов"), Int($0)) }, since: start)
        case "activeEnergy":
            return await quantityRow(id, title, HKQuantityType(.activeEnergyBurned), .cumulativeSum,
                                     unit: .kilocalorie(), format: { String(format: String(localized: "%lld ккал"), Int($0)) }, since: start)
        case "restingHeartRate", "heartRate":
            let type = id == "heartRate" ? HKQuantityType(.heartRate) : HKQuantityType(.restingHeartRate)
            return await quantityRow(id, title, type, .discreteAverage,
                                     unit: HKUnit.count().unitDivided(by: .minute()),
                                     format: { String(format: String(localized: "%lld уд/мин"), Int($0)) }, since: start)
        case "hrv":
            return await quantityRow(id, title, HKQuantityType(.heartRateVariabilitySDNN), .discreteAverage,
                                     unit: .secondUnit(with: .milli),
                                     format: { String(format: String(localized: "%lld мс"), Int($0)) }, since: start)
        case "weight":
            return await quantityRow(id, title, HKQuantityType(.bodyMass), .discreteAverage,
                                     unit: .gramUnit(with: .kilo),
                                     format: { String(format: String(localized: "%@ кг"), String(format: "%.1f", $0)) }, since: start)
        case "bodyFat":
            return await quantityRow(id, title, HKQuantityType(.bodyFatPercentage), .discreteAverage,
                                     unit: .percent(),
                                     format: { String(format: String(localized: "%lld%%"), Int(($0 * 100).rounded())) }, since: start)
        default:
            let type: HKSampleType = id == "sleep" ? HKCategoryType(.sleepAnalysis) : HKObjectType.workoutType()
            let samples = await fetch(type, since: start)
            let calendar = Calendar.current
            return Row(id: id, title: title,
                       days: Set(samples.map { calendar.startOfDay(for: $0.startDate) }).count,
                       latest: samples.map(\.startDate).max(),
                       sample: Self.sample(from: samples),
                       sources: Array(Set(samples.map(\.sourceRevision.source.name))).sorted())
        }
    }

    /// Строка отчёта по числовой величине: посуточная статистика за окно.
    private func quantityRow(_ id: String, _ title: String, _ type: HKQuantityType,
                             _ options: HKStatisticsOptions, unit: HKUnit,
                             format: @escaping (Double) -> String, since start: Date) async -> Row {
        let calendar = Calendar.current
        let anchor = calendar.startOfDay(for: start)
        var interval = DateComponents()
        interval.day = 1
        let collection: HKStatisticsCollection? = await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: HKQuery.predicateForSamples(withStart: start, end: Date()),
                // Без разделения по источникам HealthKit не заполняет `sources`
                // вовсе, и отчёт отвечал «никто не пишет» при живых данных.
                options: options.union(.separateBySource),
                anchorDate: anchor,
                intervalComponents: interval
            )
            query.initialResultsHandler = { _, results, _ in continuation.resume(returning: results) }
            healthStore.execute(query)
        }
        var days = 0
        var latest: Date?
        var latestValue: Double?
        var sources: Set<String> = []
        collection?.enumerateStatistics(from: start, to: Date()) { stats, _ in
            let quantity = options == .cumulativeSum ? stats.sumQuantity() : stats.averageQuantity()
            guard let quantity else { return }
            days += 1
            latest = stats.startDate
            latestValue = quantity.doubleValue(for: unit)
            for source in stats.sources ?? [] { sources.insert(source.name) }
        }
        return Row(id: id, title: title, days: days, latest: latest,
                   isDaily: true, sample: latestValue.map(format), sources: sources.sorted())
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
