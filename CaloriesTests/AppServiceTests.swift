import Testing
import UIKit
import Foundation
import SwiftData
@testable import Calories

// MARK: - StepStore

@MainActor
struct StepStoreTests {

    // Свой suite на каждый тест — боевые настройки приложения не трогаем (см. TestDefaults)
    private let defaults = TestDefaults.make()

    private func makeStore(goal: Int? = nil) -> StepStore {
        if let goal {
            defaults.set(goal, forKey: "step_goal")
        }
        return StepStore(defaults: defaults, groupDefaults: nil)
    }

    @Test func defaultStepGoal_is10000() {
        let store = makeStore()
        #expect(store.stepGoal == 10_000)
    }

    @Test func stepGoal_persistsToUserDefaults() {
        let store = makeStore()
        store.stepGoal = 7_500
        #expect(defaults.integer(forKey: "step_goal") == 7_500)
    }

    @Test func stepGoal_loadsFromUserDefaults() {
        let store = makeStore(goal: 5_000)
        #expect(store.stepGoal == 5_000)
    }

    @Test func initialStepsToday_isZero() {
        let store = makeStore()
        #expect(store.stepsToday == 0)
    }

    @Test func initialDistanceToday_isZero() {
        let store = makeStore()
        #expect(store.distanceTodayKm == 0)
    }

    @Test func initialActiveCalories_isZero() {
        let store = makeStore()
        #expect(store.activeCaloriesToday == 0)
    }

    @Test func initialWeekHistory_isEmpty() {
        let store = makeStore()
        #expect(store.weekHistory.isEmpty)
    }

    @Test func initialMonthHistory_isEmpty() {
        let store = makeStore()
        #expect(store.monthHistory.isEmpty)
    }

    @Test func initialGoalStreak_isZero() {
        let store = makeStore()
        #expect(store.goalStreak == 0)
    }

    @Test func initialWeeklyTotal_isZero() {
        let store = makeStore()
        #expect(store.weeklyTotal == 0)
    }
}

// MARK: - ReminderStore

@MainActor
struct ReminderStoreTests {

    // Свой suite на каждый тест — боевые настройки приложения не трогаем (см. TestDefaults)
    private let defaults = TestDefaults.make()

    private func makeStore() -> ReminderStore {
        ReminderStore(defaults: defaults)
    }

    @Test func hasThreeReminders() {
        let store = makeStore()
        #expect(store.reminders.count == 3)
    }

    @Test func reminderIds_areCorrect() {
        let store = makeStore()
        let ids = store.reminders.map(\.id)
        #expect(ids.contains("breakfast"))
        #expect(ids.contains("lunch"))
        #expect(ids.contains("dinner"))
    }

    @Test func reminderTitles_arePresent() {
        let store = makeStore()
        #expect(store.reminders.allSatisfy { !$0.title.isEmpty })
    }

    @Test func defaultAppEnabled_isFalse() {
        let store = makeStore()
        #expect(!store.appEnabled)
    }

    @Test func appEnabled_persistsToUserDefaults() {
        let store = makeStore()
        store.appEnabled = true
        #expect(defaults.bool(forKey: "reminders_app_enabled") == true)
        store.appEnabled = false
    }

    @Test func disableNotifications_setsAppEnabledFalse() {
        let store = makeStore()
        store.appEnabled = true
        store.disableNotifications()
        #expect(!store.appEnabled)
    }

    @Test func saveAndReschedule_persistsReminderState() {
        let store = makeStore()
        store.reminders[0].isEnabled = true
        store.saveAndReschedule()
        #expect(defaults.bool(forKey: "reminder_breakfast_on") == true)
    }

    @Test func saveAndReschedule_persistsReminderTime() {
        let store = makeStore()
        let newTime = Date(timeIntervalSince1970: 3600 * 9)
        store.reminders[0].time = newTime
        store.saveAndReschedule()
        let saved = defaults.object(forKey: "reminder_breakfast_time") as? TimeInterval
        #expect(saved != nil)
    }
}

// MARK: - Покупки

import StoreKitTest
import StoreKit

/// Юнит-тесты хостятся внутри процесса приложения, поэтому SKTestSession здесь реально
/// подменяет StoreKit для самого приложения — в UI-тесте это не работает, там раннер
/// и приложение разные процессы.
@MainActor
struct PurchaseServiceTests {

    private func makeSession() throws -> SKTestSession {
        let session = try SKTestSession(configurationFileNamed: "Products")
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        return session
    }

