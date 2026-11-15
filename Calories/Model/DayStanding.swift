import Foundation

/// Чем кончился день относительно нормы — одним словом для карточки дня.
///
/// То же правило, что у кольца в полоске недели (`DayMark.verdict`): недобор
/// считается промахом только когда он больше десятой части нормы. Двести
/// килокалорий из двух с половиной тысяч — обычная жизнь, и называть это
/// недобором значило бы ругать за ровно прожитый день.
nonisolated enum DayStanding: Equatable, Sendable {
    /// Записей нет — оценивать нечего.
    case empty
    /// В норме: от девяти десятых нормы до самой нормы.
    case onGoal
    /// Недобор: на сколько ккал не дотянул.
    case under(Int)
    /// Перебор: на сколько ккал вышел.
    case over(Int)

    init(consumed: Int, goal: Int, hasEntries: Bool) {
        guard hasEntries, goal > 0 else { self = .empty; return }
        if consumed > goal {
            self = .over(consumed - goal)
        } else if Double(consumed) < Double(goal) * (1 - DayMark.undershootShare) {
            self = .under(goal - consumed)
        } else {
            self = .onGoal
        }
    }
}
