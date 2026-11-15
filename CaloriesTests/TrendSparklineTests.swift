import Testing
import Foundation
@testable import Calories

/// Мини-график тренда веса в профиле.
struct TrendSparklineTests {
    @Test func tooFewPointsNoChart() {
        #expect(TrendSparkline.heights([]).isEmpty)
        #expect(TrendSparkline.heights([80]).isEmpty)
        #expect(TrendSparkline.change([80]) == nil)
    }

    /// Наименьшее — внизу, наибольшее — вверху, остальное между.
    @Test func theScaleRunsFromTheLowestToTheHighest() {
        let heights = TrendSparkline.heights([82.4, 81, 79.3])
        #expect(heights.first == 1)
        #expect(heights.last == 0)
        #expect(abs(heights[1] - (81 - 79.3) / (82.4 - 79.3)) < 1e-9)
    }

    /// Ровный ряд — середина, а не линия на дне.
    @Test func aFlatSeriesSitsInTheMiddle() {
        #expect(TrendSparkline.heights([80, 80, 80]) == [0.5, 0.5, 0.5])
    }

    @Test func theChangeIsLastMinusFirst() {
        #expect(abs((TrendSparkline.change([82.4, 81, 79.3]) ?? 0) - (-3.1)) < 1e-9)
        #expect(abs((TrendSparkline.change([79, 80]) ?? 0) - 1) < 1e-9)
    }
}