    // ИЗВЕСТНАЯ ПРОБЛЕМА: SKTestSession поднимается без ошибок, но Product.products(for:)
    // возвращает пустой список и не бросает — StoreKit отвечает, что таких продуктов нет.
    // Конфиг лежит в бандле теста, идентификаторы совпадают, формат приведён к каноническому.
    // Тест оставлен включённым намеренно: он падает и будет напоминать о нерешённом.
    @Test(.disabled("Product.products(for:) возвращает пустой список под SKTestSession — не разобрано")) func loadsAllConfiguredProducts() async throws {
        let session = try makeSession()
        defer { session.clearTransactions() }

        let service = PurchaseService()
        await service.load()

        #expect(service.products.count == 3, "Должны загрузиться две подписки и разовая покупка")
        #expect(service.subscriptions.count == 2)
        #expect(service.lifetime != nil)
        #expect(service.loadFailed == false)
    }

    @Test func noEntitlementsMeansNoPremium() async throws {
        let session = try makeSession()
        defer { session.clearTransactions() }

        let service = PurchaseService()
        await service.load()

        #expect(service.isPremium == false, "Без покупок премиума быть не должно")
    }

    @Test(.disabled("Product.products(for:) возвращает пустой список под SKTestSession — не разобрано")) func purchaseGrantsPremium() async throws {
        let session = try makeSession()
        defer { session.clearTransactions() }

        let service = PurchaseService()
        await service.load()
        let monthly = try #require(service.products.first { $0.id == PurchaseService.ProductID.monthly })

        await service.purchase(monthly)

        #expect(service.isPremium == true, "После покупки подписки премиум должен включиться")
        #expect(service.purchasedIDs.contains(PurchaseService.ProductID.monthly))
    }
}

// MARK: - Локализация

/// Проверяет каталог целиком, чтобы не открывать приложение на восьми языках руками.
/// Ловит два класса ошибок, на которых мы уже спотыкались: ключ есть, а переводов у него
/// нет (строка молча падает на русский исходник), и разъехавшиеся спецификаторы формата,
/// от которых текст ломается или приложение падает при подстановке.
struct LocalizationTests {

    private static let languages = ["en", "es", "pt", "fr", "de", "ar", "he"]

    /// Читает скомпилированный Localizable.strings конкретной локали из бандла приложения.
    private static func strings(for language: String) -> [String: String] {
        guard let url = Bundle.main.url(forResource: "Localizable", withExtension: "strings",
                                        subdirectory: nil, localization: language),
              let dict = NSDictionary(contentsOf: url) as? [String: String]
        else { return [:] }
        return dict
    }

    private static func specifiers(in text: String) -> [String] {
        // «%%» — это экранированный процент, и его надо съесть целиком, иначе
        // второй знак начинает новый разбор: в «%% de» класс флагов проглатывает
        // пробел, и появляется несуществующий «%d». Ловилось это только в тех
        // языках, где после процента идёт слово на d, f или s.
        let pattern = #"%%|%(?:\d+\$)?[-+ 0#]*[\d.]*(?:lld|ld|@|d|f|s)"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        }
        .filter { $0 != "%%" }
        // Сравниваем только типы подстановок. Порядок в переводе меняется, и тогда
        // появляется позиционная форма «%1$lld» — это тот же аргумент, что и «%lld».
        .map { $0.replacingOccurrences(of: #"^%(\d+\$)?[-+ 0#]*[\d.]*"#,
                                       with: "%", options: .regularExpression) }
        .sorted()
    }

    @Test func everyLanguageIsPresent() {
        for language in Self.languages {
            #expect(!Self.strings(for: language).isEmpty,
                    "Локаль \(language) не собралась в бандл")
        }
    }

    @Test func noLanguageFallsBackToRussian() {
        let cyrillic = try! NSRegularExpression(pattern: "[А-Яа-яЁё]")
        for language in Self.languages where language != "ru" {
            let table = Self.strings(for: language)
            let untranslated = table.filter { _, value in
                let range = NSRange(value.startIndex..., in: value)
                return cyrillic.firstMatch(in: value, range: range) != nil
            }
            #expect(untranslated.isEmpty,
                    "В локали \(language) остался русский текст: \(untranslated.keys.sorted().prefix(5))")
        }
    }

    @Test func formatSpecifiersMatchAcrossLanguages() {
        let russian = Self.strings(for: "ru")
        for language in Self.languages {
            let table = Self.strings(for: language)
            for (key, translated) in table {
                guard let source = russian[key] ?? (key.isEmpty ? nil : key) else { continue }
                let expected = Self.specifiers(in: source)
                guard !expected.isEmpty else { continue }
                #expect(Self.specifiers(in: translated) == expected,
                        "Спецификаторы разъехались в \(language) для ключа «\(key)»")
            }
        }
    }
}

