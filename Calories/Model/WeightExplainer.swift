import Foundation

/// Почему вес сегодня отклонился от тренда — по вчерашнему дню.
///
/// Утренний скачок на весах сильнее всего сбивает с диеты, а данные для
/// объяснения у приложения есть: вчерашние углеводы и соль, время последнего
/// приёма, пост накануне. Расчёт учится на истории самого человека — как его
/// вес отвечал на эти причины раньше — и сегодня называет одну-две из них.
///
/// Главный риск — убедительная неправда. Поэтому расчёт молчит, когда
/// истории мало, когда она ничего не объясняет (R² ниже 0,2), когда
/// отклонение мало или когда сегодняшние причины объясняют меньше половины
/// скачка или тянут в другую сторону. Молчать здесь — правильный ответ по
/// умолчанию.
nonisolated enum WeightExplainer {
    /// Одна пара «вчера → сегодняшнее утро».
    struct Day: Equatable, Sendable {
        /// Вес утром минус тренд на этот день, кг.
        var residualKg: Double
        /// Вчерашние углеводы минус личное среднее за 28 дней, г.
        var carbsDeltaG: Double
        /// Вчерашний натрий минус личное среднее, мг; nil — вчера он известен не весь.
        var sodiumDeltaMg: Double?
        /// На сколько часов последний приём был позже порога позднего ужина, не меньше 0.
        var lateHours: Double
        /// Вчера был день поста.
        var afterFast: Bool
    }

    enum Factor: String, Sendable { case carbs, sodium, lateMeal, afterFast }

    struct Contribution: Equatable, Sendable {
        var factor: Factor
        var kg: Double
    }

    struct Explanation: Equatable, Sendable {
        var residualKg: Double
        /// По убыванию модуля, не больше двух.
        var contributions: [Contribution]
    }

    static let minimumPairs = 21
    /// Порог отклонения, утверждённый владельцем 13.11.
    static let minimumResidualKg = 0.5
    static let minimumRSquared = 0.2
    static let minimumContributionKg = 0.15
    /// Натрий участвует, только если известен хотя бы в такой доле дней.
    static let sodiumCoverage = 0.7

    /// Модель на истории: причины, их коэффициенты и R².
    struct Fit: Equatable, Sendable {
        var factors: [Factor]
        var coefficients: [Double]
        var rSquared: Double
        var pairs: Int
    }

    /// Обучение на истории. nil — пар мало или система вырождена.
    static func fit(history: [Day]) -> Fit? {
        guard history.count >= minimumPairs else { return nil }

        // Натрий — только если он известен почти всегда; тогда в модель идут
        // лишь дни, где он есть, а не нули на месте незнания.
        let sodiumKnown = history.filter { $0.sodiumDeltaMg != nil }.count
        let useSodium = Double(sodiumKnown) >= Double(history.count) * sodiumCoverage
        let rows = useSodium ? history.filter { $0.sodiumDeltaMg != nil } : history

        var factors: [Factor] = [.carbs, .lateMeal, .afterFast]
        if useSodium { factors.append(.sodium) }
        // Причина, которой в истории не было ни разу, ничего не объясняет и
        // делает систему вырожденной.
        factors = factors.filter { factor in rows.contains { value(factor, in: $0) != 0 } }
        guard !factors.isEmpty else { return nil }

        let x = rows.map { row in factors.map { value($0, in: row) } }
        let y = rows.map(\.residualKg)
        guard let beta = leastSquares(x, y) else { return nil }

        // R² относительно среднего, а не нуля: иначе модель без свободного
        // члена выглядела бы лучше, чем есть.
        let mean = y.reduce(0, +) / Double(y.count)
        let total = y.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
        let residual = zip(x, y).reduce(0.0) { sum, pair in
            let fitted = zip(pair.0, beta).reduce(0) { $0 + $1.0 * $1.1 }
            return sum + (pair.1 - fitted) * (pair.1 - fitted)
        }
        guard total > 0 else { return nil }
        return Fit(factors: factors, coefficients: beta, rSquared: 1 - residual / total, pairs: rows.count)
    }

    static func explain(history: [Day], today: Day) -> Explanation? {
        guard abs(today.residualKg) >= minimumResidualKg,
              let model = fit(history: history),
              model.rSquared >= minimumRSquared else { return nil }
        let factors = model.factors, beta = model.coefficients

        let contributions = zip(factors, beta).map { factor, coefficient in
            Contribution(factor: factor, kg: coefficient * value(factor, in: today))
        }
        let sum = contributions.reduce(0) { $0 + $1.kg }
        // Причины тянут в другую сторону или объясняют меньше половины — молчим.
        guard sum * today.residualKg > 0, abs(sum) >= abs(today.residualKg) / 2 else { return nil }

        let shown = contributions
            .filter { abs($0.kg) >= minimumContributionKg && $0.kg * today.residualKg > 0 }
            .sorted { abs($0.kg) > abs($1.kg) }
            .prefix(2)
        guard !shown.isEmpty else { return nil }
        return Explanation(residualKg: today.residualKg, contributions: Array(shown))
    }

    private static func value(_ factor: Factor, in day: Day) -> Double {
        switch factor {
        case .carbs: return day.carbsDeltaG
        case .sodium: return day.sodiumDeltaMg ?? 0
        case .lateMeal: return day.lateHours
        case .afterFast: return day.afterFast ? 1 : 0
        }
    }

    /// Наименьшие квадраты без свободного члена: (XᵀX)β = Xᵀy, Гаусс с выбором
    /// ведущего элемента. nil — система вырождена.
    static func leastSquares(_ x: [[Double]], _ y: [Double]) -> [Double]? {
        guard let width = x.first?.count, width > 0, x.count >= width else { return nil }
        var a = Array(repeating: Array(repeating: 0.0, count: width + 1), count: width)
        for (row, target) in zip(x, y) {
            for i in 0..<width {
                for j in 0..<width { a[i][j] += row[i] * row[j] }
                a[i][width] += row[i] * target
            }
        }
        for column in 0..<width {
            guard let pivot = (column..<width).max(by: { abs(a[$0][column]) < abs(a[$1][column]) }),
                  abs(a[pivot][column]) > 1e-12 else { return nil }
            a.swapAt(column, pivot)
            for row in 0..<width where row != column {
                let factor = a[row][column] / a[column][column]
                for k in column...width { a[row][k] -= factor * a[column][k] }
            }
        }
        return (0..<width).map { a[$0][width] / a[$0][$0] }
    }
}
