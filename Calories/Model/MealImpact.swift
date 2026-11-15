import Foundation

/// Что порция делает с днём: сколько калорий останется и как закроется белок.
///
/// Экран порции раньше отвечал на один вопрос — сколько в ней калорий. Но
/// человек, который выбирает между «180 или 250 граммов», на самом деле
/// решает другое: влезет ли это в сегодняшнюю норму и не останется ли день
/// без белка. Эти два числа считаются здесь, заранее, а не после записи.
///
/// Чистая логика: день, набранное и порция приходят аргументами, времени и
/// хранилища здесь нет — поэтому проверяется таблицей.
nonisolated struct MealImpact: Equatable, Sendable {
    /// День до этого приёма.
    struct Day: Equatable, Sendable {
        /// Норма на сегодня.
        var goal: Int
        /// Съедено до этого приёма.
        var consumed: Int
        var macros: Macros
        var proteinTarget: Double?
        var fatTarget: Double?
        var carbsTarget: Double?
    }

    /// День и набранное в приёме — всё, что известно до выбора порции.
    struct Base: Equatable, Sendable {
        var day: Day
        /// Уже набрано в этом приёме: черновик не в дневнике, но съеден будет.
        var draftCalories: Int = 0
        var draftMacros: Macros = .zero
    }

    var day: Day
    var draftCalories: Int = 0
    var draftMacros: Macros = .zero
    /// Порция, которую выбирают.
    var thisCalories: Int
    var thisMacros: Macros

    init(day: Day, draftCalories: Int = 0, draftMacros: Macros = .zero,
         thisCalories: Int, thisMacros: Macros) {
        self.day = day
        self.draftCalories = draftCalories
        self.draftMacros = draftMacros
        self.thisCalories = thisCalories
        self.thisMacros = thisMacros
    }

    /// Порция поверх известной базы.
    init(base: Base, thisCalories: Int, thisMacros: Macros) {
        self.init(day: base.day, draftCalories: base.draftCalories, draftMacros: base.draftMacros,
                  thisCalories: thisCalories, thisMacros: thisMacros)
    }

    /// Съедено к концу этого приёма.
    var eatenAfter: Int { day.consumed + draftCalories + thisCalories }

    /// Сколько останется до нормы; отрицательное — перебор.
    var remainingAfter: Int { day.goal - eatenAfter }

    var isOver: Bool { remainingAfter < 0 }

    var macrosAfter: Macros { day.macros + draftMacros + thisMacros }

    /// Белка будет съедено, граммов.
    var proteinAfter: Double { macrosAfter.protein }

    /// Белок закрыт этим приёмом: до него нормы не было, с ним — есть.
    var closesProtein: Bool {
        guard let target = day.proteinTarget, target > 0 else { return false }
        return day.macros.protein + draftMacros.protein < target && proteinAfter >= target
    }
}