// MARK: - Обновление виджета шагов

/// У виджетов системный бюджет перестроений. Раньше приложение просило
/// обновиться на каждое сообщение HealthKit — то есть тратило батарею на то,
/// чтобы виджет из-за троттлинга обновлялся реже. Здесь проверяется, что
/// теперь оно просит только там, где человек увидит разницу.
struct StepWidgetRefreshTests {
    private let calendar = Calendar(identifier: .gregorian)
    private func date(_ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour))!
    }

    @Test func newDayAlwaysRefreshes() {
        // Иначе виджет до первой сотни шагов показывал бы вчерашний итог.
        #expect(StepStore.shouldRefreshWidget(
            steps: 0, goal: 10_000, lastSteps: 12_000, lastGoalReached: true,
            lastPushedAt: date(6, 23), lastPushedDay: date(6, 23),
            now: date(7, 1), calendar: calendar))
    }

    @Test func reachingTheGoalRefreshesImmediately() {
        // Ради этого момента на виджет и смотрят — ждать десять минут нельзя.
        #expect(StepStore.shouldRefreshWidget(
            steps: 10_001, goal: 10_000, lastSteps: 9_990, lastGoalReached: false,
            lastPushedAt: date(7, 12), lastPushedDay: date(7, 12),
            now: date(7, 12).addingTimeInterval(30), calendar: calendar))
    }

    @Test func aFewStepsDoNotRefresh() {
        #expect(!StepStore.shouldRefreshWidget(
            steps: 6_547, goal: 10_000, lastSteps: 6_540, lastGoalReached: false,
            lastPushedAt: date(7, 12), lastPushedDay: date(7, 12),
            now: date(7, 13), calendar: calendar))
    }

    @Test func aLongWalkTooSoonAfterTheLastRefreshWaits() {
        // Прошли достаточно, но виджет обновляли минуту назад: экран блокировки
        // не обязан пересчитываться каждую минуту прогулки.
        #expect(!StepStore.shouldRefreshWidget(
            steps: 6_900, goal: 10_000, lastSteps: 6_500, lastGoalReached: false,
            lastPushedAt: date(7, 12), lastPushedDay: date(7, 12),
            now: date(7, 12).addingTimeInterval(60), calendar: calendar))
    }

    @Test func aLongWalkAfterAPauseRefreshes() {
        #expect(StepStore.shouldRefreshWidget(
            steps: 6_900, goal: 10_000, lastSteps: 6_500, lastGoalReached: false,
            lastPushedAt: date(7, 12), lastPushedDay: date(7, 12),
            now: date(7, 12).addingTimeInterval(900), calendar: calendar))
    }
}

// MARK: - Резервная копия

/// Копия, из которой нельзя восстановиться, — не копия. И копия, в которой не
/// всё, тем более: замеры и дни голодания раньше в неё не попадали, то есть
/// человек считал бы себя защищённым, а часть истории всё равно потерял.
@MainActor
@Suite(.serialized)
struct BackupTests {
    private let container: ModelContainer
    private let store: CalorieStore

