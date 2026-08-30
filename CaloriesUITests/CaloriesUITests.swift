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
    private func launchApp(premium: Bool = false, resetMeasurements: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-onboarding_completed", "YES",
            "-is_premium", premium ? "YES" : "NO",
            "-ui_test_reset_measurements", resetMeasurements ? "YES" : "NO"
        ]
        app.launch()
        return app
    }

    /// Список ленивый: то, что ниже экрана, в дереве элементов отсутствует.
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication, attempts: Int = 8) {
        var tries = 0
        while !element.exists && tries < attempts {
            app.swipeUp()
            tries += 1
        }
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
        // Профиль расформирован: параметры тела лежат прямо на вкладке.
        XCTAssertTrue(app.staticTexts["Body Parameters"].exists,
                      "Параметры тела должны быть на вкладке, а не за ячейкой профиля")
        XCTAssertTrue(app.buttons["openWeight"].exists, "Динамика веса должна открываться из «Тела»")

        // Два входа в замеры: ячейка в параметрах и линейка в тулбаре для быстроты
        XCTAssertTrue(app.buttons["openMeasurementsRow"].exists, "Ячейка «Замеры» должна остаться")
        app.buttons["openMeasurements"].tap()
        XCTAssertTrue(app.navigationBars["Measurements"].waitForExistence(timeout: 5),
                      "Ячейка «Замеры» не открылась")
        XCTAssertTrue(app.staticTexts["Neck"].exists,
                      "Замеры вводятся прямо в списке, без отдельного листа")
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

    /// Смысл экрана: заполняешь постепенно, и недостающее подсказывается по пропорциям.
    @MainActor
    func testMeasurementsSuggestMissingSites() {
        let app = launchApp(resetMeasurements: true)
        app.tabBars.buttons["Body"].tap()
        app.buttons["openMeasurements"].tap()

        // Ввод только колесом: раскрываем строку правого бицепса и выбираем 40
        // Идентификатор на строке перекрыл бы идентификаторы вложенных подсказок,
        // поэтому строку ищем по подписи.
        let row = app.staticTexts["Biceps"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Не открылся экран замеров")
        row.tap()

        // Парное место раскрывает два колеса: левое и правое
        XCTAssertTrue(app.pickerWheels.element(boundBy: 1).waitForExistence(timeout: 5),
                      "У парного места должно быть два колеса")
        XCTAssertEqual(app.pickerWheels.count, 2)
        app.pickerWheels.element(boundBy: 1).adjust(toPickerWheelValue: "40")
        row.tap()   // свернуть колесо, иначе соседние строки уезжают за экран

        // Предплечье не мерили — должна появиться серая оценка около 32, сразу
        let forearmHint = app.staticTexts["hint-forearm-right"]
        scrollTo(forearmHint, in: app)
        XCTAssertEqual(forearmHint.label, "≈ 32",
                       "Незаполненное место должно подсказываться по пропорциям")
        XCTAssertTrue(app.staticTexts["≈ 80% of biceps"].exists,
                      "Подсказка должна объяснять, откуда взялось число")

        // Вторая сторона той же мышцы — самый надёжный ориентир
        let bicepsLeftHint = app.staticTexts["hint-biceps-left"]
        scrollTo(bicepsLeftHint, in: app)
        XCTAssertEqual(bicepsLeftHint.label, "≈ 40",
                       "Непомеренная сторона должна подсказываться по померенной")
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
