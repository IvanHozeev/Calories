import Foundation
import SwiftUI
import Observation

/// Насколько подробно приложение объясняет свои числа.
///
/// Разным людям нужно разное. Новичок спрашивает «почему норма именно такая» и
/// «что теперь делать»; человек, который считает макросы третий год, знает это
/// лучше приложения, и длинная подпись у него только отнимает экран.
///
/// Разделять по возрасту было бы гаданием: и двадцатилетний, и сорокалетний
/// натурал хотят одного и того же. Различается не поколение, а опыт — поэтому
/// уровень человек выбирает сам, один раз, как в начале игры.
enum ExplanationLevel: String, CaseIterable, Identifiable, Sendable {
    /// Коротко: только суть. Для тех, кто и так знает, откуда берутся числа.
    case expert
    /// Подробно: почему число такое и что с ним делать.
    case novice

    var id: String { rawValue }

    var title: String {
        switch self {
        case .novice: return String(localized: "Подробно")
        case .expert: return String(localized: "Коротко")
        }
    }

    /// Чем эти уровни отличаются — одной строкой на выбор.
    var summary: String {
        switch self {
        case .novice: return String(localized: "Объясняем, откуда берутся числа и что с ними делать")
        case .expert: return String(localized: "Только суть, без разъяснений")
        }
    }

    static let key = "explanation_level"
}

/// Выбранный уровень — одним экземпляром на всё приложение.
///
/// Наблюдаемым объектом, а не просто чтением из настроек: иначе экраны,
/// открытые до переключения, остались бы со старыми подписями до перезапуска.
/// Тот же урок уже был с расписанием приёмов, где двух экземпляров настроек
/// хватило, чтобы тумблер не работал до перезапуска.
@Observable
@MainActor
final class ExplanationSettings {
    static let shared = ExplanationSettings()

    @ObservationIgnored private let defaults: UserDefaults

    var level: ExplanationLevel {
        didSet { defaults.set(level.rawValue, forKey: ExplanationLevel.key) }
    }

    /// Спрашивали ли человека вообще. Пока не спрашивали — объясняем подробно.
    var wasAsked: Bool {
        defaults.object(forKey: ExplanationLevel.key) != nil
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.level = defaults.string(forKey: ExplanationLevel.key)
            .flatMap(ExplanationLevel.init(rawValue:)) ?? .novice
    }
}

/// Пояснение — или ничего.
///
/// На коротком уровне подписи не сокращаются, а исчезают: человек, который
/// выбрал «Коротко», просил не объяснять, а не объяснять помельче. Поэтому
/// функция возвращает `nil`, и вызывающий просто не рисует строку.
///
/// Короткий вариант всё же можно передать — для мест, где строка несёт число
/// или правило, без которого экран становится загадкой. Таких мало, и каждое
/// такое место видно по наличию `short:`.
@MainActor
func explain(_ detailed: String, short: String? = nil) -> String? {
    guard ExplanationSettings.shared.level == .expert else { return detailed }
    return short
}

/// То же для подписей, которые задаются ключом локализации.
@MainActor
func explain(_ detailed: LocalizedStringKey, short: LocalizedStringKey? = nil) -> LocalizedStringKey? {
    guard ExplanationSettings.shared.level == .expert else { return detailed }
    return short
}
