import Foundation

/// Что съесть на оставшиеся калории приёма.
///
/// Человек открывает добавление, зная одно: у него полдник на 400 ккал. Дальше
/// он ищет продукт, подбирает граммы, смотрит, сколько вышло, и правит — то
/// есть делает работу, которую приложение может сделать за него: оно знает и
/// остаток приёма, и что этот человек обычно ест.
///
/// Предлагаем не «еду вообще», а то, что он уже ел: чужие рекомендации
/// выглядят навязчивым советом, а свой же вчерашний творог — подсказкой.
enum MealSuggestions {
    struct Candidate: Identifiable, Equatable {
        let id: String
        /// Как называть: имя приёма или продукта.
        let name: String
        /// Из чего он собран — уже с подобранными граммами.
        let parts: [EntryComponent]
        let calories: Int
        let macros: Macros
        /// Насколько это близко к остатку, от 0 до 1 — для порядка в списке.
        let fit: Double

        /// Приём из нескольких продуктов или одиночная еда.
        var isComposed: Bool { parts.count > 1 }
    }

    /// Сколько предложений показывать. Больше трёх — это уже список, который
    /// надо читать, а он должен решаться одним взглядом.
    static let limit = 3
    /// Ниже этого остатка предлагать нечего: на сотню килокалорий подобрать
    /// осмысленную порцию нельзя, а «17 г творога» — издевательство.
    static let minimumRemaining = 120
    /// Насколько порция может разойтись с остатком.
    static let tolerance = 0.25

    /// Еда, из которой выбираем: то, что человек ел за последние недели.
    ///
    /// Готовые приёмы, а не отдельные продукты: полдник на 400 ккал — это не
    /// «творог 180 г», а «творог с бананом», как он его и ест. Одиночная еда
    /// тоже сюда попадает — как приём из одной части.
    struct Option {
        let name: String
        let parts: [EntryComponent]
        let calories: Int
        let macros: Macros
        /// Как часто ел: чем чаще, тем выше при равной точности.
        let timesEaten: Int
    }

    static func suggest(remaining: Int, from options: [Option],
                        leadingMacro: MacroKind? = nil) -> [Candidate] {
        guard remaining >= minimumRemaining else { return [] }
        let target = Double(remaining)

        let candidates: [Candidate] = options.compactMap { option in
            guard option.calories > 0 else { return nil }
            // Приём целиком масштабируется под остаток: съел его вчера на 520,
            // сегодня осталось 400 — берём тот же набор, но порции поменьше.
            // Растягивать сильно нельзя, иначе от «как он ест» ничего не
            // останется: половина порции — это уже другая еда.
            let raw = target / Double(option.calories)
            guard abs(raw - 1) <= tolerance else { return nil }

            let parts = option.parts.map { part -> EntryComponent in
                guard let grams = part.grams, grams > 0 else { return part }
                // До пятёрки: кухонные весы точнее не дают, а «137 г»
                // выглядит расчётом, а не едой.
                return part.scaled(toGrams: max(5, (grams * raw / 5).rounded() * 5))
            }
            let calories = parts.reduce(0) { $0 + $1.calories }
            let macros = parts.reduce(Macros.zero) { $0 + $1.macros }
            guard calories > 0 else { return nil }
            let miss = abs(Double(calories) - target) / target
            guard miss <= tolerance else { return nil }

            var fit = 1 - miss
            // Готовый приём ценнее одиночного продукта: он и есть ответ на
            // вопрос «что съесть», а продукт — только его часть.
            if option.parts.count > 1 { fit += 0.2 }
            // Ведущий макрос решает, что полезнее предложить: пока не закрыт
            // белок, творог лучше банана при одинаковых калориях.
            if let leadingMacro, isRich(calories: calories, macros: macros, in: leadingMacro) { fit += 0.25 }
            // При прочих равных — то, что человек ест чаще.
            fit += min(Double(option.timesEaten), 10) / 100

            return Candidate(id: option.name, name: option.name, parts: parts,
                             calories: calories, macros: macros, fit: fit)
        }

        return Array(candidates.sorted { $0.fit > $1.fit }.prefix(limit))
    }

    // MARK: - Пара под остаток

    /// Продукт, из которого можно собрать пару: цифры на сто грамм.
    struct Food {
        let name: String
        let caloriesPer100g: Int
        let macrosPer100g: Macros
        /// Сколько раз человек его ел — чем чаще, тем охотнее предлагаем.
        let timesEaten: Int
    }

    /// Разумные границы порции в граммах. Ниже — не еда, выше — не порция.
    static let portionRange: ClosedRange<Double> = 30...400
    /// Насколько собранная пара может разойтись с остатком калорий.
    static let pairCalorieTolerance = 0.07
    /// И с остатком белка. Допуск шире: белок добирают за день, а не за приём.
    static let pairProteinTolerance = 0.2

