import Testing
@testable import Calories

/// Правило «когда набранный приём нельзя терять молча». На самом листе
/// смахивание из юнит-теста не нажать, поэтому проверяем само правило.
@Suite struct MealDraftGuardTests {

    @Test func anEmptyDraftCanBeSwipedAway() {
        #expect(!MealDraftGuard.hasUnsavedWork(count: 0, appending: false))
    }

    @Test func anyAddedItemBlocksTheSwipe() {
        #expect(MealDraftGuard.hasUnsavedWork(count: 1, appending: false))
        #expect(MealDraftGuard.hasUnsavedWork(count: 4, appending: false))
    }

    @Test func theRecordBeingExtendedIsNotUnsavedWork() {
        // Открыли запись, чтобы дополнить, и ничего не добавили: в черновике
        // только она сама, и закрыть лист можно как обычно.
        #expect(!MealDraftGuard.hasUnsavedWork(count: 1, appending: true))
        #expect(MealDraftGuard.hasUnsavedWork(count: 2, appending: true))
    }
}
