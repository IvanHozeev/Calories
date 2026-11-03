import Foundation

/// Мясное, молочное или ни то ни другое.
///
/// Нужно для одного: между мясным и молочным положено выждать, и сколько
/// именно — зависит от того, что съели последним. Всё остальное приложение
/// про кашрут не знает и знать не берётся: оно не говорит, кошерный продукт
/// или нет, не читает сертификаты и не советует, что есть.
///
/// Почему это не категория продукта. Категория в приложении — про навигацию:
/// «Молочное и яйца» лежат вместе, потому что их вместе ищут в списке. Для
/// кашрута это ровно та граница, по которой нельзя проводить черту: яйцо —
/// парве, и таймер, построенный на категории, запретил бы мясо после яйца.
/// Поэтому статус живёт своим свойством, а категория даёт ему только
/// значение по умолчанию — и то не везде.
enum KosherStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Бсари: мясо и птица, и всё, что на мясном бульоне.
    case meat
    /// Халави: молоко и всё молочное.
    case dairy
    /// Парве — ни мясное, ни молочное: яйца, рыба, растительное.
    case parve
    /// Состав неизвестен.
    ///
    /// Отдельное значение, а не «парве по умолчанию»: про печенье нельзя
    /// сказать, на сливочном оно масле или на растительном, и догадка здесь
    /// хуже молчания. Неизвестное не запускает отсчёт и не снимает его.
    case unknown

    var id: String { rawValue }

    /// Противоположное: то, чего после этого ждут.
    var opposite: KosherStatus? {
        switch self {
        case .meat:  return .dairy
        case .dairy: return .meat
        case .parve, .unknown: return nil
        }
    }
}

// MARK: - Значение по умолчанию

extension KosherStatus {
    /// Статус по категории — грубая основа, которую уточняют поимённо.
    ///
    /// Шесть категорий честно ложатся на кашрут: мясо мясное, рыба, яйца и
    /// растения парве. Ради этого яйца и уехали из «Молочного» в свою
    /// категорию: пока они лежали вместе с сыром, значение по умолчанию
    /// запрещало мясо после яичницы. Остальные категории не ложатся, и по ним
    /// отдельные списки ниже: мороженое молочное, сало мясное, а выпечка —
    /// неизвестность, потому что рецепт у неё у каждого свой.
    static func byCategory(_ category: FoodCategory) -> KosherStatus {
        switch category {
        case .meat:
            return .meat
        case .dairy:
            return .dairy
        case .fish, .eggs, .produce, .grains, .legumes, .mushrooms:
            return .parve
        // Здесь категория не говорит ничего: в «Сладком» лежат и мёд, и
        // пломбир, в «Напитках» — и вода, и латте, а «Готовые блюда» бывают
        // любыми. Имя уточнит то, что уточняется; остальное останется
        // неизвестным — и это правильный ответ, а не недоработка.
        case .fats, .sweets, .drinks, .dishes, .other:
            return .unknown
        }
    }