    /// Собрать пару продуктов под остаток калорий и белка.
    ///
    /// Нужна там, где прежняя подсказка молчала: приёма, который попадает в
    /// оставшиеся 480 ккал, человек никогда не ел, и предложить ему нечего.
    /// Зато из его же продуктов пара собирается почти всегда — и собирается
    /// точно, потому что двух продуктов хватает, чтобы попасть сразу в два
    /// числа: калории и белок.
    ///
    /// Решается это не перебором граммов, а системой из двух уравнений на две
    /// порции: сколько сотен граммов первого и второго дают нужные калории и
    /// нужный белок. Перебор идёт только по парам продуктов, и его немного.
    static func pair(remaining: Int, protein: Double, from foods: [Food],
                     limit: Int = 2) -> [Candidate] {
        guard remaining >= minimumRemaining, protein > 0 else { return [] }
        let targetCalories = Double(remaining)
        let pool = Array(foods.filter { $0.caloriesPer100g > 0 }
            .sorted { $0.timesEaten > $1.timesEaten }
            .prefix(14))
        guard pool.count >= 2 else { return [] }

        var found: [Candidate] = []
        for (i, first) in pool.enumerated() {
            for second in pool[(i + 1)...] {
                guard let candidate = solve(first: first, second: second,
                                            calories: targetCalories, protein: protein) else { continue }
                found.append(candidate)
            }
        }
        // По одному продукту в паре: три варианта с одним и тем же творогом —
        // это один вариант, показанный трижды.
        var usedNames = Set<String>()
        var result: [Candidate] = []
        for candidate in found.sorted(by: { $0.fit > $1.fit }) {
            let names = Set(candidate.parts.map(\.name))
            guard usedNames.isDisjoint(with: names) else { continue }
            usedNames.formUnion(names)
            result.append(candidate)
            if result.count == limit { break }
        }
        return result
    }

    /// Две порции, попадающие сразу в калории и в белок.
    private static func solve(first: Food, second: Food,
                              calories: Double, protein: Double) -> Candidate? {
        // Сотни граммов: a — первого, b — второго.
        let c1 = Double(first.caloriesPer100g), c2 = Double(second.caloriesPer100g)
        let p1 = first.macrosPer100g.protein, p2 = second.macrosPer100g.protein
        let determinant = c1 * p2 - c2 * p1
        // Пара, у которой калории и белок идут в одной пропорции, вторым
        // уравнением не решается: это, по сути, один и тот же продукт.
        guard abs(determinant) > 0.5 else { return nil }

        let a = (calories * p2 - protein * c2) / determinant
        let b = (protein * c1 - calories * p1) / determinant
        // До пятёрки: кухонные весы точнее не дают.
        let gramsFirst = (a * 100 / 5).rounded() * 5
        let gramsSecond = (b * 100 / 5).rounded() * 5
        guard portionRange.contains(gramsFirst), portionRange.contains(gramsSecond) else { return nil }

        let parts = [component(first, grams: gramsFirst), component(second, grams: gramsSecond)]
        let total = parts.reduce(0) { $0 + $1.calories }
        let macros = parts.reduce(Macros.zero) { $0 + $1.macros }
        let calorieMiss = abs(Double(total) - calories) / calories
        let proteinMiss = abs(macros.protein - protein) / protein
        guard calorieMiss <= pairCalorieTolerance, proteinMiss <= pairProteinTolerance else { return nil }

        // Точность по калориям важнее: белок добирают в течение дня, а в приём
        // надо попасть сейчас.
        var fit = 1 - calorieMiss * 2 - proteinMiss
        fit += min(Double(first.timesEaten + second.timesEaten), 20) / 100
        return Candidate(id: "pair-\(first.name)-\(second.name)",
                         name: "\(first.name) + \(second.name)",
                         parts: parts, calories: total, macros: macros, fit: fit)
    }

    private static func component(_ food: Food, grams: Double) -> EntryComponent {
        EntryComponent(name: food.name,
                       calories: Int((Double(food.caloriesPer100g) * grams / 100).rounded()),
                       macros: food.macrosPer100g.portion(grams: grams),
                       grams: grams)
    }

    /// Богата ли еда этим макросом — по доле калорий, а не по граммам.
    private static func isRich(calories: Int, macros: Macros, in macro: MacroKind) -> Bool {
        let total = Double(calories)
        guard total > 0 else { return false }
        let share: Double
        switch macro {
        case .protein: share = macros.protein * MacroTargets.kcalPerProteinGram / total
        case .fat:     share = macros.fat * MacroTargets.kcalPerFatGram / total
        case .carbs:   share = macros.carbs * MacroTargets.kcalPerCarbGram / total
        }
        return share >= 0.4
    }
}
