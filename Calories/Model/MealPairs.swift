import Foundation

/// Что человек обычно кладёт вместе.
///
/// Приёмы у многих собираются одними и теми же парами: молоко всегда с
/// протеином, паста всегда с котлетой, творог с ягодами. Приложение это видит
/// — состав каждого приёма лежит в дневнике, — но до сих пор молчало, и
/// второй продукт приходилось искать поиском, зная наперёд, что ищешь.
///
/// Здесь только счёт, без экрана и без стора: пороги в такой вещи важнее
/// всего, и проверяются они тестами, а не глазами.
enum MealPairs {
    /// Что предложить: имя и обычный для него вес.
    struct Suggestion: Identifiable, Equatable {
        let name: String
        /// Сколько человек обычно берёт этого, когда берёт вместе с тем, что
        /// уже в приёме. Медиана, а не среднее: одна запись «протеин 400 г»
        /// вместо сорока сдвинула бы среднее так, что предложенное нельзя
        /// было бы есть.
        let grams: Double?
        let calories: Int
        let macros: Macros
        /// Сколько раз встречалось вместе — по нему и порядок.
        let together: Int

        var id: String { name }
    }

    /// Реже этого — совпадение, а не привычка.
    ///
    /// Два раза: один раз вместе бывает у чего угодно, а дважды — уже выбор.
    /// Три было бы честнее, но тогда новая пара ждёт признания неделю, и
    /// подсказка приходит, когда она уже не нужна.
    static let minimumTogether = 2

    /// Сколько предложений показывать. Столько же, сколько у подсказок под
    /// остаток: больше трёх — список, который надо читать.
    static let limit = 3

    /// Что обычно идёт вместе с тем, что уже лежит в приёме.
    ///
    /// - Parameters:
    ///   - draft: имена того, что уже положили.
    ///   - history: состав прошлых приёмов, каждый — своим списком.
    static func suggestions(draft: [String], history: [[EntryComponent]]) -> [Suggestion] {
        let inDraft = Set(draft.map(normalized))
        guard !inDraft.isEmpty else { return [] }

        // Сколько раз кандидат встречался в одном приёме с чем-то из черновика
        // и какими порциями его брали.
        var together: [String: Int] = [:]
        var samples: [String: [EntryComponent]] = [:]

        for meal in history {
            let names = Set(meal.map { normalized($0.name) })
            // Приём, в котором нет ничего из черновика, про наши пары молчит.
            guard !names.isDisjoint(with: inDraft) else { continue }
            for part in meal where !inDraft.contains(normalized(part.name)) {
                let key = normalized(part.name)
                together[key, default: 0] += 1
                samples[key, default: []].append(part)
            }
        }

        return together
            .filter { $0.value >= minimumTogether }
            .compactMap { key, count -> Suggestion? in
                guard let parts = samples[key], let last = parts.last else { return nil }
                let grams = median(parts.compactMap(\.grams))
                // Калории и макросы — под ту порцию, которую предлагаем, а не
                // под последнюю съеденную: иначе строка обещает одно число, а
                // в приём попадает другое.
                let scale = scale(from: last, to: grams)
                return Suggestion(
                    name: last.name,
                    grams: grams,
                    calories: Int((Double(last.calories) * scale).rounded()),
                    macros: Macros(protein: last.protein * scale,
                                   fat: last.fat * scale,
                                   carbs: last.carbs * scale),
                    together: count)
            }
            // Чаще вместе — выше; при равном счёте по имени, чтобы порядок не
            // прыгал от перезапуска к перезапуску.
            .sorted { ($0.together, $1.name) > ($1.together, $0.name) }
            .prefix(limit)
            .map { $0 }
    }

    /// Во сколько раз предлагаемая порция отличается от последней съеденной.
    private static func scale(from part: EntryComponent, to grams: Double?) -> Double {
        guard let grams, let was = part.grams, was > 0 else { return 1 }
        return grams / was
    }

    /// Имена сравниваем без регистра и лишних пробелов: «Протеин AllIn» и
    /// «протеин allin» — один и тот же продукт, а не два разных.
    nonisolated static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}
