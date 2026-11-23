import Testing
import SwiftUI
@testable import Calories

/// Объёмные дуги кольца дня: свет должен смотреть вправо-вниз на экране, а не на кольце.
struct RubberArcsTests {
    @Test func offsetStaysPutWithoutTurn() {
        let size = RubberArcs.offset(3, 5, compensating: 0)
        #expect(abs(size.width - 3) < 1e-9)
        #expect(abs(size.height - 5) < 1e-9)
    }

    @Test func offsetTurnsAQuarterClockwise() {
        // Вниз при повороте на 90° по часовой уходит влево: так экран видит это смещение,
        // если кольцо потом повернуть обратно.
        let size = RubberArcs.offset(0, 1, compensating: 90)
        #expect(abs(size.width + 1) < 1e-9)
        #expect(abs(size.height) < 1e-9)
    }

    @Test func compensationCancelsTheRingRotation() {
        // Кольцо стоит повёрнутым на -40°: смещение, повёрнутое на +40°, после этого
        // возвращается ровно туда, куда смотрело изначально.
        let compensated = RubberArcs.offset(2, 4, compensating: 40)
        let onScreen = RubberArcs.offset(compensated.width, compensated.height, compensating: -40)
        #expect(abs(onScreen.width - 2) < 1e-9)
        #expect(abs(onScreen.height - 4) < 1e-9)
    }
}
