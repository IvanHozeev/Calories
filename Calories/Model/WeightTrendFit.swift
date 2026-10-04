import Foundation

/// Прямая по взвешиваниям: темп и то, насколько ему можно верить.
///
/// Темп за фазу считался по двум точкам — весу на старте и весу сегодня, — и
/// ошибка любой из них целиком уходила в наклон. Одно утро после солёного
/// ужина сдвигало «темп за фазу» на сотню граммов в неделю, а вместе с ним
/// уезжала и дата финиша: вчера она была в ноябре, сегодня в январе.
///
/// Прямая по всем взвешиваниям устойчивее, но главное не в этом: у неё есть
/// **собственная погрешность**, и её можно показать. Три взвешивания за две
/// недели дают наклон, который с тем же успехом может быть нулём, — и честный
/// ответ в этом случае не «цель к 3 ноября», а «темп пока не отличим от нуля».
struct WeightTrendFit: Equatable {
    /// Килограммов в неделю. Минус — вес уходит.
    let weeklyRateKg: Double
    /// Стандартная ошибка наклона, в тех же килограммах в неделю.
    let standardErrorKg: Double
    let points: Int

    /// Отличим ли темп от нуля.
    ///
    /// Если коридор наклона накрывает ноль, направление не установлено: вес
    /// может уходить, а может стоять, и данные пока не различают эти случаи.
    var isDistinguishableFromZero: Bool {
        standardErrorKg > 0 && abs(weeklyRateKg) > standardErrorKg
    }

    /// Границы темпа — наклон плюс-минус его ошибка.
    var range: ClosedRange<Double> {
        (weeklyRateKg - standardErrorKg)...(weeklyRateKg + standardErrorKg)
    }

    /// Сколько взвешиваний нужно, чтобы вообще строить прямую.
    ///
    /// По двум точкам прямая проходит ровно, и ошибка выходит нулевой — то
    /// есть получается обещание точности, которой нет. Четыре — минимум, на
    /// котором разброс начинает что-то значить.
    static let minimumPoints = 4

    /// Метод наименьших квадратов по времени в неделях.
    static func fit(_ points: [(date: Date, kg: Double)]) -> WeightTrendFit? {
        guard points.count >= minimumPoints, let first = points.map(\.date).min() else { return nil }
        let xs = points.map { $0.date.timeIntervalSince(first) / (7 * 86_400) }
        let ys = points.map(\.kg)
        let n = Double(points.count)
        let meanX = xs.reduce(0, +) / n
        let meanY = ys.reduce(0, +) / n
        let sxx = zip(xs, ys).reduce(0.0) { $0 + ($1.0 - meanX) * ($1.0 - meanX) }
        guard sxx > 0.0001 else { return nil }
        let sxy = zip(xs, ys).reduce(0.0) { $0 + ($1.0 - meanX) * ($1.1 - meanY) }
        let slope = sxy / sxx
        let intercept = meanY - slope * meanX

        // Остаточный разброс вокруг прямой — он и есть мера того, насколько
        // вес шумит вокруг тренда: вода, соль, время взвешивания.
        let residual = zip(xs, ys).reduce(0.0) { sum, point in
            let predicted = intercept + slope * point.0
            return sum + (point.1 - predicted) * (point.1 - predicted)
        }
        let degreesOfFreedom = n - 2
        guard degreesOfFreedom > 0 else { return nil }
        let standardError = ((residual / degreesOfFreedom) / sxx).squareRoot()
        return WeightTrendFit(weeklyRateKg: slope, standardErrorKg: standardError, points: points.count)
    }
}
