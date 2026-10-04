import WidgetKit
import SwiftUI
import AppIntents

/// Ближайший приём пищи на экране блокировки: что и когда.
///
/// Экран блокировки — то место, где на телефон смотрят чаще всего и дольше
/// ничего не нажимают. Вопрос, который там задают про еду, один: скоро ли
/// следующий приём и сколько на него отведено. Ради такого ответа не стоит
/// открывать приложение.
///
/// Приложение кладёт в общий контейнер весь день расписанием, а виджет сам
/// решает, какой приём сейчас идёт и какой следующий: он живёт своей временной
/// лентой и переходит с обеда на ужин в семь вечера, даже если приложение в
/// этот день больше не открывали.

private let appGroup = "group.calories.shared"

/// Один приём из расписания, как его видит виджет.
struct MealSlotSnapshot: Equatable {
    /// Ключ названия приёма: «Завтрак», «Обед» — он же строка в каталоге.
    let period: String
    /// Время самого приёма.
    let time: Date
    /// Окно, в котором этот приём ждут.
    let start: Date
    let end: Date
    /// Сколько калорий на него отведено.
    let calories: Int

    var isCurrent: Bool { Date() >= start && Date() < end }
}

struct MealEntry: TimelineEntry {
    let date: Date
    /// Идущий сейчас приём, если его окно открыто.
    let current: MealSlotSnapshot?
    /// Ближайший впереди.
    let next: MealSlotSnapshot?
    /// Расписание вообще включено: без него и показывать нечего.
    var hasSchedule: Bool = true

    /// Что показывать: идущий приём важнее будущего — в его окне и едят.
    var shown: MealSlotSnapshot? { current ?? next }
}

/// Чтение расписания из общего контейнера — одно на виджет и контрол.
enum MealFeed {
    static func slots() -> [MealSlotSnapshot] {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: "widget_meals"),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return raw.compactMap { item in
            guard let period = item["period"] as? String,
                  let time = item["time"] as? Double,
                  let start = item["start"] as? Double,
                  let end = item["end"] as? Double,
                  let calories = item["calories"] as? Double else { return nil }
            return MealSlotSnapshot(period: period,
                                    time: Date(timeIntervalSince1970: time),
                                    start: Date(timeIntervalSince1970: start),
                                    end: Date(timeIntervalSince1970: end),
                                    calories: Int(calories))
        }
    }

    /// Что показывать на этот момент: идущий приём важнее будущего — в его
    /// окне и едят.
    ///
    /// Когда впереди на сегодня не осталось ничего, показываем первый приём
    /// завтрашнего дня: время у приёмов изо дня в день одно и то же. Калорий у
    /// него нет — норму на завтра никто ещё не считал, и выдумывать её нельзя.
    static func shown(at date: Date, in slots: [MealSlotSnapshot]) -> MealSlotSnapshot? {
        if let current = slots.first(where: { date >= $0.start && date < $0.end }) { return current }
        if let next = slots.first(where: { $0.time > date }) { return next }
        guard let first = slots.min(by: { $0.time < $1.time }) else { return nil }
        return MealSlotSnapshot(period: first.period,
                                time: first.time.addingTimeInterval(86_400),
                                start: first.start.addingTimeInterval(86_400),
                                end: first.end.addingTimeInterval(86_400),
                                calories: 0)
    }
}

struct MealProvider: TimelineProvider {
    func placeholder(in context: Context) -> MealEntry {
        let soon = Date().addingTimeInterval(2 * 3600)
        let slot = MealSlotSnapshot(period: "Ужин", time: soon,
                                    start: soon.addingTimeInterval(-1800),
                                    end: soon.addingTimeInterval(1800), calories: 840)
        return MealEntry(date: Date(), current: nil, next: slot)
    }

    func getSnapshot(in context: Context, completion: @escaping (MealEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entry(at: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MealEntry>) -> Void) {
        let slots = loadSlots()
        // Моменты, когда картинка меняется: открытие окна, его конец и само
        // время приёма. Между ними виджету обновляться незачем.
        let moments = ([Date()] + slots.flatMap { [$0.start, $0.time, $0.end] })
            .filter { $0 >= Date() }
            .sorted()
        let entries = moments.prefix(24).map { entry(at: $0, slots: slots) }
        completion(Timeline(entries: entries.isEmpty ? [entry(at: Date(), slots: slots)] : Array(entries),
                            policy: .after(nextMidnight)))
    }

    private var nextMidnight: Date {
        Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date())
    }

    private func entry(at date: Date, slots: [MealSlotSnapshot]? = nil) -> MealEntry {
        let all = slots ?? MealFeed.slots()
        let shown = MealFeed.shown(at: date, in: all)
        let isCurrent = shown.map { date >= $0.start && date < $0.end } ?? false
        return MealEntry(date: date,
                         current: isCurrent ? shown : nil,
                         next: isCurrent ? nil : shown,
                         hasSchedule: !all.isEmpty)
    }

