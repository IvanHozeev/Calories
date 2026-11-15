import Foundation

/// Тренд веса мини-графиком: из ряда значений — высоты точек от 0 до 1.
///
/// Чистая арифметика: сам ряд собирает хранилище, рисует вьюха, а здесь
/// только то, что можно проверить таблицей — как значения ложатся на шкалу и
/// когда графика нет вовсе.
nonisolated enum TrendSparkline {
    /// Меньше двух точек линии не получится.
    static let minimumPoints = 2

    /// Высоты точек от 0 (низ) до 1 (верх) по шкале от наименьшего значения
    /// ряда до наибольшего. Пусто, если точек мало.
    ///
    /// Ровный ряд — не плоская «линия на нуле», а середина: нулевой разброс
    /// ничего не говорит, и прижимать его к краю значило бы изображать
    /// падение.
    static func heights(_ values: [Double]) -> [Double] {
        guard values.count >= minimumPoints, let low = values.min(), let high = values.max() else { return [] }
        let span = high - low
        guard span > 0 else { return values.map { _ in 0.5 } }
        return values.map { ($0 - low) / span }
    }

    /// Изменение за весь ряд: последнее минус первое. nil, если точек мало.
    static func change(_ values: [Double]) -> Double? {
        guard values.count >= minimumPoints, let first = values.first, let last = values.last else { return nil }
        return last - first
    }
}