    /// Английские названия позиций каталога, у которых статус не совпадает с
    /// категорией. Ключ английский, потому что он у каталога стабилен:
    /// русское название переводится, английское — нет.
    ///
    /// Своих продуктов здесь нет и быть не может: у человека в списке лежит
    /// товар с израильской полки, и угадать его состав по имени нельзя. Им
    /// статус ставится руками, а до тех пор он неизвестен.
    private static let byName: [String: KosherStatus] = [
        // Сладкое: молочное тут то, где молоко в составе названо.
        "Ice cream": .dairy, "Condensed milk": .dairy, "Milk chocolate": .dairy,
        "Chocolate hazelnut spread": .dairy,

        // Напитки: кофе сам по себе парве, молочным его делает молоко.
        "Latte": .dairy, "Cappuccino": .dairy, "Coffee with milk": .dairy,
        "Milkshake": .dairy,
        "Water": .parve, "Mineral water": .parve, "Tea": .parve, "Black coffee": .parve,
        "Tomato juice": .parve, "Orange juice": .parve, "Apple juice": .parve,
        "Compote": .parve, "Berry drink": .parve, "Kvass": .parve, "Cola": .parve,
        "Energy drink": .parve,

        // Масла и орехи: все растительные — парве, сливочное молочное, сало мясное.
        "Butter": .dairy,
        "Salo": .meat,
        "Sunflower oil": .parve, "Olive oil": .parve, "Coconut oil": .parve,
        "Mayonnaise": .parve, "Peanut butter": .parve,
        "Walnuts": .parve, "Hazelnuts": .parve, "Almonds": .parve, "Pistachios": .parve,
        "Cashews": .parve, "Peanuts": .parve, "Pine nuts": .parve, "Coconut": .parve,
        "Sesame": .parve, "Chia seeds": .parve, "Flax seeds": .parve,
        "Sunflower seeds": .parve, "Pumpkin seeds": .parve,

        // Готовые блюда: мясное — то, что варится на мясе или из мяса.
        "Chicken soup": .meat, "Shawarma": .meat, "Plov": .meat, "Goulash": .meat,
        "Burger": .meat, "Hot dog": .meat, "Cabbage rolls": .meat, "Solyanka": .meat,
        "Borscht": .meat, "Shchi": .meat,
        // Молочное — то, где молоко, творог или сыр держат блюдо.
        "Syrniki": .dairy, "Rice milk porridge": .dairy, "Pancakes": .dairy,
        "Fritters": .dairy, "Cheese sandwich": .dairy, "Lasagna": .dairy,
        "Pizza": .dairy, "Caesar salad": .dairy, "Greek salad": .dairy,
        "Vareniki with potato": .dairy,
        // Парве — овощное и рыбное.
        "Vinegret": .parve, "Vegetable stew": .parve, "Fried potato": .parve,
        "French fries": .parve, "Fish soup": .parve, "Sushi roll": .parve,
        "Omelette": .parve, "Fried eggs": .parve,

        // Каши на воде парве, на молоке — молочные.
        "Oatmeal with milk": .dairy, "Semolina porridge": .dairy,
    ]

    /// Статус позиции каталога: поимённо, иначе по категории.
    static func forCatalog(name: String, category: FoodCategory) -> KosherStatus {
        byName[name] ?? byCategory(category)
    }

    /// Твёрдый выдержанный сыр: после него ждут столько же, сколько после
    /// мясного.
    ///
    /// Список короткий намеренно. Выдержка — свойство конкретного сыра, а не
    /// его имени: израильская жёлтая сырная нарезка твёрдая на вид, но
    /// полгода её никто не держал. Поэтому здесь только то, что выдержано по
    /// определению, а остальное человек отмечает сам.
    static func isHardCheese(name: String) -> Bool {
        name == "Parmesan"
    }
}

// MARK: - Что не кошерно видом

/// Запрещено ли это само по себе.
///
/// Приложение не выдаёт кашрут и не читает сертификаты. Про говядину оно не
/// знает, был ли забой кошерным, и сказать «кошерно» не может никогда — такой
/// ответ был бы враньём с видом уверенности.
///
/// Сказать «не кошерно» — может, и это другой разговор: свинина, зайчатина и
/// морское без чешуи и плавников запрещены видом. Это не зависит ни от
/// производителя, ни от надзора, ни от страны, и ошибиться тут нельзя.
/// Поэтому ответов два: «запрещено видом» и «не знаю».
enum KosherVerdict: String, Codable, Sendable {
    /// Запрещено видом — что бы ни было написано на упаковке.
    case forbidden
    /// Зависит от производства, а о нём приложение ничего не знает.
    case unknown
}

extension KosherVerdict {
    /// Позиции каталога, запрещённые видом. Ключ английский — он у каталога
    /// стабилен.
    ///
    /// Сюда попадает только бесспорное. «Сосиски» и «Колбаса варёная» бывают
    /// и говяжьими, и индюшачьими — они остаются неизвестностью. «Крабовые
    /// палочки» делают из минтая, и у них бывает надзор, несмотря на имя.
    /// А вот «Ветчина» в этом каталоге — свиная, как её и заводили.
    private static let forbiddenNames: Set<String> = [
        "Pork", "Pork tenderloin", "Pork shashlik", "Bacon", "Salo", "Ham",
        "Rabbit",
        "Shrimp", "Squid", "Crab", "Mussels",
    ]

    static func forCatalog(name: String) -> KosherVerdict {
        forbiddenNames.contains(name) ? .forbidden : .unknown
    }
}

// MARK: - Приём пищи целиком

extension KosherStatus {
    /// Статус приёма из нескольких продуктов.
    ///
    /// Мясное перевешивает: если в тарелке было и то и другое, ждать надо по
    /// мясному. Неизвестное не перевешивает ничего — иначе один непонятный
    /// продукт стирал бы отсчёт, начатый куском курицы.
    static func of(_ parts: [KosherStatus]) -> KosherStatus {
        if parts.contains(.meat) { return .meat }
        if parts.contains(.dairy) { return .dairy }
        if parts.contains(.parve) { return .parve }
        return .unknown
    }