    private func loadSlots() -> [MealSlotSnapshot] { MealFeed.slots() }
}

struct MealWidgetView: View {
    var entry: MealEntry
    @Environment(\.widgetFamily) private var family

    private var slot: MealSlotSnapshot? { entry.shown }

    /// Название приёма на языке телефона: в контейнер кладётся ключ, а не
    /// готовая строка — иначе после смены языка виджет говорил бы по-старому,
    /// пока приложение не откроют.
    private var title: String {
        guard let slot else { return String(localized: "Приём пищи") }
        return String(localized: String.LocalizationValue(slot.period))
    }

    private var time: String {
        guard let slot else { return "" }
        return slot.time.formatted(date: .omitted, time: .shortened)
    }

    var body: some View {
        switch family {
        case .accessoryInline:
            // Одна строка и один значок — больше система здесь не покажет.
            Label {
                if let slot, slot.isCurrent {
                    Text(verbatim: slot.calories > 0
                         ? "\(title) · \(slot.calories) \(String(localized: "ккал"))"
                         : title)
                } else if let slot {
                    Text(verbatim: slot.calories > 0
                         ? "\(title) \(time) · \(slot.calories) \(String(localized: "ккал"))"
                         : "\(title) \(time)")
                } else {
                    Text("Нет расписания")
                }
            } icon: {
                Image(systemName: "fork.knife")
            }
            .containerBackground(.clear, for: .widget)

        case .accessoryCircular:
            // Кружок: вилка и время приёма под ней. Калории сюда не лезут, а
            // время — ровно то, ради чего на блокировку и смотрят.
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "fork.knife")
                        .font(.system(size: 13, weight: .semibold))
                    Text(verbatim: slot == nil ? "—" : time)
                        .font(.system(size: 12, weight: .medium))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                }
                .padding(.horizontal, 2)
            }
            .containerBackground(.clear, for: .widget)

        default:
            rectangular
        }
    }

    /// Прямоугольный — единственный на блокировке, где помещается ответ
    /// целиком: что за приём, когда он и сколько на него отведено.
    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "fork.knife")
                    .font(.caption2)
                Text(verbatim: title)
                    .font(.headline)
                    .lineLimit(1)
            }
            .widgetAccentable()

            if let slot {
                if slot.isCurrent {
                    // Окно открыто: про «через сколько» говорить нечего, еда
                    // сейчас. Остаётся до какого часа и сколько отведено.
                    Text(verbatim: String(format: String(localized: "до %@ · %lld ккал"),
                                          slot.end.formatted(date: .omitted, time: .shortened),
                                          slot.calories))
                        .font(.caption)
                } else {
                    Text(verbatim: slot.calories > 0
                         ? "\(time) · \(slot.calories) \(String(localized: "ккал"))"
                         : time)
                        .font(.caption)
                    // Системный таймер сам считает минуты: виджету не нужно
                    // просыпаться ради каждой из них.
                    Text(slot.time, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                // Разные ответы на разные вопросы: расписания нет вовсе —
                // или оно есть, но приложение ещё не рассказало виджету, что в
                // нём. Второе чинится открытием приложения, первое — нет.
                Text(entry.hasSchedule ? "Приёмов больше нет" : "Расписание выключено")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .containerBackground(.clear, for: .widget)
    }
}

struct MealWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CaloriesMealWidget", provider: MealProvider()) { entry in
            MealWidgetView(entry: entry)
        }
        .configurationDisplayName("Приём пищи")
        .description("Что за приём ближайший, когда он и сколько на него отведено.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline, .accessoryCircular])
    }
}

// MARK: - Контрол

/// Кнопка приёма пищи для Пункта управления, кнопки действия и экрана
/// блокировки.
///
/// На самой блокировке у контрола видно только значок — так система их рисует,
/// подписи там нет ни у одного контрола. Поэтому время живёт в виджете выше, а
/// контрол даёт одно: нажал — открылся приём пищи. В Пункте управления подпись
/// есть, и туда уходит ближайший приём с его временем.
@available(iOS 18.0, *)
struct MealControlValueProvider: ControlValueProvider {
    var previewValue: String { String(localized: "Приём пищи") }

    func currentValue() async throws -> String {
        guard let slot = MealFeed.shown(at: Date(), in: MealFeed.slots()) else {
            return String(localized: "Приём пищи")
        }
        let name = String(localized: String.LocalizationValue(slot.period))
        return slot.isCurrent
            ? name
            : "\(name) \(slot.time.formatted(date: .omitted, time: .shortened))"
    }
}

@available(iOS 18.0, *)
struct MealControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "ivankhozeyev.team.Calories.control.nextMeal",
                                   provider: MealControlValueProvider()) { title in
            ControlWidgetButton(action: QuickAddIntent(option: .meal)) {
                Label(title, systemImage: "fork.knife")
            }
        }
        .displayName("Приём пищи")
        .description("Показывает ближайший приём и открывает его добавление.")
    }
}
