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
