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
    /// - Parameter health: объявить доступ к «Здоровью» выданным. Нужно
    ///   там, где экран лежит за чипом шагов: без доступа чип открывает не
    ///   экран, а системное окно доступа, которое из теста нечем закрыть.
    /// - Parameter seedMeasurements: посеять два сеанса замеров. История
    ///   замеров открывается только со второго — по одному её не бывает.
    private func launchApp(premium: Bool = false, resetMeasurements: Bool = false,
                           health: Bool = false, seedMeasurements: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-onboarding_completed", "YES",
            // Заставка поверх первого кадра перехватывала первые нажатия теста.
            "-show_launch_splash", "NO",
            // Системное окно доступа к «Здоровью» на свежей установке перекрывало
            // вкладки. Тот же флаг ставит «не сейчас» в онбординге.
            "-health_access_deferred", "YES",
            "-is_premium", premium ? "YES" : "NO",
            "-ui_test_reset_measurements", resetMeasurements ? "YES" : "NO",
            // Шрифт и кегль — к известному состоянию, но сбросом, а не
            // подменой значения.
            //
            // Их выбирает один из тестов и оставляет выбранными: следующий
            // прогон начинался с засечек и мелкого кегля, строки съезжали, и
            // тест про шрифт падал на собственном следе. Держалось это на
            // том, что `Tools/test.sh` удаляет оба ключа перед прогоном, —
            // то есть тест был верен только при запуске через скрипт, а
            // запущенный из Xcode по одному падал.
            //
            // Задать их аргументом запуска нельзя: аргументы ложатся поверх
            // хранилища и читаются раньше него, так что выбор, сделанный
            // внутри теста, перестал бы читаться вовсе — а он-то и
            // проверяется.
            "-ui_test_reset_appearance", "YES",
            "-health_pretend_authorized", health ? "YES" : "NO",
            "-ui_test_seed_measurements", seedMeasurements ? "YES" : "NO"
        ]
        app.launch()
        // Ждём, пока интерфейс действительно встанет, и только потом отдаём
        // приложение тесту.
        //
        // Дальше каждый тест проверяет свой навбар с ожиданием в пять секунд,
        // и на загруженной машине они кончались раньше, чем приложение
        // успевало показать хоть что-то. Флак ловился в разных тестах и каждый
        // раз выглядел по-новому — то «нет карточки», то «нет вкладки», — то
        // есть указывал куда угодно, кроме настоящей причины.
        _ = app.tabBars.firstMatch.waitForExistence(timeout: 30)
        return app
    }

    /// Открывает лист добавления еды.
    ///
    /// Плюс на «Сегодня» теперь открывает меню — сканер, камера, ручное
    /// добавление, — потому что выбирать способ логичнее до входа, а не внутри
    /// уже открытого экрана. Поэтому тапов два, а не один.
    private func openAddEntry(in app: XCUIApplication) {
        app.navigationBars["Today"].buttons["addMenu"].tap()
        let add = app.buttons["Meal"]
        XCTAssertTrue(add.waitForExistence(timeout: 5), "В меню плюса нет ручного добавления")
        add.tap()
    }

    /// Открывает настройки.
    ///
    /// Своей вкладки у них нет: шестерёнка стоит в шапке «Профиля», рядом с
    /// остальным про самого человека, а «Сегодня» осталось про сегодняшний день.
    private func openSettings(in app: XCUIApplication) {
        // Сначала сам экран, потом кнопка в его шапке: на загруженной машине
        // ожидание сразу кнопки кончалось раньше, чем приложение успевало
        // нарисовать экран, и тест падал на «нет настроек» там, где их
        // просто ещё не было на экране.
        let profileTab = app.tabBars.buttons["Profile"]
        XCTAssertTrue(profileTab.waitForExistence(timeout: 10), "Нет вкладки «Профиль»")
        profileTab.tap()
        XCTAssertTrue(app.navigationBars["Profile"].waitForExistence(timeout: 10),
                      "«Профиль» не открылся")
        let gear = app.navigationBars["Profile"].buttons["openSettings"]
        XCTAssertTrue(gear.waitForExistence(timeout: 10), "В шапке «Профиля» нет настроек")
        gear.tap()
    }

    /// Нажимает «В приём пищи» на экране порции.
    ///
    /// Не сразу: на этом экране курсор сам встаёт в поле веса, и поднявшаяся
    /// клавиатура двигает панель кнопок вверх. Тап по координатам, снятым до
    /// этого, уходит мимо — тест жмёт не ту кнопку и оказывается на «Сегодня».
    private func addToMeal(in app: XCUIApplication) {
        let button = app.buttons["addToMeal"]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "Экран порции не открылся")
        // Курсор на этом экране встаёт в поле веса сам. На устройстве панель
        // кнопок поднимается над клавиатурой, но в симуляторе с подключённой
        // клавиатурой Mac вместо неё снизу висит узкая полоса подсказок — она
        // кнопки и накрывает, и тап уходит в неё. Убираем её тем же жестом,
        // что и человек: протянуть список вниз.
        if app.keyboards.firstMatch.waitForExistence(timeout: 3) {
            app.swipeDown()
            Thread.sleep(forTimeInterval: 0.4)
        }
        button.tap()
    }

    /// Выбирает пункт в меню-фильтре тулбара.
    ///
    /// Источник и раздел больше не полоса сегментов: она занимала строку
    /// экрана и обрезала подписи. Теперь это кнопка-меню, и путь к выбору —
    /// два тапа, а не один.
    private func pickFromMenu(_ button: String, item: String, in app: XCUIApplication) {
        let menu = app.descendants(matching: .any).matching(identifier: button).firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 5), "Нет меню «\(button)»")
        menu.tap()
        let option = app.buttons[item].firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 5), "В меню нет пункта «\(item)»")
        option.tap()
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

    /// Строка продукта в результатах поиска. Ищем по метке среди любых
    /// элементов, а не по `staticTexts["Beef"]`: этот запрос перестал находить
    /// строку (почему именно, не выяснялось), хотя на экране она есть.
    func foodRow(_ name: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", name)).firstMatch
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

    // MARK: - Онбординг

    /// Онбординг проходится одними «Далее», спрашивает доступ к шагам своим
    /// шагом, а не системным окном на старте, и кончается на «Сегодня».
    @MainActor
    func testOnboardingWalksThroughToToday() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-onboarding_completed", "NO",
            "-show_launch_splash", "NO",
        ]
        app.launch()

        let start = app.buttons["Get Started"]
        XCTAssertTrue(start.waitForExistence(timeout: 30), "Онбординг не открылся")
        start.tap()

        // Шагов с настройкой несколько; доходим «Далее» до шага с доступом к шагам.
        // На шаге цели выбираем поддержание: план с дефицитом запустил бы
        // пробный период, и следующие тесты получили бы премиум, которого не ждут.
        let health = app.buttons["onboardingHealthAccess"]
        let maintenance = app.buttons["Maintenance"]
        var taps = 0
        while !health.exists && taps < 14 {
            if maintenance.exists, !maintenance.isSelected {
                // Шаг въезжает сбоку: тап посреди перехода попадал по соседнему
                // сегменту («Набор»), и план всё равно создавался.
                Thread.sleep(forTimeInterval: 0.6)
                maintenance.tap()
                XCTAssertTrue(maintenance.isSelected, "Не удалось выбрать поддержание")
            }
            app.buttons["Next"].tap()
            taps += 1
        }
        XCTAssertTrue(health.waitForExistence(timeout: 5), "Нет шага с доступом к шагам")

        app.buttons["Next"].tap()
        XCTAssertTrue(app.staticTexts["Ready?"].waitForExistence(timeout: 5), "Нет итогового шага")
        app.buttons["Get Started"].tap()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 10),
                      "После онбординга должно открываться «Сегодня»")
        // Без плана пробный период не начат — строка плана зовёт в пэйвол.
        XCTAssertTrue(app.staticTexts["Personal plan"].waitForExistence(timeout: 5),
                      "Поддержание не должно создавать план и пробный период")
    }

    // MARK: - Навигация

    @MainActor
    func testAllTabsOpen() {
        let app = launchApp()

        XCTAssertTrue(app.staticTexts["Today"].waitForExistence(timeout: 5),
                      "Приложение должно открываться на вкладке «Сегодня»")

        app.tabBars.buttons["Profile"].tap()
        XCTAssertTrue(app.navigationBars["Profile"].waitForExistence(timeout: 5),
                      "Вкладка «Профиль» не открылась")
        // Вкладки «Еда» больше нет: свои продукты и блюда живут в экране
        // добавления, а склад без записи в дневник был лишним.
        XCTAssertFalse(app.tabBars.buttons["Food"].exists)

        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5),
                      "Возврат на «Сегодня» не сработал")
    }

    @MainActor
    func testSettingsOpenFromProfile() {
        let app = launchApp()
        openSettings(in: app)
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5),
                      "Шестерёнка в шапке «Профиля» должна открывать настройки")
        // Своей вкладки нет, и на «Сегодня» шестерёнки больше нет: один вход,
        // иначе человек гадает, который из них настоящий.
        XCTAssertFalse(app.tabBars.buttons["Settings"].exists)
        app.navigationBars["Settings"].buttons.firstMatch.tap()
        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 10),
                      "«Сегодня» не открылось")
        XCTAssertFalse(app.buttons["openSettings"].exists,
                       "Шестерёнка уехала в «Профиль» — на «Сегодня» её быть не должно")
    }

    /// Включённое деление дня должно быть видно на «Сегодня».
    ///
    /// Фича была сделана целиком, но тумблер лежал в «Напоминаниях», а
    /// «Сегодня» читало свой экземпляр настроек, прочитанный на запуске, —
    /// то есть включить её было негде и незаметно.
    @MainActor
    func testMealScheduleStripShowsUpWhenTheDayIsSplit() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-onboarding_completed", "YES",
            "-show_launch_splash", "NO",
            "-health_access_deferred", "YES",
            "-meal_schedule_on", "YES",
        ]
        app.launch()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 30))

        let strip = app.descendants(matching: .any).matching(identifier: "mealScheduleStrip").firstMatch
        XCTAssertTrue(strip.waitForExistence(timeout: 10),
                      "День делится на приёмы, а строки ближайшего приёма на «Сегодня» нет")
    }

    /// Вход в приёмы пищи живёт в профиле: это про режим человека — подъём,
    /// отбой, число приёмов, — а не про то, как выглядит приложение.
    @MainActor
    func testProfileHasTheWayIntoMealSchedule() {
        let app = launchApp()
        let profile = app.tabBars.buttons["Profile"]
        XCTAssertTrue(profile.waitForExistence(timeout: 10))
        profile.tap()

        let entrance = app.descendants(matching: .any).matching(identifier: "openMealSchedule").firstMatch
        scrollTo(entrance, in: app)
        XCTAssertTrue(entrance.exists, "В настройках нет своей строки приёмов пищи")
        entrance.tap()
        XCTAssertTrue(app.switches["mealScheduleToggle"].firstMatch.waitForExistence(timeout: 5),
                      "Экран приёмов пищи не открылся")
    }

    // MARK: - Каждый экран открывается

    /// Доводит до экрана и возвращается обратно.
    ///
    /// Сеть под навигацию: не проверяет, что на экране написано, — только
    /// что он вообще открывается и отпускает назад. Этого хватает, чтобы
    /// поймать оборванный переход, а дороже ничего и не нужно: содержимое
    /// каждого экрана проверяется модульными тестами там, где оно
    /// считается.
    @MainActor
    private func visit(_ identifier: String, expecting title: String,
                       in app: XCUIApplication, inList: Bool = true) {
        let row = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        if inList {
            scrollTo(row, in: app)
        }
        guard row.waitForExistence(timeout: 5) else {
            XCTFail("Нет входа «\(identifier)»")
            return
        }
        // Листать до того, что лежит в шапке, нечего: она на месте всегда, а
        // свайпы увели бы список под ней и сбили бы попадание.
        if inList {
            scrollIntoReach(row, in: app)
        }
        row.tap()
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 10),
                      "Не открылся «\(title)»")
        back(from: title, in: app)
    }

    /// Назад из пушнутого экрана — кнопкой в шапке.
    ///
    /// По её системному имени, а не по порядку в шапке: порядок задаёт экран,
    /// и шеврон оказывается первым не везде — на «Приёмах пищи» тап уходил не
    /// туда. Имя у шеврона всегда `BackButton`, а подпись у него меняется,
    /// потому что её берут с экрана, с которого вошли.
    ///
    /// Жест от левого края сюда не годится: он срабатывает не на каждом
    /// экране — там, где под пальцем горизонтальная прокрутка, его забирает
    /// она.
    ///
    /// Возврат проверяется по тому, что покинутый экран исчез, а не по
    /// названию того, куда вернулись. У корневых вкладок название меняется на
    /// прокрутке: пока тест листал «Профиль» до нужной строки, заголовок там
    /// успевал стать «Параметрами тела», и ждать слова «Профиль» было
    /// бессмысленно.
    @MainActor
    private func back(from title: String, in app: XCUIApplication) {
        let chevron = app.navigationBars[title].buttons["BackButton"]
        guard chevron.waitForExistence(timeout: 5) else {
            XCTFail("На «\(title)» нет кнопки «назад»")
            return
        }
        chevron.tap()
        XCTAssertTrue(app.navigationBars[title].waitForNonExistence(timeout: 10),
                      "«\(title)» не закрылся кнопкой «назад»")
    }

    /// Всё, что открывается с «Сегодня».
    @MainActor
    func testEveryScreenOffTodayOpens() {
        // С подпиской и с доступом к «Здоровью»: без подписки полоска плана
        // открывает не план, а предложение подписки, а без доступа чип шагов
        // просит доступ вместо экрана. И то и другое — верное поведение, но
        // тогда оба экрана остались бы непройденными.
        let app = launchApp(premium: true, health: true)
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 10))

        // Имя на элементе тулбара, а не внутри чипа: идентификатор на
        // внешнем элементе перекрывает вложенные.
        visit("steps", expecting: "Steps", in: app, inList: false)
        // «Новый план», а не «План»: пока плана нет, экран плана и есть его
        // настройка — показывать на нём нечего. Готовый план за той же
        // полоской проверяет `testPlanEditorOpensFromTheToolbar`.
        visit("planStrip", expecting: "New plan", in: app)
    }

    /// Всё, что открывается из «Настроек», включая отладочные экраны:
    /// они тоже ломаются, а чинить их никто не ходит, пока не понадобятся.
    @MainActor
    func testEverySettingsScreenOpens() {
        let app = launchApp()
        openSettings(in: app)

        visit("openRingSound", expecting: "Ring sound", in: app)
        visit("openFontSettings", expecting: "Font and size", in: app)
        visit("openAutoBackup", expecting: "Automatic backup", in: app)

        let debug = app.buttons["Debug"].firstMatch
        scrollTo(debug, in: app)
        XCTAssertTrue(debug.exists, "В настройках нет входа в отладку")
        scrollIntoReach(debug, in: app)
        debug.tap()
        XCTAssertTrue(app.navigationBars["Debug"].waitForExistence(timeout: 10))

        // «Что есть в Здоровье» сюда не попадает, и не потому, что экран не
        // важен. Он при появлении сам спрашивает доступ к «Здоровью», а
        // системное окно доступа рисует другой процесс: в дереве приложения
        // его нет, закрыть его из теста нечем, и оно остаётся висеть — тап
        // «назад» уходит в него, экран не закрывается, а следующий тест падает
        // на чужом окне. Проверяется он руками.
        for (label, title) in [("Sleep: what arrived", "Sleep: what arrived")] {
            let row = app.buttons[label].firstMatch
            scrollTo(row, in: app)
            XCTAssertTrue(row.exists, "В отладке нет «\(label)»")
            row.tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 10),
                          "Не открылся «\(title)»")
            back(from: title, in: app)
        }
    }

    /// Всё, что открывается из «Профиля».
    ///
    /// Разделён на два теста, и не ради порядка: на тест отведена минута, а
    /// впятером эти экраны укладывались в шестьдесят две секунды — тест падал
    /// от длины, а не от поломки. Поднять предел изнутри не вышло: XCTest
    /// берёт его раньше, чем отрабатывает `setUp`, и остаётся при своей
    /// минуте. Разрезать дешевле, чем договариваться с ним флагами, которых
    /// в CI всё равно не будет.
    @MainActor
    func testEveryProfileScreenOpens() {
        let app = launchApp()
        openProfile(in: app)

        visit("openWeight", expecting: "Weight and trend", in: app)
        visit("openMealSchedule", expecting: "Meals", in: app)
        visit("openKosher", expecting: "Kashrut", in: app)
    }

    /// Замеры и их история — вторая половина обхода «Профиля».
    ///
    /// История лежит за замерами, поэтому идём вглубь, а не возвращаемся на
    /// «Профиль» между шагами. И открывается она только со второго сеанса —
    /// отсюда посев.
    @MainActor
    func testTheMeasurementScreensOpen() {
        let app = launchApp(seedMeasurements: true)
        openProfile(in: app)

        let measurements = app.descendants(matching: .any)
            .matching(identifier: "openMeasurementsRow").firstMatch
        scrollTo(measurements, in: app)
        XCTAssertTrue(measurements.exists, "В профиле нет входа в замеры")
        scrollIntoReach(measurements, in: app)
        measurements.tap()
        XCTAssertTrue(app.navigationBars["Measurements"].waitForExistence(timeout: 10),
                      "Строка замеров не открыла экран замеров")
        visit("openMeasurementHistory", expecting: "Measurement history", in: app)
        back(from: "Measurements", in: app)
    }

    /// Открыть «Профиль» и дождаться, пока он встанет.
    ///
    /// Ждём вкладку в таббаре, а не название в шапке. Заголовок корневой
    /// вкладки меняется на прокрутке: доехав до секции, шапка называется её
    /// именем, и «Профиль» в ней уже не пишется. Это та же ловушка, которую
    /// обходит `back(from:in:)`, — а в начале теста она осталась, и обход
    /// замеров падал двумя прогонами из шести. Заметил это не набор, а шесть
    /// полных прогонов подряд: тест, падающий один раз из трёх, читается как
    /// случайность, пока его не прогонят пять раз.
    ///
    /// С посеянными замерами промахов больше: на «Профиле» появляется секция
    /// выводов, список становится выше, и у шапки есть куда переименоваться
    /// ещё до первого жеста.
    @MainActor
    private func openProfile(in app: XCUIApplication) {
        let tab = app.tabBars.buttons["Profile"]
        XCTAssertTrue(tab.waitForExistence(timeout: 10), "В таббаре нет «Профиля»")
        tab.tap()
        // Признак того, что вкладка открылась, — её собственная строка, а не
        // слово в шапке.
        let anchor = app.descendants(matching: .any)
            .matching(identifier: "openWeight").firstMatch
        XCTAssertTrue(anchor.waitForExistence(timeout: 10), "«Профиль» не открылся")
    }

    // MARK: - Вёрстка

    /// Кольцо не должно наезжать на полоску взвешивания.
    ///
    /// Наезжало дважды, и оба раза находил человек, а не набор: первый —
    /// когда блок первого экрана схлопывался клавиатурой из-под листа,
    /// второй — когда диаметр кольца стали считать от одной ширины, и оно
    /// перестало умещаться в отведённую высоту. Глазами такое ловится
    /// случайно, координатами — всегда.
    @MainActor
    func testTheRingDoesNotOverlapTheWeighInRow() {
        let app = launchApp()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 10))

        let ring = app.descendants(matching: .any).matching(identifier: "addFromRing").firstMatch
        XCTAssertTrue(ring.waitForExistence(timeout: 10), "Кольца нет на экране")
        let weighIn = app.descendants(matching: .any).matching(identifier: "weighInRow").firstMatch
        guard weighIn.waitForExistence(timeout: 5) else {
            // Взвесились сегодня — строки нет, и проверять нечего.
            return
        }

        XCTAssertLessThanOrEqual(
            ring.frame.maxY, weighIn.frame.minY,
            "Кольцо (\(ring.frame)) наезжает на полоску взвешивания (\(weighIn.frame))")
    }

    /// Под кольцом не больше одной главной подсказки (ТЗ-1).
    ///
    /// Раньше советы были отдельными строками и могли говорить разное
    /// одновременно. Теперь их выбирает одна очередь — и строка одна.
    @MainActor
    func testTodayShowsAtMostOneHint() {
        let app = launchApp()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 10))
        let hints = app.descendants(matching: .any).matching(identifier: "dayHintMain")
        XCTAssertLessThanOrEqual(hints.count, 1, "На «Сегодня» больше одной главной подсказки")
    }

    /// Клавиатура из-под листа не трогает экран под ним.
    ///
    /// Лист с калориями поднимает клавиатуру, а она сужает безопасную область
    /// всему, что ниже, — и «Сегодня» сжималось вместе с ней: кольцо мельчало,
    /// плитки лезли на него. Проверяем по самому кольцу: его прямоугольник до
    /// показа листа и после закрытия должен совпасть.
    @MainActor
    func testTheKeyboardUnderASheetLeavesTodayAlone() {
        let app = launchApp()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 10))

        let ring = app.descendants(matching: .any).matching(identifier: "addFromRing").firstMatch
        XCTAssertTrue(ring.waitForExistence(timeout: 10), "Кольца нет на экране")
        let before = ring.frame

        app.navigationBars["Today"].buttons["addMenu"].tap()
        let quick = app.buttons["Calories only"].firstMatch
        XCTAssertTrue(quick.waitForExistence(timeout: 5), "В меню нет быстрых калорий")
        quick.tap()
        // Поле ввода с клавиатурой — ради неё лист и открывали.
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10),
                      "Лист открылся без клавиатуры — проверять нечего")

        app.buttons["Cancel"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 10))
        XCTAssertTrue(ring.waitForExistence(timeout: 10))

        XCTAssertEqual(ring.frame.width, before.width, accuracy: 1,
                       "Кольцо изменило ширину из-за клавиатуры под листом")
        XCTAssertEqual(ring.frame.height, before.height, accuracy: 1,
                       "Кольцо изменило высоту из-за клавиатуры под листом")
        XCTAssertEqual(ring.frame.minY, before.minY, accuracy: 1,
                       "Кольцо уехало по вертикали из-за клавиатуры под листом")
    }

    /// Названия вкладок начинаются на одной вертикали.
    ///
    /// Средний слот тулбара к левому краю не прижимается — он центрует то,
    /// что в нём лежит, — и «Профиль» стоял посреди шапки, пока «Рацион» с
    /// длинным названием выглядел правильным. Разницу в двадцать точек глаз
    /// замечает только рядом, а вкладки рядом не показать.
    @MainActor
    func testTabTitlesShareTheSameLeftEdge() {
        let app = launchApp()

        func titleLeft(_ tab: String, bar: String) -> CGFloat {
            if tab != "Today" { app.tabBars.buttons[tab].tap() }
            let navBar = app.navigationBars[bar]
            XCTAssertTrue(navBar.waitForExistence(timeout: 10), "Нет шапки «\(bar)»")
            // Самую широкую из одноимённых: название экрана система держит в
            // шапке дважды — наше и своё, скрытое, — и запрос по имени
            // возвращает оба. Видимое из них шире.
            let titles = navBar.staticTexts.allElementsBoundByIndex.filter { $0.label == bar }
            guard let title = titles.max(by: { $0.frame.width < $1.frame.width }) else {
                XCTFail("В шапке нет названия «\(bar)»")
                return 0
            }
            return title.frame.minX
        }

        let today = titleLeft("Today", bar: "Today")
        let profile = titleLeft("Profile", bar: "Profile")
        let pantry = titleLeft("Pantry", bar: "Pantry")

        XCTAssertEqual(profile, today, accuracy: 1,
                       "«Профиль» начинается не там, где «Сегодня»")
        XCTAssertEqual(pantry, today, accuracy: 1,
                       "«Рацион» начинается не там, где «Сегодня»")
    }

    /// Вкладка «Рацион» открывает экран всей еды: свои блюда, свои продукты
    /// и база. Оттуда же свой продукт правится — категорию и состав иначе
    /// поменять было негде.
    @MainActor
    func testPantryTabOpensTheFoodScreen() {
        let app = launchApp()
        // «Pantry» — английская локаль, на которой идёт набор.
        let tab = app.tabBars.buttons["Pantry"]
        XCTAssertTrue(tab.waitForExistence(timeout: 10), "Нет вкладки рациона")
        tab.tap()

        // Раздел выбирается меню в тулбаре: своих продуктов, блюд и базы.
        let menu = app.descendants(matching: .any).matching(identifier: "sectionFilter").firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 10), "На вкладке рациона нет выбора раздела")
        menu.tap()
        // «Foods», а не «My Foods»: слово «Мои» из названий разделов убрали,
        // а тест остался с прежним — и падал с тех пор молча, потому что в
        // обычный прогон UI-тесты не входят.
        XCTAssertTrue(app.buttons["Foods"].firstMatch.waitForExistence(timeout: 5),
                      "В меню нет своих продуктов")
        XCTAssertTrue(app.buttons["Database"].firstMatch.exists, "И базы продуктов тоже")
        app.buttons["Database"].firstMatch.tap()
    }

    /// Вход в замеры должен быть виден на пустом экране, иначе фичу просто не найдут.
    @MainActor
    func testBodyTabOffersFirstMeasurement() {
        let app = launchApp()
        app.tabBars.buttons["Profile"].tap()
        XCTAssertTrue(app.navigationBars["Profile"].waitForExistence(timeout: 5))
        // Профиль расформирован: параметры тела лежат прямо на вкладке.
        // Доскроллить обязательно: сверху теперь карточка расчёта, а список
        // ленивый — то, что ниже экрана, в дереве элементов отсутствует.
        let bodyParameters = app.staticTexts["Body Parameters"]
        scrollTo(bodyParameters, in: app)
        XCTAssertTrue(bodyParameters.exists,
                      "Параметры тела должны быть на вкладке, а не за ячейкой профиля")
        XCTAssertTrue(app.buttons["openWeight"].exists, "Динамика веса должна открываться из «Тела»")

        // Замеры — пятой строкой в параметрах тела, рядом с ростом и весом:
        // это такой же параметр, просто снимаемый лентой. Взвешивание из
        // этого тулбара уехало на «Сегодня»: его делают каждое утро, и ради
        // него больше не нужно заходить в профиль.
        let measurements = app.buttons["openMeasurementsRow"]
        scrollTo(measurements, in: app)
        measurements.tap()
        XCTAssertTrue(app.navigationBars["Measurements"].waitForExistence(timeout: 5),
                      "Строка в параметрах тела не открыла «Замеры»")
        // Сам экран показывает выводы, а ввод живёт за плюсом в его тулбаре
        XCTAssertTrue(app.buttons["openMeasurementEntry"].exists,
                      "Ввод замеров должен открываться линейкой в тулбаре")
    }

    @MainActor
    func testSettingsOffersDataExport() {
        let app = launchApp()
        openSettings(in: app)
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
        // Макросы есть всегда: они считаются по любой записи, чем бы она ни
        // была. А витамины — только у продуктов встроенной базы, и секция
        // показывается, лишь когда есть что показать: раньше она стояла
        // всегда и чаще объясняла, почему чисел нет.
        let macros = app.staticTexts["Protein, fat, carbs"]
        scrollTo(macros, in: app)
        XCTAssertTrue(macros.exists, "В разборе дня должны быть макросы")
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

        let search = revealSearchField(in: app)
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Spinach")

        // firstMatch обязателен: после первого же прогона шпинат оседает
        // в «Недавнем», и на следующем запуске строк с этим названием две —
        // в недавнем и в базе. Без него тест зелёный ровно один раз на
        // чистом симуляторе, а дальше падает на «multiple matching elements».
        // По метке, а не по типу: после «быстрого добавления» строка с
        // названием может быть не статическим текстом, а кнопкой.
        let food = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] 'Spinach'")).firstMatch
        XCTAssertTrue(food.waitForExistence(timeout: 5), "Шпината нет во встроенной базе")
        food.tap()

        addToMeal(in: app)

        // Именно проверка, а не «если появилась»: без сохранения записи в дневнике
        // не будет, и падать тест станет на значке — там, где причину уже не видно.
        // Нижний бар перестраивается вместе со свёрнутой строкой поиска, и на
        // это уходит больше, чем занимает обычное появление кнопки.
        let save = app.buttons["saveMeal"]
        XCTAssertTrue(save.waitForExistence(timeout: 10), "Кнопка сохранения приёма пищи не появилась")
        save.tap()

        // Шпинат богат фолатом: 194 мкг на сто грамм при норме 400.
        //
        // До строки надо доскроллить, и это не перестраховка: на незаполненном
        // профиле сверху висит баннер «заполни профиль», и дневник уезжает под
        // нижнюю кромку. Список ленивый — то, что ниже экрана, в дереве
        // отсутствует, и тест падал на «значка нет», хотя значок был.
        let badge = app.descendants(matching: .any)["microTag-folate"]
        scrollTo(badge, in: app)
        XCTAssertTrue(badge.waitForExistence(timeout: 10),
                      "У записи должен появиться значок нутриента, которым продукт богат")
    }

    /// Набранный приём не пропадает от случайного смахивания листа.
    ///
    /// Раньше лист закрывался жестом вниз, и собранный приём исчезал молча.
    /// Теперь, пока в черновике есть продукт, смахнуть нельзя: выйти можно
    /// «Сохранить» или «Отмена».
    @MainActor
    func testASwipeCannotDropAnUnsavedMeal() throws {
        let app = launchApp()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        openAddEntry(in: app)

        let search = revealSearchField(in: app)
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Spinach")
        // По метке, а не по типу: после «быстрого добавления» строка с
        // названием может быть не статическим текстом, а кнопкой.
        let food = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] 'Spinach'")).firstMatch
        if !food.waitForExistence(timeout: 5) {
            let labels = app.descendants(matching: .any).allElementsBoundByIndex
                .prefix(80).map { "\($0.elementType.rawValue):\($0.label)" }
            XCTFail("Spinach не найден. На экране: \(labels.joined(separator: " | "))")
            return
        }
        food.tap()
        addToMeal(in: app)

        let save = app.buttons["saveMeal"]
        XCTAssertTrue(save.waitForExistence(timeout: 10), "Продукт не попал в черновик")

        // Тянем лист за ручку: кнопка сохранения должна остаться на экране.
        // Не `swipeDown`: он в симуляторе ничего не закрывает даже без защиты,
        // и тест зеленел бы от любого кода. Перетаскиваем от верха листа до
        // нижней кромки экрана, как делает палец. Ручки у листа во всю высоту
        // нет, а заголовок экрана собран по-своему и как элемент не находится,
        // поэтому берёмся за точку на уровне заголовка по координатам.
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.10))
        let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98))
        from.press(forDuration: 0.1, thenDragTo: to)
        Thread.sleep(forTimeInterval: 1.0)
        XCTAssertTrue(app.buttons["saveMeal"].exists, "Лист закрылся, и набранный приём пропал")

        // Один продукт стирается «Отменой» без вопроса, и лист снова свободен.
        app.buttons["cancelMeal"].tap()
        XCTAssertTrue(app.buttons["saveMeal"].waitForNonExistence(timeout: 5),
                      "«Отмена» не очистила черновик")
    }

    /// Правка плана живёт в тулбаре, а не строкой в самом низу списка.
    @MainActor
    func testPlanEditorOpensFromTheToolbar() {
        let app = launchApp(premium: true)
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))

        let strip = app.buttons["planStrip"]
        scrollIntoReach(strip, in: app)
        if strip.exists { strip.tap() }

        // Без плана экран плана и есть редактор — показывать нечего. Тест
        // проверяет путь к правке, а он в этом случае короче на одно нажатие.
        let phases = app.staticTexts["Phases"]
        if phases.waitForExistence(timeout: 3) { return }

        let edit = app.buttons["editPlan"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "В тулбаре плана нет кнопки правки")
        edit.tap()
        XCTAssertTrue(phases.waitForExistence(timeout: 5),
                      "Кнопка тулбара не открыла редактор плана")
    }

    /// Смысл экрана: заполняешь постепенно, и недостающее подсказывается по пропорциям.
    @MainActor
    func testMeasurementsSuggestMissingSites() {
        let app = launchApp(resetMeasurements: true)
        app.tabBars.buttons["Profile"].tap()
        let measurements = app.buttons["openMeasurementsRow"]
        scrollTo(measurements, in: app)
        measurements.tap()
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

        // До продукта добираемся поиском, а не пролистыванием. Раньше во
        // встроенной базе было шесть десятков позиций и «Миндаль» находился
        // за десяток свайпов; теперь их почти три сотни, разложенных по
        // категориям, и орехи лежат глубже любого разумного числа свайпов.
        let search = revealSearchField(in: app)
        XCTAssertTrue(search.waitForExistence(timeout: 5), "Не показалась строка поиска")
        search.tap()
        search.typeText("Almonds")

        let food = foodRow("Almonds", in: app)
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

        // Время приёма живёт на самом экране: за переходом его не видно, и
        // ошибку замечали уже в дневнике. Теперь это кнопка с часами рядом со
        // строкой поиска, а календарь с временем открываются по нажатию.
        let clock = app.descendants(matching: .any).matching(identifier: "mealTimePicker").firstMatch
        XCTAssertTrue(clock.waitForExistence(timeout: 5), "На экране приёма пищи нет выбора времени")
        clock.tap()

        // И дата, и время: поправить один только час невозможно.
        let calendar = app.datePickers.firstMatch
        XCTAssertTrue(calendar.waitForExistence(timeout: 5), "По часам должен открываться выбор дня и времени")
        XCTAssertGreaterThanOrEqual(calendar.buttons.count, 2,
                                    "У записи должны настраиваться и день, и время")
    }

    /// Правка позиции в собранном приёме: по нажатию на строку, и после
    /// «Готово» экран возвращается к приёму, а не в пустоту.
    ///
    /// Был чёрный экран с одной стрелкой назад: правка подменяла элемент
    /// целиком, у нового элемента был новый идентификатор, и открытый по
    /// старому экран порции переставал что-либо находить.
    @MainActor
    func testEditingADraftItemReturnsToTheMeal() {
        let app = launchApp()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        openAddEntry(in: app)

        let search = revealSearchField(in: app)
        search.tap()
        search.typeText("Beef")
        let row = foodRow("Beef", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Поиск не нашёл продукт")
        row.tap()
        let add = app.buttons["addToMeal"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()

        // Строка приёма пищи открывает правку по обычному нажатию.
        let draftRow = foodRow("Beef", in: app)
        XCTAssertTrue(draftRow.waitForExistence(timeout: 5), "Продукт не попал в приём пищи")
        draftRow.tap()

        let done = app.buttons["addToMeal"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "Правка не открылась по нажатию на строку")
        done.tap()

        // Вернулись к приёму пищи, а не в пустоту: кнопка сохранения на месте.
        XCTAssertTrue(app.buttons["saveMeal"].waitForExistence(timeout: 5),
                      "После «Готово» экран приёма пищи не вернулся")
    }

    /// Поиск идёт сразу по всему: недавнее, свои продукты, блюда и база.
    ///
    /// Раньше источник выбирался кнопкой в тулбаре, и поиск шёл по одному
    /// выбранному. Кнопка ушла: при наборе запроса показываются все источники
    /// разом, а внешняя база — по отдельной кнопке в результатах, потому что
    /// она ходит в сеть.
    @MainActor
    func testSearchCoversEverySourceAtOnce() {
        let app = launchApp()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        openAddEntry(in: app)

        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "sourceFilter").firstMatch.exists,
                       "Переключателя источника на экране быть не должно")

        let search = revealSearchField(in: app)
        XCTAssertTrue(search.waitForExistence(timeout: 5), "Не показалась строка поиска")
        search.tap()
        search.typeText("Beef")

        XCTAssertTrue(foodRow("Beef", in: app).waitForExistence(timeout: 5),
                      "Продукт из базы должен находиться без выбора источника")
        let usda = app.buttons["Search the USDA database"]
        XCTAssertTrue(usda.exists || app.staticTexts["Search the USDA database"].exists,
                      "Во внешнюю базу должна вести кнопка прямо из результатов")
    }

    /// Фраза с весом даёт быстрый выбор: количество из строки становится
    /// порцией, а тап кладёт продукт в приём без экрана порции.
    ///
    /// Проверяем на английском, потому что тесты запускаются с английским
    /// интерфейсом: база ищет сразу по русскому и английскому названиям, и
    /// этот же путь должен работать для обоих.
    @MainActor
    func testQuickAddFromQueryPutsFoodInTheMeal() {
        let app = launchApp()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        openAddEntry(in: app)

        let search = revealSearchField(in: app)
        XCTAssertTrue(search.waitForExistence(timeout: 5), "Не показалась строка поиска")
        search.tap()
        search.typeText("cottage cheese 180")

        let quick = app.descendants(matching: .any)
            .matching(identifier: "quickAddRow0").firstMatch
        XCTAssertTrue(quick.waitForExistence(timeout: 5),
                      "Фраза с весом должна показывать быстрое добавление")
        quick.tap()

        // Сохранение — признак того, что продукт действительно лёг в приём:
        // полоса с кнопкой появляется только над непустым черновиком.
        XCTAssertTrue(app.buttons["saveMeal"].waitForExistence(timeout: 10),
                      "Быстрый выбор должен класть продукт в приём пищи")
    }

    /// Дата и время приёма стоят в тулбаре, на месте прежнего выбора источника.
    @MainActor
    func testMealTimeLivesInTheToolbar() {
        let app = launchApp()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        openAddEntry(in: app)

        let picker = app.descendants(matching: .any).matching(identifier: "mealTimePicker").firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "Нет выбора времени приёма")
    }

    /// Выбор шрифта должен доезжать до интерфейса, а не только сохраняться.
    @MainActor
    func testFontChoiceIsOfferedAndPersists() {
        let app = launchApp()
        openSettings(in: app)
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
        app.tabBars.buttons["Profile"].tap()
        XCTAssertTrue(app.navigationBars["Profile"].waitForExistence(timeout: 5))

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
        let row = foodRow("Beef", in: app)
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

        let row = foodRow("Beef", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Поиск не нашёл продукт")

        // Найденное — выше секции приёма пищи. Сравниваем координаты, а не
        // порядок в дереве: дерево у списка не обязано совпадать с тем, что видно.
        let mealHeader = app.collectionViews.staticTexts["Meal"].firstMatch
        if mealHeader.exists {
            XCTAssertGreaterThan(mealHeader.frame.minY, row.frame.minY,
                                 "Пока идёт поиск, приём пищи должен быть ниже найденного")
        }

        row.tap()
        addToMeal(in: app)

        // Курсор вернулся в поиск сам: клавиатура поднята, к строке не тянулись.
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5),
                      "После добавления курсор не вернулся в строку поиска")
    }

    // MARK: - Запись еды

    @MainActor
    func testQuickCaloriesReachTheRing() {
        let app = launchApp()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))

        // «Только калории» живёт в плюсе на «Сегодня», рядом с остальными
        // способами что-то записать.
        let addMenu = app.buttons["addMenu"]
        XCTAssertTrue(addMenu.waitForExistence(timeout: 5), "Нет плюса на «Сегодня»")
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
        XCTAssertTrue(app.staticTexts["Refeeds and diet breaks"].exists,
                      "Перечень фич должен быть переведён, а не падать на русский исходник")
    }

    // MARK: - Премиум-гейт

    @MainActor
    func testPlanStripShowsPaywallWithoutPremium() {
        let app = launchApp(premium: false)
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))

        // Строка под кольцом — видимая дверь в план. Нажатие на само кольцо
        // ведёт туда же, но о нём ничто не сообщает: платную функцию нельзя
        // прятать за жест, которого не видно.
        let strip = app.buttons["planStrip"]
        scrollIntoReach(strip, in: app)
        XCTAssertTrue(strip.exists, "Под кольцом должна быть строка плана")
        strip.tap()
        XCTAssertTrue(app.navigationBars["Subscription"].waitForExistence(timeout: 5),
                      "Без премиума строка плана должна открывать пейволл")
    }

    /// Кольцо ведёт в добавление еды — самое частое действие на экране.
    /// План открывается строкой под ним, у которой есть подпись.
    @MainActor
    func testRingOpensMealEntry() {
        let app = launchApp(premium: true)
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))

        // Ищем среди всех потомков: кольцо — не кнопка и не текст, а вьюха
        // с признаком кнопки, и в какой именно коллекции она окажется,
        // зависит от того, как SwiftUI её свернул.
        let ring = app.descendants(matching: .any)["addFromRing"].firstMatch
        XCTAssertTrue(ring.waitForExistence(timeout: 5), "Кольцо не нашлось")
        ring.tap()
        XCTAssertTrue(app.navigationBars["Meal"].waitForExistence(timeout: 5),
                      "Нажатие на кольцо должно открывать приём пищи")
    }
}
