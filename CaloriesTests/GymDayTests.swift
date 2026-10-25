import Testing
import Foundation
@testable import Calories

/// Про какой день в зале стоит сказать, а про какой промолчать.
///
/// Подсказка про углеводы стоит ровно одного: в день ног и спины они
/// работают, потому что эти группы съедают гликогена больше, чем руки за всю
/// неделю. В день рук, в день отдыха и в день, о котором ничего не известно,
/// строки быть не должно — иначе она станет фоном и перестанет значить
/// что-либо.
@Suite struct GymDayTests {

    private let calendar = Calendar.current

    private func state(type: String?, name: String? = nil, isRest: Bool = false,
                       daysAgo: Int = 0) -> GymBridge.State {
        let date = calendar.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        return GymBridge.State(
            date: date,
            today: GymBridge.State.Today(name: name, type: type, isRest: isRest)
        )
    }

    @Test func legDayAsksForCarbs() {
        let today = state(type: "Legs", name: "Ноги")
        #expect(GymBridge.isHeavyDay(today) == true)
        #expect(GymBridge.todayName(today) == "Ноги")
    }

    @Test func backAndFullBodyCountToo() {
        #expect(GymBridge.isHeavyDay(state(type: "Pull")) == true)
        #expect(GymBridge.isHeavyDay(state(type: "Full Body")) == true)
    }

    /// День рук — обычный день: ради него говорить нечего.
    @Test func armDaySaysNothing() {
        #expect(GymBridge.isHeavyDay(state(type: "Arms")) == false)
        #expect(GymBridge.isHeavyDay(state(type: "Shoulders")) == false)
    }

    @Test func aRestDayIsNotHeavy() {
        let today = state(type: "Legs", isRest: true)
        #expect(GymBridge.isHeavyDay(today) == false)
        #expect(GymBridge.todayName(today) == nil)
    }

    /// Тренировка вне программы приходит без типа — судить не о чем, и это
    /// не то же самое, что «день лёгкий».
    @Test func aWorkoutOutsideAProgramIsUnknown() {
        #expect(GymBridge.isHeavyDay(state(type: nil)) == nil)
    }

    /// Вчерашний день ног про сегодня не говорит ничего.
    @Test func yesterdaysLegDayIsNotTodays() {
        #expect(GymBridge.isHeavyDay(state(type: "Legs", daysAgo: 1)) == nil)
    }

    /// Своё имя человека важнее нашего слота, но без него сгодится и слот —
    /// лишь бы строка не вышла пустой.
    @Test func theSplitSlotStandsInForAMissingName() {
        #expect(GymBridge.todayName(state(type: "Legs")) == "Legs")
    }

    @Test func noNeighbourMeansNoHint() {
        #expect(GymBridge.isHeavyDay(nil) == nil)
        #expect(GymBridge.todayName(nil) == nil)
    }
}
