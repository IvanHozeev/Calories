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

    /// Открывает лист добавления еды.
    ///
    /// Плюс на «Сегодня» теперь открывает меню — сканер, камера, ручное
    /// добавление, — потому что выбирать способ логичнее до входа, а не внутри
    /// уже открытого экрана. Поэтому тапов два, а не один.
    private func openAddEntry(in app: XCUIApplication) {
        app.navigationBars["Today"].buttons["addMenu"].tap()
        let add = app.buttons["Add food"]
        XCTAssertTrue(add.waitForExistence(timeout: 5), "В меню плюса нет ручного добавления")
        add.tap()
    }

    /// Список ленивый: то, что ниже экрана, в дереве элементов отсутствует.
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication, attempts: Int = 16) {
        var tries = 0
        while !element.exists && tries < attempts {
            app.swipeUp()
            tries += 1
        }
    }

    /// Прокручивает так, чтобы по элементу можно было именно нажать.
    ///
    /// Ни `exists`, ни `isHittable` для этого не годятся. В дереве у списка есть
    /// и соседние строки, а `isHittable` остаётся истинным даже когда строка
    /// прижата к нижней кромке: тап туда уходит в индикатор домой, ничего не
    /// открывается, и тест падает позже — на проверке, где причину уже не видно.
    /// Поэтому доводим элемент до середины экрана, а не до его края.
    private func scrollIntoReach(_ element: XCUIElement, in app: XCUIApplication, attempts: Int = 12) {
        // Смотрим на середину элемента, а не на его края. По краям высокая
        // карточка не влезает в «безопасную» полосу, даже когда видна целиком,
        // — и тест листал дальше, пока не уносил её за верх экрана, где строки
        // списка выгружаются и элемент перестаёт существовать вовсе.
        let top = 80.0
        let bottom = app.frame.height - 120
        for _ in 0..<attempts {
            if element.exists {
                let middle = element.frame.midY
                if middle > top && middle < bottom { return }
                // Уехал выше видимого — возвращаемся, а не листаем дальше.
                if middle <= top {
                    app.swipeDown()
                    continue
                }
            }
            app.swipeUp()
        }
    }

    /// Строка поиска живёт под тулбаром и появляется, только когда список
    /// подтягивают вниз, — поэтому в дереве её сразу может не быть.
    ///
    /// Тянем именно за список, а не за экран целиком: свайп от верхней кромки
    /// вытягивает Центр уведомлений, и он остаётся висеть поверх приложения —
    /// следующие тесты потом не находят даже таб-бар.
    @discardableResult
    private func revealSearchField(in app: XCUIApplication) -> XCUIElement {
        let search = app.searchFields.firstMatch
        let list = app.collectionViews.firstMatch
        var tries = 0
        while !search.exists && list.exists && tries < 8 {
            list.swipeDown()
            tries += 1
        }
        return search
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
        XCTAssertTrue(app.navigationBars["Pantry"].waitForExistence(timeout: 5),
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

        // Замеры — линейка в тулбаре «Тела», а не строка в параметрах
        app.buttons["openMeasurementsRow"].tap()
        XCTAssertTrue(app.navigationBars["Measurements"].waitForExistence(timeout: 5),
                      "Линейка в тулбаре не открыла «Замеры»")
        // Сам экран показывает выводы, а ввод живёт за плюсом в его тулбаре
        XCTAssertTrue(app.buttons["openMeasurementEntry"].exists,
                      "Ввод замеров должен открываться плюсом в тулбаре")
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

    /// Карточка макросов — вход в разбор дня. Раньше на ней жили три
    /// всплывающих окошка, и сравнить макросы между собой было нельзя.
    @MainActor
    func testMacrosCardOpensTheDayBreakdown() {
        let app = launchApp()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))

        let card = app.buttons["openDayNutrition"]
        scrollIntoReach(card, in: app)
        XCTAssertTrue(card.exists, "Карточка макросов должна быть на «Сегодня»")
        card.tap()

        XCTAssertTrue(app.navigationBars["Day breakdown"].waitForExistence(timeout: 5),
                      "Карточка не открыла разбор дня")
        XCTAssertTrue(app.staticTexts["Vitamins and minerals"].waitForExistence(timeout: 5),
                      "В разборе дня должны быть витамины и минералы")
    }

    /// Сквозная проверка микронутриентов: продукт встроенной базы приносит
    /// состав, и в дневнике у записи появляется значок того, чем она богата.
    ///
    /// Проверять есть что: состав живёт в файле каталога, подтягивается по
    /// названию продукта и пересчитывается на съеденные граммы. Любое звено
    /// этой цепочки можно порвать так, что приложение соберётся и промолчит.
    @MainActor
    func testDiaryShowsWhatAFoodIsRichIn() {
        let app = launchApp()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        openAddEntry(in: app)

        app.segmentedControls.firstMatch.buttons["Database"].tap()
        let search = revealSearchField(in: app)
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Spinach")

        let food = app.staticTexts["Spinach"]
        XCTAssertTrue(food.waitForExistence(timeout: 5), "Шпината нет во встроенной базе")
        food.tap()

        let addToMeal = app.buttons["addToMeal"]
        XCTAssertTrue(addToMeal.waitForExistence(timeout: 5))
        addToMeal.tap()

        let save = app.buttons["saveMeal"]
        if save.waitForExistence(timeout: 3) { save.tap() }

        // Шпинат богат фолатом: 194 мкг на сто грамм при норме 400.
        let badge = app.staticTexts["microTag-folate"]
        XCTAssertTrue(badge.waitForExistence(timeout: 10),
                      "У записи должен появиться значок нутриента, которым продукт богат")
    }

    /// Смысл экрана: заполняешь постепенно, и недостающее подсказывается по пропорциям.
    @MainActor
    func testMeasurementsSuggestMissingSites() {
        let app = launchApp(resetMeasurements: true)
        app.tabBars.buttons["Body"].tap()
        app.buttons["openMeasurementsRow"].tap()
        app.buttons["openMeasurementEntry"].tap()

        // Ввод только колесом: раскрываем строку правого бицепса и выбираем 40.
        // Ищем по идентификатору подписи: сама подпись «Бицепс» встречается ещё и
        // в таблице обхватов на экране результатов, который остался под этим.
        let row = app.staticTexts["site-biceps"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Не открылся экран замеров")
        // Руки идут после торса, а у каждого места на экране своя подсказка,
        // как его мерить: до бицепса надо доскроллить.
        scrollIntoReach(row, in: app)
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

    /// На экране порции внизу лежит то, ради чего на него зашли, а редкое
    /// пополнение справочника — иконкой в навбаре.
    @MainActor
    func testServingScreenPutsActionsWithinReach() {
        let app = launchApp()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        openAddEntry(in: app)

        // База продуктов живёт на своей вкладке источника
        app.segmentedControls.firstMatch.buttons["Database"].tap()

        // До продукта добираемся поиском, а не пролистыванием. Раньше во
        // встроенной базе было шесть десятков позиций и «Миндаль» находился
        // за десяток свайпов; теперь их почти три сотни, разложенных по
        // категориям, и орехи лежат глубже любого разумного числа свайпов.
        let search = revealSearchField(in: app)
        XCTAssertTrue(search.waitForExistence(timeout: 5), "Не показалась строка поиска")
        search.tap()
        search.typeText("Almonds")

        let food = app.staticTexts["Almonds"]
        XCTAssertTrue(food.waitForExistence(timeout: 5), "Не открылся лист добавления еды")
        food.tap()

        let addToMeal = app.buttons["addToMeal"]
        XCTAssertTrue(addToMeal.waitForExistence(timeout: 5), "Не открылся экран порции")

        let saveToMyFoods = app.buttons["saveToMyFoods"]
        XCTAssertTrue(saveToMyFoods.exists, "Сохранение в мои продукты должно быть в навбаре")

        // Действие приёма пищи ниже, чем пополнение справочника
        XCTAssertGreaterThan(addToMeal.frame.midY, saveToMyFoods.frame.midY,
                             "«В приём пищи» должно быть внизу, а закладка — наверху")
    }

    /// Забытый приём пищи должен вставать на своё время, а не на время записи.
    @MainActor
    func testMealCarriesTheTimeItWasEaten() {
        let app = launchApp()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        openAddEntry(in: app)

        // Время убрано с самого экрана: его меняют редко, поэтому оно живёт
        // за кнопкой с часами в тулбаре.
        let clock = app.buttons["mealTime"]
        XCTAssertTrue(clock.waitForExistence(timeout: 5), "Не открылся лист добавления еды")
        clock.tap()

        // В пикере есть и дата, и время — иначе поправить час невозможно
        let when = app.datePickers.firstMatch
        XCTAssertTrue(when.waitForExistence(timeout: 5), "Не открылся выбор времени приёма")
        XCTAssertGreaterThanOrEqual(when.buttons.count, 2,
                                    "У записи должны настраиваться и день, и время")
    }

    /// Источники разведены сегментами, чтобы поиск шёл по одному, а не по всем сразу.
    @MainActor
    func testFoodSourcesAreSeparated() {
        let app = launchApp()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        openAddEntry(in: app)

        let sources = app.segmentedControls.firstMatch
        XCTAssertTrue(sources.waitForExistence(timeout: 5), "Нет переключателя источника")
        for name in ["Recent", "Mine", "Database", "Online"] {
            XCTAssertTrue(sources.buttons[name].exists, "Нет источника «\(name)»")
        }

        // База разложена по категориям и появляется только на своей вкладке
        XCTAssertFalse(app.staticTexts["Meat and poultry"].exists,
                       "База не должна показываться на вкладке недавнего")
        sources.buttons["Database"].tap()
        let header = app.staticTexts["Meat and poultry"]
        scrollTo(header, in: app)
        XCTAssertTrue(header.exists, "База не открылась на своей вкладке")

        let second = app.staticTexts["Fish and seafood"]
        scrollTo(second, in: app)
        XCTAssertTrue(second.exists, "Категории должны идти отдельными секциями")

        // Поиск проверяем последним: он забирает фокус, а сегменты прячутся уже
        // по курсору в строке, и вернуть их внутри теста нечем — «Отмена» на этом
        // экране не одна, и попасть можно не в ту.
        let search = revealSearchField(in: app)
        if search.exists {
            search.tap()
            search.typeText("Beef")
            XCTAssertFalse(app.segmentedControls.firstMatch.exists,
                           "Во время поиска сегменты не должны притворяться рабочими")
            XCTAssertTrue(app.staticTexts["Beef"].waitForExistence(timeout: 5),
                          "Поиск должен находить продукт, не переключая источник")
        }
    }

    /// Выбор шрифта должен доезжать до интерфейса, а не только сохраняться.
    @MainActor
    func testFontChoiceIsOfferedAndPersists() {
        let app = launchApp()
        app.tabBars.buttons["Body"].tap()
        app.buttons["openSettings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))

        let entry = app.buttons["openFontSettings"]
        scrollTo(entry, in: app)
        XCTAssertTrue(entry.exists, "В настройках должен быть выбор шрифта")
        entry.tap()

        XCTAssertTrue(app.navigationBars["Font and size"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.sliders["textSizeSlider"].exists, "Размер текста должен настраиваться ползунком")
        for style in ["system", "rounded", "serif", "monospaced"] {
            XCTAssertTrue(app.buttons["font-\(style)"].exists, "Нет начертания «\(style)»")
        }

        // Регрессия: смена размера пересоздавала дерево и выбрасывала со экрана
        let slider = app.sliders["textSizeSlider"]
        slider.adjust(toNormalizedSliderPosition: 1.0)
        XCTAssertTrue(app.navigationBars["Font and size"].exists,
                      "Ползунок размера не должен выбрасывать с экрана")
        slider.adjust(toNormalizedSliderPosition: 0.0)
        XCTAssertTrue(app.navigationBars["Font and size"].exists,
                      "Возврат к мелкому размеру тоже не должен ронять навигацию")

        app.buttons["font-serif"].tap()
        app.navigationBars["Font and size"].buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Serif"].waitForExistence(timeout: 5),
                      "Выбранное начертание должно быть видно в настройках")
    }

    /// Случайный тап по уровню активности не должен молча менять норму калорий.
    @MainActor
    func testActivityLevelChangeAsksFirst() {
        let app = launchApp()
        app.tabBars.buttons["Body"].tap()
        XCTAssertTrue(app.navigationBars["Body"].waitForExistence(timeout: 5))

        // Уровень переживает прогоны, а тап по уже выбранному ничего не делает —
        // поэтому сначала уводим его в заведомо другое положение.
        let baseline = app.staticTexts["Sedentary"]
        scrollTo(baseline, in: app)
        baseline.tap()
        if app.alerts.firstMatch.waitForExistence(timeout: 2) {
            app.alerts.firstMatch.buttons["Change"].tap()
        }

        let target = app.staticTexts["Very Active"]
        scrollTo(target, in: app)
        XCTAssertTrue(target.exists, "Нет уровня активности «Very Active»")
        target.tap()

        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "Смена уровня должна спрашивать подтверждение")

        // Отмена оставляет всё как было
        alert.buttons["Cancel"].tap()
        XCTAssertFalse(app.alerts.firstMatch.exists)

        // А подтверждение применяет
        target.tap()
        app.alerts.firstMatch.buttons["Change"].tap()
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    /// Жалоба из жизни: первый тап по строке «не слышен». Подозрение на клавиатуру —
    /// после поиска она открыта, и тап может уходить на её закрытие.
    @MainActor
    func testFoodRowOpensOnTheFirstTapWhileSearching() {
        let app = launchApp()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        openAddEntry(in: app)

        let search = revealSearchField(in: app)
        XCTAssertTrue(search.exists, "Строка поиска не вытянулась из-под тулбара")
        search.tap()
        // Ввод идёт только когда фокус реально дошёл до поля: тап возвращается
        // раньше, чем поднимается клавиатура, и печать в этот зазор падает с
        // «Neither element nor any descendant has keyboard focus».
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5),
                      "Клавиатура не поднялась после тапа по поиску")
        search.typeText("Beef")

        // Поиск идёт по всем источникам, поэтому совпадений может быть несколько
        let row = app.staticTexts.matching(identifier: "Beef").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Поиск не нашёл продукт")
        row.tap()   // ровно один тап

        XCTAssertTrue(app.buttons["addToMeal"].waitForExistence(timeout: 3),
                      "Строка должна открываться с первого тапа, даже когда открыта клавиатура")
    }

    /// После добавления продукта экран должен остаться готовым к следующему:
    /// курсор в строке поиска, и найденное выше набранного приёма пищи.
    ///
    /// Без первого приходится каждый раз тянуться к строке пальцем, без второго
    /// список положенного отодвигает результаты вниз тем сильнее, чем больше
    /// набрал. Проверяем оба, потому что ломаются они порознь.
    @MainActor
    func testSearchStaysReadyAfterAddingToTheMeal() {
        let app = launchApp()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        openAddEntry(in: app)

        let search = revealSearchField(in: app)
        XCTAssertTrue(search.exists, "Строка поиска не вытянулась из-под тулбара")
        search.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5),
                      "Клавиатура не поднялась после тапа по поиску")
        search.typeText("Beef")

        let row = app.staticTexts.matching(identifier: "Beef").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Поиск не нашёл продукт")

        // Найденное — выше секции приёма пищи. Сравниваем координаты, а не
        // порядок в дереве: дерево у списка не обязано совпадать с тем, что видно.
        let mealHeader = app.staticTexts["Meal"].firstMatch
        if mealHeader.exists {
            XCTAssertGreaterThan(mealHeader.frame.minY, row.frame.minY,
                                 "Пока идёт поиск, приём пищи должен быть ниже найденного")
        }

        row.tap()
        let addToMeal = app.buttons["addToMeal"]
        XCTAssertTrue(addToMeal.waitForExistence(timeout: 3), "Экран порции не открылся")
        addToMeal.tap()

        // Курсор вернулся в поиск сам: клавиатура поднята, к строке не тянулись.
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5),
                      "После добавления курсор не вернулся в строку поиска")
    }

    // MARK: - Запись еды

    @MainActor
    func testQuickCaloriesReachTheRing() {
        let app = launchApp()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))

        openAddEntry(in: app)

        // Поле «только калории» убрано с экрана: оно мешало всё остальное время,
        // и теперь открывается из меню на плюсе.
        let addMenu = app.buttons["addMoreMenu"]
        XCTAssertTrue(addMenu.waitForExistence(timeout: 5), "Не открылся лист добавления еды")
        addMenu.tap()
        app.buttons["Calories only"].tap()

        let field = app.textFields["Kcal"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Не открылся ввод калорий")
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
        XCTAssertTrue(app.navigationBars["Pantry"].waitForExistence(timeout: 5))

        XCTAssertTrue(app.searchFields.firstMatch.exists,
                      "На «Моей еде» должна быть поисковая строка")
        // Счётчиков в подписях больше нет: «Мои продукты (128)» не влезало в
        // сегмент и обрезалось, а количество и так видно в самом списке.
        let sources = app.segmentedControls.firstMatch
        XCTAssertTrue(sources.waitForExistence(timeout: 5), "Нет переключателя разделов")
        for name in ["My Dishes", "My Foods", "Database"] {
            XCTAssertTrue(sources.buttons[name].exists, "Нет раздела «\(name)»")
        }
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
