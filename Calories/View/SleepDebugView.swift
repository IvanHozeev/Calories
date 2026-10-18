#if DEBUG
import SwiftUI
import HealthKit

/// Что «Здоровье» на самом деле отдаёт про сон.
///
/// Экран появился, потому что приложение назвало ночь в 3.6 часа там, где
/// человек спал 6.5, и починить это вслепую нельзя: причин у недобора три, и
/// они требуют разных правок. Либо источник пишет часть ночи фазами, а часть
/// «в постели», и мы берём только фазы. Либо ночь разваливается на куски с
/// разрывом больше трёх часов, и до дня доходит только последний. Либо
/// источников несколько и они спорят друг с другом.
///
/// Поэтому здесь показано сырьё: каждая запись как есть — тип, источник,
/// начало, конец, — и рядом то, что из неё собрало приложение. Разница видна
/// глазами за секунду.
struct SleepDebugView: View {
    private let healthStore = HKHealthStore()

    @State private var records: [Record] = []
    @State private var nights: [SleepNight] = []
    @State private var loading = true

    struct Record: Identifiable {
        let id = UUID()
        let kind: String
        let source: String
        let start: Date
        let end: Date
        var hours: Double { end.timeIntervalSince(start) / 3600 }
        /// Идёт ли запись в счёт сна, или это «в постели» и «не сплю».
        let counted: Bool
    }

    var body: some View {
        List {
            if loading {
                Section { ProgressView() }
            }

            Section {
                if nights.isEmpty {
                    Text("Ночей не собралось")
                        .font(.app(.footnote))
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(nights.enumerated()), id: \.offset) { _, night in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: String(format: "%.2f ч", night.hours))
                            .font(.app(.headline))
                            .monospacedDigit()
                        Text(verbatim: "\(time(night.bed)) → \(time(night.wake))")
                            .font(.app(.caption))
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Что посчитало приложение")
            } footer: {
                Text("Отрезки склеиваются в одну ночь, пока разрыв между ними не больше трёх часов. Ночь короче трёх часов отбрасывается как дрёма.")
            }

            Section {
                ForEach(records) { record in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(verbatim: record.kind)
                                .font(.app(.subheadline, weight: .semibold))
                                .foregroundStyle(record.counted ? Color.primary : .secondary)
                            Spacer()
                            Text(verbatim: String(format: "%.2f ч", record.hours))
                                .font(.app(.subheadline))
                                .monospacedDigit()
                                .foregroundStyle(record.counted ? Color.primary : .secondary)
                        }
                        Text(verbatim: "\(day(record.start)) \(time(record.start)) → \(time(record.end))")
                            .font(.app(.caption))
                            .foregroundStyle(.secondary)
                        Text(verbatim: record.source)
                            .font(.app(.caption2))
                            .foregroundStyle(.tertiary)
                    }
                }
            } header: {
                Text("Что отдало «Здоровье»")
            } footer: {
                Text("Серым — записи, которые в счёт сна не идут: «в постели» при наличии фаз и «не сплю». Две последние ночи, от свежей к старой.")
            }
        }
        .glassRow()
        .listStyle(.insetGrouped)
        .screenTitle(String(localized: "Сон: что пришло"))
        .task { await load() }
    }

    private func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    private func day(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated))
    }

    private func load() async {
        let start = Calendar.current.date(byAdding: .day, value: -2, to: Date()) ?? Date()
        let samples: [HKCategorySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKCategoryType(.sleepAnalysis),
                predicate: HKQuery.predicateForSamples(withStart: start, end: Date()),
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKCategorySample]) ?? [])
            }
            healthStore.execute(query)
        }

        let asleep = samples.filter { StepStore.asleepValues.contains($0.value) }
        let inBed = samples.filter { $0.value == HKCategoryValueSleepAnalysis.inBed.rawValue }
        // Ровно тот же отбор, что в приложении: иначе экран показывал бы не то,
        // на что приложение смотрит, и диагностика врала бы вместе с ним.
        let counted = Set((asleep.isEmpty ? inBed : asleep).map(\.uuid))

        records = samples.map {
            Record(kind: Self.name(for: $0.value),
                   source: $0.sourceRevision.source.name,
                   start: $0.startDate, end: $0.endDate,
                   counted: counted.contains($0.uuid))
        }
        nights = SleepAnalysis.nights(from: SleepAnalysis.segments(
            asleep: asleep.map { SleepAnalysis.Segment(start: $0.startDate, end: $0.endDate) },
            inBed: inBed.map { SleepAnalysis.Segment(start: $0.startDate, end: $0.endDate) }))
        loading = false
    }

    private static func name(for value: Int) -> String {
        switch HKCategoryValueSleepAnalysis(rawValue: value) {
        case .inBed:              return "в постели"
        case .awake:              return "не сплю"
        case .asleepCore:         return "основной"
        case .asleepDeep:         return "глубокий"
        case .asleepREM:          return "быстрый"
        case .asleepUnspecified:  return "сон"
        default:                  return "неизвестно (\(value))"
        }
    }
}
#endif
