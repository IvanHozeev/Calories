import XCTest

/// UI-тесты держат в узде то, чего не видят юнит-тесты: навигацию и то, что данные
/// действительно доезжают до экрана. Все регрессии интерфейса этой недели —
/// съехавшая дуга кольца, обрезанная ось графика, белая рамка вокруг карточки —
/// ловились глазами, а не сборкой.
final class CaloriesUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Запускаем в предсказуемых условиях: английская локаль, онбординг пропущен.
    /// Оба параметра — обычные перекрытия UserDefaults через аргументы запуска,
    /// поэтому в самом приложении не нужен тестовый код.
    private func launchApp(premium: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-onboarding_completed", "YES",
            "-is_premium", premium ? "YES" : "NO"
        ]
        app.launch()
        return app
    }

    // MARK: - Навигация

    @MainActor
    func testAllThreeTabsOpen() {
        let app = launchApp()

        XCTAssertTrue(app.staticTexts["Today"].waitForExistence(timeout: 5),
                      "Приложение должно открываться на вкладке «Сегодня»")

        app.tabBars.buttons["Body"].tap()
        XCTAssertTrue(app.navigationBars["Body"].waitForExistence(timeout: 5),
                      "Вкладка «Тело» не открылась")

        app.tabBars.buttons["Food"].tap()
        XCTAssertTrue(app.navigationBars["My Food"].waitForExistence(timeout: 5),
                      "Вкладка «Еда» не открылась")

        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5),
                      "Возврат на «Сегодня» не сработал")
    }

    @MainActor
    func testSettingsReachableFromBody() {
        let app = launchApp()
        app.tabBars.buttons["Body"].tap()
        app.buttons["openSettings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5),
                      "Шестерёнка на «Теле» должна вести в настройки")
    }

    /// Вход в замеры должен быть виден на пустом экране, иначе фичу просто не найдут.
    @MainActor
    func testBodyTabOffersFirstMeasurement() {
        let app = launchApp()
        app.tabBars.buttons["Body"].tap()
        XCTAssertTrue(app.navigationBars["Body"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["addMeasurement"].exists, "В тулбаре должна быть кнопка добавления замера")
        XCTAssertTrue(app.staticTexts["Weight and trend"].exists, "Вес должен открываться из «Тела»")
    }

    @MainActor
    func testSettingsOffersDataExport() {
        let app = launchApp()
        app.tabBars.buttons["Body"].tap()
        app.buttons["openSettings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))

        let backup = app.buttons["Backup (JSON)"]
        // Экспорт лежит внизу списка — доскроллим.
        var attempts = 0
        while !backup.isHittable && attempts < 8 {
            app.swipeUp()
            attempts += 1
        }
        XCTAssertTrue(backup.exists, "В настройках должна быть выгрузка резервной копии")
        XCTAssertTrue(app.buttons["Diary as a table (CSV)"].exists,
                      "В настройках должна быть выгрузка дневника в CSV")
    }

    /// Слипшиеся при вводе цифры не должны попадать в историю: один такой замер
    /// ломает и график, и все производные отношения в отчёте.
    @MainActor
    func testMeasurementRejectsImplausibleValue() {
        let app = launchApp()
        app.tabBars.buttons["Body"].tap()
        app.buttons["addMeasurement"].tap()

        let chest = app.textFields["field-chest-right"]
        XCTAssertTrue(chest.waitForExistence(timeout: 5), "Не открылась форма замера")
        chest.tap()
        chest.typeText("10878828196")

        XCTAssertTrue(app.staticTexts["range-chest"].waitForExistence(timeout: 2),
                      "Должна появиться подсказка с ожидаемым диапазоном")
        XCTAssertFalse(app.buttons["saveMeasurement"].isEnabled,
                       "Сохранение должно быть заблокировано при неправдоподобном значении")

        // Живое значение снимает блокировку
        chest.tap()
        for _ in 0..<11 { chest.typeText(XCUIKeyboardKey.delete.rawValue) }
        chest.typeText("108")

        XCTAssertFalse(app.staticTexts["range-chest"].exists, "Подсказка должна исчезнуть")
        XCTAssertTrue(app.buttons["saveMeasurement"].isEnabled,
                      "С правдоподобным значением сохранение должно быть доступно")
    }

    // MARK: - Запись еды

    @MainActor
    func testQuickCaloriesReachTheRing() {
        let app = launchApp()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))

        app.navigationBars["Today"].buttons.element(boundBy: app.navigationBars["Today"].buttons.count - 1).tap()

        let field = app.textFields["Kcal"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Не открылся лист добавления еды")
        field.tap()
        field.typeText("777")

        app.buttons["Save"].firstMatch.tap()

        // Запись должна появиться в дневнике за сегодня. Список лежит под карточками,
        // поэтому доскролливаем: SwiftUI не держит в дереве строки далеко за экраном.
        let entry = app.staticTexts["777"]
        var attempts = 0
        while !entry.exists && attempts < 6 {
            app.swipeUp()
            attempts += 1
        }
        XCTAssertTrue(entry.exists, "Добавленные калории не отобразились на «Сегодня»")
    }

    // MARK: - Еда

    @MainActor
    func testFoodTabHasSearchAndSegments() {
        let app = launchApp()
        app.tabBars.buttons["Food"].tap()
        XCTAssertTrue(app.navigationBars["My Food"].waitForExistence(timeout: 5))

        XCTAssertTrue(app.searchFields.firstMatch.exists,
                      "На «Моей еде» должна быть поисковая строка")
        XCTAssertTrue(app.buttons["Dishes (0)"].exists || app.buttons.containing(
            NSPredicate(format: "label BEGINSWITH 'Dishes'")).count > 0,
                      "Должен быть сегмент «Блюда» со счётчиком")
    }

    // MARK: - Покупки

    /// Проверяем структуру пейволла, но не сами продукты: конфигурация StoreKit
    /// применяется только к запуску по схеме из Xcode, а SKTestSession живёт в процессе
    /// тест-раннера и до приложения в UI-тесте не достаёт. Загрузку продуктов надо
    /// проверять руками, запустив приложение из Xcode.
    @MainActor
    func testPaywallStructure() {
        let app = launchApp(premium: false)
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))

        app.staticTexts["Personal plan"].tap()
        XCTAssertTrue(app.navigationBars["Subscription"].waitForExistence(timeout: 5))

        XCTAssertTrue(app.buttons["Restore"].exists,
                      "Восстановление покупок обязательно для App Review")
        XCTAssertTrue(app.staticTexts["Plan progress right on the main screen"].exists,
                      "Перечень фич должен быть переведён, а не падать на русский исходник")
    }

    // MARK: - Премиум-гейт

    @MainActor
    func testPlanCardShowsPaywallWithoutPremium() {
        let app = launchApp(premium: false)
        // Карточка плана теперь единственный вход — она на «Сегодня».
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))

        app.staticTexts["Personal plan"].tap()
        XCTAssertTrue(app.navigationBars["Subscription"].waitForExistence(timeout: 5),
                      "Без премиума карточка плана должна открывать пейволл")
    }
}
