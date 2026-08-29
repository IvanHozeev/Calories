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

        app.tabBars.buttons["Progress"].tap()
        XCTAssertTrue(app.navigationBars["Progress"].waitForExistence(timeout: 5),
                      "Вкладка «Прогресс» не открылась")

        app.tabBars.buttons["Food"].tap()
        XCTAssertTrue(app.navigationBars["My Food"].waitForExistence(timeout: 5),
                      "Вкладка «Еда» не открылась")

        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5),
                      "Возврат на «Сегодня» не сработал")
    }

    @MainActor
    func testSettingsTabOpensSettings() {
        let app = launchApp()
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5),
                      "Вкладка «Настройки» должна открывать настройки")
    }

    @MainActor
    func testSettingsOffersDataExport() {
        let app = launchApp()
        app.tabBars.buttons["Settings"].tap()
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

        // Запись должна появиться в дневнике за сегодня.
        XCTAssertTrue(app.staticTexts["777"].waitForExistence(timeout: 5)
                      || app.staticTexts.containing(NSPredicate(format: "label CONTAINS '777'")).count > 0,
                      "Добавленные калории не отобразились на «Сегодня»")
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
        app.tabBars.buttons["Progress"].tap()
        XCTAssertTrue(app.navigationBars["Progress"].waitForExistence(timeout: 5))

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
        app.tabBars.buttons["Progress"].tap()
        XCTAssertTrue(app.navigationBars["Progress"].waitForExistence(timeout: 5))

        app.staticTexts["Personal plan"].tap()
        XCTAssertTrue(app.navigationBars["Subscription"].waitForExistence(timeout: 5),
                      "Без премиума карточка плана должна открывать пейволл")
    }
}
