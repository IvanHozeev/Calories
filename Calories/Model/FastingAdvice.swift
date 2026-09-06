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
    }

    static func preparation(for kind: FastKind) -> [Item] {
        var items = [
            Item(when: String(localized: "За 2–3 дня"),
                 text: String(localized: "Снижай кофе постепенно. Головная боль в пост чаще от отмены кофеина, чем от голода, и резкий отказ накануне делает только хуже.")),
            Item(when: String(localized: "За сутки"),
                 text: String(localized: "Меньше соли. Соль — главный двигатель жажды, и солёный ужин накануне ощущается весь следующий день."))
        ]
        if kind == .dry {
            items.append(Item(
                when: String(localized: "За сутки"),
                text: String(localized: "Пей равномерно весь день, а не литр перед началом: выпитое залпом уходит в мочевой пузырь, а не в ткани.")))
        }
        items.append(Item(
            when: String(localized: "Последний приём"),
            text: String(localized: "Умеренно, без острого и очень солёного. Переевший начинает пост с жажды, а не с сытости.")))
        items.append(Item(
            when: String(localized: "Накануне"),
            text: String(localized: "Без алкоголя — он обезвоживает.")))
        return items
    }

    static func breakingFast(for kind: FastKind) -> [Item] {
        var items = [
            Item(when: String(localized: "Первые минуты"),
                 text: String(localized: "Начни с жидкости небольшими порциями. Литр залпом после сухого дня — самый частый способ испортить себе вечер."))
        ]
        items.append(Item(
            when: String(localized: "Через 30–60 минут"),
            text: String(localized: "Обычная еда. Не жирное и не солёное застолье сразу — разбитость после поста чаще от него, чем от самого поста.")))
        if kind == .water {
            items.append(Item(
                when: String(localized: "Дальше"),
                text: String(localized: "После голодания на воде выход мягче: организм не обезвожен, и полноценный приём пищи переносится легче.")))
        }
        return items
    }

    /// Граница, которую приложение переходить не должно.
    static var medicalNote: String {
        String(localized: "Беременность, диабет, лекарства по часам — это к врачу, а не к приложению. Здесь общие советы, а не медицинская рекомендация.")
    }
}
