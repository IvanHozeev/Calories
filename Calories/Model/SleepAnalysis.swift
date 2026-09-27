import Foundation

/// Одна ночь: когда лёг, когда встал и сколько на самом деле спал.
struct SleepNight: Codable, Equatable, Sendable {
    /// Когда лёг — начало первого отрезка сна.
    let bed: Date
    /// Когда встал — конец последнего.
    let wake: Date
    /// Часы сна: сумма отрезков, без пробуждений посреди ночи.
    let hours: Double
}

/// Сон из «Здоровья» — отрезками, а не ночами.
///
/// Браслет пишет каждую фазу отдельной записью, между ними попадаются
/// пробуждения, а иногда человек встаёт в туалет и ложится обратно. Собрать из
/// этого «лёг в 23:40, встал в 7:10, спал 6 ч 50 мин» — работа приложения.
///
/// Нужно это дважды. Во-первых, ради подъёма: расписание приёмов пищи до сих
/// пор угадывало его по первой еде дня, потому что время будильника iOS не
/// отдаёт, — а сон отдаёт прямо. Во-вторых, ради объяснений: после короткой
/// ночи и вес скачет, и голод сильнее, и шагов меньше, и без этой строчки
/// такой день выглядит просто сорванным.
enum SleepAnalysis {
    /// Отрезок сна, как его отдаёт «Здоровье».
    struct Segment: Equatable, Sendable {
        let start: Date
        let end: Date

        var duration: TimeInterval { end.timeIntervalSince(start) }
    }

    /// Разрыв, после которого это уже не та же ночь.
    ///
    /// Три часа. Сначала стоял час, и это оказалось слишком строго: браслет
    /// отдаёт ночь крупными кусками с долгими «бодрствованиями» между ними, и
    /// ночь из шести часов разваливалась на две по три — с подъёмом посреди
    /// ночи. Для человека же это одна ночь: он вставал, но ложился обратно.
    ///
    /// Дневной сон при этом всё равно останется отдельным: от утреннего
    /// подъёма до него проходит куда больше трёх часов.
    static let maxGap: TimeInterval = 3 * 60 * 60
    /// Короче этого — дрёма, а не ночь: дневной сон в кресле не должен
    /// объявлять подъёмом четыре часа дня.
    static let minimumHours: Double = 3

    /// Что считать сном, когда фаз нет.
    ///
    /// Apple Watch пишут фазы — глубокий, быстрый, основной, — и тогда всё
    /// просто. Браслеты часто отдают только «в постели», без разбора, и
    /// требовать от них фазы значит не видеть их сна вовсе. Поэтому: есть фазы
    /// — считаем по ним, нет ни одной — берём «в постели» как есть.
    ///
    /// Смешивать нельзя: у тех, кто пишет и то и другое, «в постели» шире сна
    /// и накинуло бы час чтения перед сном к ночи.
    static func segments(asleep: [Segment], inBed: [Segment]) -> [Segment] {
        asleep.isEmpty ? inBed : asleep
    }

    /// Собирает отрезки в ночи. Ночь принадлежит дню, в который человек встал.
    static func nights(from segments: [Segment]) -> [SleepNight] {
        let sorted = segments.filter { $0.duration > 0 }.sorted { $0.start < $1.start }
        guard !sorted.isEmpty else { return [] }

        var nights: [SleepNight] = []
        var group: [Segment] = [sorted[0]]

        func close(_ group: [Segment]) {
            guard let first = group.first, let last = group.last else { return }
            let hours = group.reduce(0.0) { $0 + $1.duration } / 3600
            guard hours >= minimumHours else { return }
            nights.append(SleepNight(bed: first.start, wake: last.end, hours: hours))
        }

        for segment in sorted.dropFirst() {
            if let previous = group.last, segment.start.timeIntervalSince(previous.end) <= maxGap {
                group.append(segment)
            } else {
                close(group)
                group = [segment]
            }
        }
        close(group)
        return nights
    }

    /// Ночь, относящаяся к этому дню, — та, после которой человек в этот день
    /// проснулся.
    static func night(for date: Date, in nights: [SleepNight], calendar: Calendar = .current) -> SleepNight? {
        nights.last { calendar.isDate($0.wake, inSameDayAs: date) }
    }

    /// Насколько ночь короче обычной. Ноль — спал как всегда или дольше.
    ///
    /// Сравнивается со средним, а не с нормой из учебника: «восемь часов» —
    /// это чужая цифра, а недосып у каждого свой относительно собственной
    /// привычки.
    static func shortfall(hours: Double, usual: Double) -> Double {
        max(0, usual - hours)
    }
}
