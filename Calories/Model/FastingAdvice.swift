import Foundation

/// Что делать до и после голодания.
///
/// Советы разведены по типу не для красоты: в сухом голодании нельзя пить, и
/// «пей больше воды во время» там не просто бесполезно, а вредно. Всё остальное
/// — про соль, кофеин и последний приём — общее.
enum FastingAdvice {
    struct Item: Identifiable {
        let id = UUID()
        /// Когда это делать — «за сутки», «сразу после».
        let when: String
        let text: String
        /// За сколько дней до голодания совет к месту: 0 — сам день. По нему
        /// «Сегодня» показывает подсказку ровно тогда, когда она нужна, а не
        /// всю памятку разом.
        let daysBefore: ClosedRange<Int>
    }

    static func preparation(for kind: FastKind) -> [Item] {
        var items = [
            Item(when: String(localized: "За 2–3 дня"),
                 text: String(localized: "Снижай кофе постепенно. Головная боль в пост чаще от отмены кофеина, чем от голода, и резкий отказ накануне делает только хуже."),
                 daysBefore: 2...3),
            Item(when: String(localized: "За сутки"),
                 text: String(localized: "Меньше соли. Соль — главный двигатель жажды, и солёный ужин накануне ощущается весь следующий день."),
                 daysBefore: 1...1)
        ]
        if kind == .dry {
            items.append(Item(
                when: String(localized: "За сутки"),
                text: String(localized: "Пей равномерно весь день, а не литр перед началом: выпитое залпом уходит в мочевой пузырь, а не в ткани."),
                daysBefore: 1...1))
        }
        items.append(Item(
            when: String(localized: "Накануне"),
            text: String(localized: "Норма на день поднята: заправь углеводами. В пост держит печёночный гликоген — около 100 г, и уходит он за первые 12–24 часа. Заполнить его хватает одного дня."),
            daysBefore: 1...1))
        items.append(Item(
            when: String(localized: "Последний приём"),
            text: String(localized: "Углеводы плюс немного жира: жир замедляет опорожнение желудка, и сытость держится дольше. Без острого и очень солёного — переевший солёного начинает пост с жажды."),
            daysBefore: 1...1))
        items.append(Item(
            when: String(localized: "Накануне"),
            text: String(localized: "Без алкоголя — он обезвоживает."),
            daysBefore: 1...1))
        return items
    }

    static func breakingFast(for kind: FastKind) -> [Item] {
        var items = [
            Item(when: String(localized: "Первые минуты"),
                 text: String(localized: "Начни с жидкости небольшими порциями. Литр залпом после сухого дня — самый частый способ испортить себе вечер."),
                 daysBefore: 0...0)
        ]
        items.append(Item(
            when: String(localized: "Через 30–60 минут"),
            text: String(localized: "Обычная еда. Не жирное и не солёное застолье сразу — разбитость после поста чаще от него, чем от самого поста."),
            daysBefore: 0...0))
        if kind == .water {
            items.append(Item(
                when: String(localized: "Дальше"),
                text: String(localized: "После голодания на воде выход мягче: организм не обезвожен, и полноценный приём пищи переносится легче."),
                daysBefore: 0...0))
        }
        return items
    }

    /// Самое раннее, за сколько дней до голодания есть что посоветовать.
    static let earliestDaysBefore = 3

    /// Советы к месту на этот день: за 2–3 дня — про кофе, накануне — про соль,
    /// воду и последний приём, в сам день — как выходить.
    static func advice(for kind: FastKind, daysBefore: Int) -> [Item] {
        (preparation(for: kind) + breakingFast(for: kind)).filter { $0.daysBefore.contains(daysBefore) }
    }

    /// Граница, которую приложение переходить не должно.
    static var medicalNote: String {
        String(localized: "Беременность, диабет, лекарства по часам — это к врачу, а не к приложению. Здесь общие советы, а не медицинская рекомендация.")
    }
}