    /// Мясное и молочное в одной тарелке.
    ///
    /// Отдельная проверка, а не ещё одно значение статуса: ожидание и
    /// запрет — разные вещи. Статус такого приёма всё равно мясной (ждать
    /// после него надо по мясному), но сказать о нём нужно другое — что так
    /// нельзя, и сказать до того, как человек запишет приём, а не после.
    static func isMixed(_ parts: [KosherStatus]) -> Bool {
        parts.contains(.meat) && parts.contains(.dairy)
    }
}

/// Сколько ждать — обычай, а не одно число.
///
/// После мясного ждут шесть часов (Шулхан Арух, большинство общин), пять с
/// половиной, три часа (немецкий обычай) или час (голландский). После
/// молочного по букве закона ждать не нужно вовсе — достаточно прополоскать
/// рот и съесть что-то нейтральное, — но полчаса распространённый обычай.
/// Приложение не выбирает за человека: оно считает по тому, как принято у
/// него.
struct KosherCustom: Equatable, Codable, Sendable {
    /// Сколько минут ждать молочного после мясного.
    var afterMeat: Int = 360
    /// Сколько минут ждать мясного после молочного. Ноль — не ждать.
    var afterDairy: Int = 0
    /// Считать ли твёрдый выдержанный сыр мясным по времени ожидания.
    var hardCheeseLikeMeat: Bool = true

    /// Обычаи после мясного, в минутах: час, три часа, пять с половиной, шесть.
    static let afterMeatOptions = [60, 180, 330, 360]
    /// После молочного: не ждать, полчаса, час.
    static let afterDairyOptions = [0, 30, 60]
}

/// Ожидание после еды: чего ждём и до какого времени.
struct KosherWait: Equatable, Sendable {
    /// Что съели — от этого зависит, чего именно нельзя.
    let eaten: KosherStatus
    /// Чего ждём.
    let blocked: KosherStatus
    /// Когда съели. Нужно строке: она называет причину отсчёта, а не только
    /// его конец — «после мясного в 18:40» объясняет число, которое иначе
    /// пришлось бы принимать на веру.
    let since: Date
    let until: Date

    func isOver(at now: Date = Date()) -> Bool { now >= until }
}

enum KosherClock {
    /// Ожидание после одного приёма.
    ///
    /// Парве и неизвестное не создают ожидания: после них можно и то и
    /// другое, а про неизвестное мы просто ничего не знаем — и молчим,
    /// вместо того чтобы на всякий случай запретить.
    static func wait(after status: KosherStatus, at date: Date,
                     hardCheese: Bool = false,
                     custom: KosherCustom = KosherCustom()) -> KosherWait? {
        guard let blocked = status.opposite else { return nil }
        let minutes: Int
        switch status {
        case .meat:
            minutes = custom.afterMeat
        case .dairy:
            // Твёрдый сыр ждут как мясо: это тот случай, ради которого отсчёт
            // после молочного вообще нужен. Без него приложение бодро
            // сообщало бы, что после пармезана курица через полчаса.
            minutes = hardCheese && custom.hardCheeseLikeMeat ? custom.afterMeat : custom.afterDairy
        case .parve, .unknown:
            return nil
        }
        guard minutes > 0 else { return nil }
        return KosherWait(eaten: status, blocked: blocked, since: date,
                          until: date.addingTimeInterval(Double(minutes) * 60))
    }

    /// Ожидание по дневнику: самое позднее из действующих.
    ///
    /// Записи приходят в любом порядке, а считать надо по той, что держит
    /// дольше: съел курицу в час и сыр в два — молочного ждать до семи, а
    /// мясное после сыра уже можно, и обе эти правды нужны одновременно.
    /// Поэтому возвращаем по одному ожиданию на каждое заблокированное.
    static func waits(from meals: [(status: KosherStatus, date: Date, hardCheese: Bool)],
                      now: Date = Date(),
                      custom: KosherCustom = KosherCustom()) -> [KosherWait] {
        var latest: [KosherStatus: KosherWait] = [:]
        for meal in meals {
            guard let wait = wait(after: meal.status, at: meal.date,
                                  hardCheese: meal.hardCheese, custom: custom),
                  !wait.isOver(at: now) else { continue }
            if let existing = latest[wait.blocked], existing.until >= wait.until { continue }
            latest[wait.blocked] = wait
        }
        return latest.values.sorted { $0.until > $1.until }
    }
}