    init() async throws {
        container = try ModelContainer(
            for: FoodEntry.self, FoodItem.self, WeightEntry.self, GoalRecord.self, Dish.self,
            BodyMeasurement.self, FastDay.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        store = CalorieStore(context: container.mainContext,
                             defaults: TestDefaults.make(), groupDefaults: nil)
        store.dailyGoal = 2100
    }

    private func fillDiary() {
        store.add(name: "Овсянка", calories: 300, macros: Macros(protein: 10, fat: 5, carbs: 50), grams: 250)
        store.addWeight(77.4)
        store.addCustomFood(name: "Творог мой", caloriesPer100g: 90,
                            protein: 17, fat: 1, carbs: 3, category: .dairy, defaultGrams: 200)
        store.addMeasurement(BodyMeasurement(date: Date(), neckCm: 39, bicepsLeftCm: 38, bicepsRightCm: 39))
        _ = store.markFastDay(Date(), kind: .dry)
    }

    @Test func aBackupCarriesEverythingIncludingMeasurementsAndFasts() {
        fillDiary()
        let backup = store.makeBackup()

        #expect(backup.entries.count == 1)
        #expect(backup.weights.count == 1)
        #expect(backup.products.count == 1)
        // Категория раньше в копию не попадала, и после восстановления свой
        // продукт оказывался в «Другом».
        #expect(backup.products.first?.category == FoodCategory.dairy.rawValue)
        #expect(backup.measurements?.count == 1)
        #expect(backup.fastDays?.count == 1)
        #expect(backup.fastDays?.first?.kind == FastKind.dry.rawValue)
    }

    @Test func restoringReplacesWhateverIsThereNow() {
        fillDiary()
        let backup = store.makeBackup()

        // После снимка человек наел лишнего и записал не тот вес — ровно та
        // ситуация, ради которой восстановление и существует.
        store.add(name: "Ошибка", calories: 5000)
        store.addWeight(99)
        #expect(store.entries.count == 2)

        store.restore(from: backup)

        #expect(store.entries.count == 1)
        #expect(store.entries.first?.name == "Овсянка")
        #expect(store.weightEntries.count == 1)
        #expect(abs((store.weightEntries.first?.weightKg ?? 0) - 77.4) < 0.01)
        #expect(store.measurements.count == 1)
        #expect(store.fastDays.count == 1)
        #expect(store.customFoods.first?.foodCategory == .dairy)
        #expect(store.dailyGoal == 2100)
    }

    /// Копия обязана нести состав приёма: без него восстановление стирало бы
    /// ровно то, ради чего состав и заводился — продукты внутри приёма для
    /// «Недавнего» и категории рациона для разбора дня.
    @Test func aBackupCarriesWhatTheMealWasMadeOf() throws {
        store.add(name: "Хала, Молоко", calories: 400, components: [
            EntryComponent(name: "Хала", calories: 300, grams: 100),
            EntryComponent(name: "Молоко", calories: 100, grams: 200),
        ])

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(CaloriesBackup.self, from: try encoder.encode(store.makeBackup()))

        store.restore(from: decoded)

        let restored = try #require(store.entries.first { $0.name == "Хала, Молоко" })
        #expect(restored.components.map(\.name) == ["Хала", "Молоко"])
        #expect(restored.components.first?.grams == 100)
    }

    /// Копии, снятые до того, как состав начали хранить, обязаны читаться
    /// дальше: у человека их накоплено за месяцы.
    @Test func anOldBackupWithoutCompositionStillRestores() throws {
        let json = """
        {"appVersion": "3", "dailyGoal": 2100, "exportedAt": "2026-09-01T10:00:00Z",
         "entries": [{"name": "Овсянка", "calories": 300, "protein": 10, "fat": 5,
                      "carbs": 50, "grams": 100, "date": "2026-09-01T08:00:00Z"}],
         "weights": [], "products": [], "dishes": [], "goalHistory": [], "measurements": []}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(CaloriesBackup.self, from: Data(json.utf8))

        store.restore(from: backup)

        #expect(store.entries.count == 1)
        #expect(store.entries.first?.components.isEmpty == true)
    }

    @Test func restoringSurvivesAFullEncodeAndDecode() throws {
        fillDiary()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(store.makeBackup())
        let decoded = try decoder.decode(CaloriesBackup.self, from: data)
        store.add(name: "Мусор", calories: 1)
        store.restore(from: decoded)

        #expect(store.entries.count == 1)
        #expect(store.measurements.count == 1)
        #expect(store.fastDays.count == 1)
    }

    @Test func anOlderBackupWithoutTheNewFieldsStillLoads() throws {
        // Копия, снятая до того, как в файл добавили замеры и голодания. Отказать
        // в ней — значит выбросить всю историю человека из-за пары новых полей.
        let json = """
        {
          "exportedAt": "2026-01-15T10:00:00Z",
          "appVersion": "1.0",
          "profile": null,
          "plan": null,
          "dailyGoal": 1900,
          "entries": [{"name":"Каша","calories":250,"protein":8,"fat":4,"carbs":45,"grams":200,
                       "date":"2026-01-15T07:30:00Z"}],
          "weights": [{"weightKg":76.2,"date":"2026-01-15T07:00:00Z"}],
          "products": [{"name":"Свой сыр","caloriesPer100g":300,"protein":25,"fat":22,
                        "carbs":1,"defaultGrams":30}],
          "dishes": [],
          "goalHistory": []
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(CaloriesBackup.self, from: Data(json.utf8))

        #expect(backup.measurements == nil)
        #expect(backup.fastDays == nil)
        #expect(backup.products.first?.category == nil)

        store.restore(from: backup)
        #expect(store.entries.count == 1)
        #expect(store.customFoods.count == 1)
        // Категории в старом файле не было — продукт честно ложится в «Другое»,
        // а не роняет восстановление.
        #expect(store.customFoods.first?.foodCategory == .other)
        #expect(store.dailyGoal == 1900)
    }
}

/// Расписание и уборка старых копий — без файловой системы: обе функции чистые
/// именно ради этого.
struct BackupScheduleTests {
    @Test func theFirstBackupHappensImmediately() {
        #expect(BackupService.shouldBackup(last: nil, now: Date()))
    }

    @Test func aBackupMadeAnHourAgoWaits() {
        let now = Date()
        #expect(!BackupService.shouldBackup(last: now.addingTimeInterval(-3600), now: now))
    }

    @Test func aBackupOlderThanADayHappens() {
        let now = Date()
        #expect(BackupService.shouldBackup(last: now.addingTimeInterval(-25 * 3600), now: now))
    }

    @Test func nothingIsDeletedWhileThereIsRoom() {
        let names = (1...5).map { "calories-backup-2026-09-0\($0)-1000.json" }
        #expect(BackupService.obsoleteBackups(among: names, keepLast: 14).isEmpty)
    }

    @Test func theOldestGoFirstWhenThereAreTooMany() {
        let names = (1...9).map { "calories-backup-2026-09-0\($0)-1000.json" }
        let obsolete = BackupService.obsoleteBackups(among: names, keepLast: 3)
        #expect(obsolete.count == 6)
        #expect(obsolete.first == "calories-backup-2026-09-01-1000.json")
        #expect(!obsolete.contains("calories-backup-2026-09-09-1000.json"))
    }

    @Test func otherFilesInTheFolderAreLeftAlone() {
        // Папку человек выбирает сам, и в ней вполне может лежать его собственное.
        let names = ["заметки.txt", "фото.jpg", "calories-backup-2026-09-01-1000.json"]
        #expect(BackupService.obsoleteBackups(among: names, keepLast: 0) == ["calories-backup-2026-09-01-1000.json"])
    }
}

// MARK: - Ввод чисел

/// На русской и израильской раскладках десятичный разделитель — запятая, а
/// `Double("1,5")` возвращает nil. Замена запятой жила в четырнадцати местах
/// по вьюхам: забыл в одном поле — и «1,5» молча превращается в ноль.
struct DecimalInputTests {
    @Test func aCommaMeansTheSameAsADot() {
        #expect("1,5".decimalValue == 1.5)
        #expect("1.5".decimalValue == 1.5)
        #expect(" 76,15 ".decimalValue == 76.15, "Пробелы по краям — не повод терять число")
    }

    @Test func nonsenseIsNotANumber() {
        #expect("".decimalValue == nil)
        #expect("кг".decimalValue == nil)
        #expect("".decimalValueOrZero == 0, "Где пусто значит «нет», ноль уместен")
    }
}

// MARK: - Щелчки кольца

struct RingTicksTests {

    @Test func fullTurn_clicksEveryNotch() {
        let times = RingTicks.crossingTimes(from: 0, to: 360)
        #expect(times.count == 12)
        #expect(times == times.sorted())
        #expect((times.last ?? 0) <= RingTicks.duration)
    }

    @Test func clicksThinOutTowardsTheEnd() {
        // Колесо докручивается: промежутки между щелчками к концу растут.
        let times = RingTicks.crossingTimes(from: 0, to: 720)
        let gaps = zip(times.dropFirst(), times).map { $0 - $1 }
        #expect((gaps.last ?? 0) > (gaps[gaps.count / 2]))
    }

    @Test func turnFromMidway_startsAtTheNextNotch() {
        #expect(RingTicks.crossingTimes(from: 45, to: 360).count == 11)
    }

    /// По умолчанию — прежний звук колеса, чтобы у тех, кто не заходил
    /// в настройки, ничего не поменялось.
    @Test func ringSound_defaultsToTheWheel() {
        let saved = UserDefaults.standard.string(forKey: RingSound.defaultsKey)
        defer { UserDefaults.standard.set(saved, forKey: RingSound.defaultsKey) }
        UserDefaults.standard.removeObject(forKey: RingSound.defaultsKey)
        #expect(RingSound.current == .wheel)
        #expect(RingSound.wheel.soundID == 1157)
    }

    /// «Без звука» действительно без звука, а у остальных звуки разные.
    @Test func ringSound_offIsSilentAndOthersDiffer() {
        #expect(RingSound.off.soundID == nil)
        let ids = RingSound.allCases.compactMap(\.soundID)
        #expect(ids.count == RingSound.allCases.count - 1)
        #expect(Set(ids).count == ids.count)
    }
}
