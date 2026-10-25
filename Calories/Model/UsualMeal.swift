import Foundation

/// Приём, который человек собирает снова и снова.
///
/// Разбор дневника показал простую вещь: почти каждый приём составной, а
/// продуктов в обороте десяток. Завтрак из четырёх позиций собирается четырьмя
/// действиями — и так каждое утро, хотя ровно этот завтрак был вчера,
/// позавчера и неделю назад.
///
/// Здесь ищется не «похожий приём», а повторяющийся набор: что лежит вместе
/// достаточно часто, чтобы предложить его целиком. Порции берём медианные —
/// одно утро с четырьмя яйцами не должно сделать из них норму.
///
/// Только счёт, без экрана и без стора: пороги в такой вещи важнее всего.
enum UsualMeal {

    /// Готовое предложение: состав целиком и его обычная цена в калориях.
    struct Suggestion: Identifiable, Equatable {
        /// Имена состава — по ним же и опознаётся повтор.
        let parts: [EntryComponent]
        /// Сколько раз человек собирал ровно такой набор.
        let times: Int
        /// Когда собирал в последний раз: вчерашний завтрак ближе, чем
        /// такой же, но месячной давности.
        let lastEaten: Date

        var calories: Int { parts.reduce(0) { $0 + $1.calories } }

        var macros: Macros {
            parts.reduce(Macros.zero) {
                Macros(protein: $0.protein + $1.protein,
                       fat: $0.fat + $1.fat,
                       carbs: $0.carbs + $1.carbs)
            }
        }

        var id: String { parts.map(\.name).joined(separator: "|") }
    }

    /// Из скольких позиций набор считается набором.
    ///
    /// Две: приём из одной позиции повторять незачем — для него уже есть
    /// «Недавнее» и повтор свайпом, и ради него городить предложение значит
    /// показывать человеку то, что у него и так под рукой.
    static let minimumParts = 2

    /// Сколько раз набор должен повториться, чтобы стать «обычным».
    ///
    /// Три, а не два, как у пар. Пара продуктов — это привычка сочетания, и
    /// ошибиться в ней дёшево: человек просто не нажмёт. Здесь же в приём
    /// уезжает сразу четыре позиции с порциями, и случайное совпадение стоит
    /// дороже — его придётся разбирать руками.
    static let minimumTimes = 3

    /// Сколько предложений показывать. Больше двух — это уже список, который
    /// надо читать и выбирать, то есть ровно та работа, которой мы избегаем.
    static let limit = 2

    /// Насколько похожие наборы считать одним.
    ///
    /// Человек не ест по рецепту: к обычному завтраку иногда добавляется
    /// банан, иногда забывается кофе. Требовать полного совпадения значит не
    /// найти ни одного повтора — в дневнике почти не бывает двух абсолютно
    /// одинаковых приёмов. Три четверти общего состава — та граница, за
    /// которой это всё ещё «тот самый завтрак».
    static let sameShare = 0.75

    /// Что человек обычно ест в это окно.
    ///
    /// - Parameters:
    ///   - history: прошлые приёмы — состав и когда это было.
    ///   - period: окно дня, если хотим только завтраки; nil — любые.
    ///   - calendar: нужен, чтобы определить окно по времени записи.
    static func suggestions(history: [(date: Date, parts: [EntryComponent])],
                            period: MealPeriod? = nil,
                            calendar: Calendar = .current) -> [Suggestion] {
        // Приёмы того же окна: обед не предлагают на завтрак, даже если
        // человек ест одно и то же.
        let meals = history.filter { meal in
            guard meal.parts.count >= minimumParts else { return false }
            guard let period else { return true }
            return MealPeriod.period(for: meal.date) == period
        }
        guard meals.count >= minimumTimes else { return [] }

        // Группируем похожие наборы вокруг первого встреченного: сортировка
        // по свежести делает опорой самый недавний вариант, а не самый старый.
        var groups: [(names: Set<String>, meals: [(date: Date, parts: [EntryComponent])])] = []
        for meal in meals.sorted(by: { $0.date > $1.date }) {
            let names = Set(meal.parts.map { normalized($0.name) })
            if let index = groups.firstIndex(where: { isSame($0.names, names) }) {
                groups[index].meals.append(meal)
            } else {
                groups.append((names, [meal]))
            }
        }

        return groups
            .filter { $0.meals.count >= minimumTimes }
            .compactMap { group -> Suggestion? in
                guard let parts = typical(group.meals), let last = group.meals.first?.date else { return nil }
                return Suggestion(parts: parts, times: group.meals.count, lastEaten: last)
            }
            // Чаще — выше; при равной частоте ближе тот, что ели недавно.
            .sorted { ($0.times, $0.lastEaten) > ($1.times, $1.lastEaten) }
            .prefix(limit)
            .map { $0 }
    }

    /// Два набора — один и тот же приём?
    private static func isSame(_ left: Set<String>, _ right: Set<String>) -> Bool {
        let common = Double(left.intersection(right).count)
        let biggest = Double(max(left.count, right.count))
        guard biggest > 0 else { return false }
        return common / biggest >= sameShare
    }

    /// Типичный состав группы: то, что входит в большинство её приёмов, с
    /// медианной порцией.
    ///
    /// Именно большинство, а не объединение: иначе в «обычный завтрак»
    /// попадёт всё, что человек когда-либо к нему добавлял, и предложение
    /// станет длиннее настоящего приёма.
    private static func typical(_ meals: [(date: Date, parts: [EntryComponent])]) -> [EntryComponent]? {
        guard !meals.isEmpty else { return nil }
        var byName: [String: [EntryComponent]] = [:]
        for meal in meals {
            // Один и тот же продукт дважды в одном приёме считаем один раз:
            // иначе он получит вес двух приёмов.
            var seen: Set<String> = []
            for part in meal.parts where seen.insert(normalized(part.name)).inserted {
                byName[normalized(part.name), default: []].append(part)
            }
        }
        let half = Double(meals.count) / 2
        let kept = byName.filter { Double($0.value.count) > half }
        guard kept.count >= minimumParts else { return nil }

        return kept.values
            .compactMap { samples -> EntryComponent? in
                guard let last = samples.first else { return nil }
                let grams = median(samples.compactMap(\.grams))
                let scale = scale(from: last, to: grams)
                return EntryComponent(
                    name: last.name,
                    calories: Int((Double(last.calories) * scale).rounded()),
                    macros: Macros(protein: last.protein * scale,
                                   fat: last.fat * scale,
                                   carbs: last.carbs * scale),
                    grams: grams)
            }
            // Порядок по калориям: главное блюдо приёма стоит первым, как
            // человек его и собирает.
            .sorted { ($0.calories, $1.name) > ($1.calories, $0.name) }
    }

    private static func scale(from part: EntryComponent, to grams: Double?) -> Double {
        guard let grams, let was = part.grams, was > 0 else { return 1 }
        return grams / was
    }

    static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}
