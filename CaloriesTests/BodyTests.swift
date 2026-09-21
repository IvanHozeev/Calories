import Testing
import UIKit
import Foundation
import SwiftData
@testable import Calories

// MARK: - Антропометрия

@MainActor
struct BodyAnalysisTests {

    private func sample() -> BodyMeasurement {
        BodyMeasurement(
            neckCm: 40, chestCm: 108, shouldersCm: 126, waistCm: 78, beltCm: 82,
            pelvisCm: 81, glutesCm: 96,
            bicepsLeftCm: 39, bicepsRightCm: 40,
            forearmLeftCm: 31, forearmRightCm: 31.5,
            wristLeftCm: 17, wristRightCm: 17,
            thighLeftCm: 58, thighRightCm: 58.5,
            quadLeftCm: 54, quadRightCm: 54,
            calfLeftCm: 39, calfRightCm: 39
        )
    }

    @Test func symmetry_flagsOnlyRealAsymmetry() {
        let results = BodyAnalysis.symmetry(sample())
        let biceps = results.first { $0.site == .biceps }
        let calf = results.first { $0.site == .calf }

        #expect(biceps?.difference == 1.0)
        #expect(biceps?.verdict == .excellent, "1 см — это погрешность ленты, не перекос")
        #expect(biceps?.strongerSide == .right)
        #expect(calf?.difference == 0)
    }

    @Test func symmetry_skipsIncompletePairs() {
        let m = sample()
        m.calfLeftCm = 0
        let results = BodyAnalysis.symmetry(m)
        #expect(!results.contains { $0.site == .calf },
                "Пара без одной стороны не должна попадать в отчёт как нулевая")
    }

    @Test func symmetry_warnsOnBigGap() {
        let m = sample()
        m.bicepsLeftCm = 36
        m.bicepsRightCm = 40
        let biceps = BodyAnalysis.symmetry(m).first { $0.site == .biceps }
        #expect(biceps?.verdict == .watch)
    }

    @Test func mccallum_derivesFromWrist() {
        let ideal = BodyAnalysis.mccallum(wristCm: 17)
        #expect(ideal?.chest == 110.5)                     // 17 × 6.5
        #expect(abs((ideal?.arm ?? 0) - 39.78) < 0.01)     // 36% груди
        #expect(BodyAnalysis.mccallum(wristCm: 0) == nil)
    }

    @Test func ffmi_isNotInflatedByFat() {
        // Один рост и вес, разный процент жира: у более сухого FFMI должен быть выше.
        let lean = BodyAnalysis.ffmi(weightKg: 80, heightCm: 180, bodyFatPercent: 10)!
        let fat = BodyAnalysis.ffmi(weightKg: 80, heightCm: 180, bodyFatPercent: 25)!
        #expect(lean > fat)
        #expect(abs(lean - 22.2) < 0.2)
    }

    @Test func ffmi_rejectsGarbageInput() {
        #expect(BodyAnalysis.ffmi(weightKg: 0, heightCm: 180, bodyFatPercent: 10) == nil)
        #expect(BodyAnalysis.ffmi(weightKg: 80, heightCm: 0, bodyFatPercent: 10) == nil)
        #expect(BodyAnalysis.ffmi(weightKg: 80, heightCm: 180, bodyFatPercent: 0) == nil)
    }

    @Test func insights_haveStableIdentifiers() {
        let first = BodyAnalysis.insights(measurement: sample(), profile: nil).map(\.id)
        let second = BodyAnalysis.insights(measurement: sample(), profile: nil).map(\.id)
        #expect(first == second, "Пересчёт не должен менять id — иначе SwiftUI перерисовывает список целиком")
    }

    @Test func insights_skipWhatWasNotMeasured() {
        let empty = BodyMeasurement()
        #expect(BodyAnalysis.insights(measurement: empty, profile: nil).isEmpty,
                "Без замеров отчёт должен быть пустым, а не полным нулей")
    }

    @Test func estimates_fillGapsFromWhatIsAlreadyMeasured() {
        let m = BodyMeasurement(date: Date())
        m.bicepsRightCm = 40

        let e = BodyAnalysis.estimates(for: m)
        // Соседние мышцы растут вместе, связь теснее, чем через костяк
        #expect(e[.forearm].map { abs($0.value - 32.2) < 0.1 } == true)
        #expect(e[.neck]?.value == 40)
        #expect(e[.calf]?.value == 40)
        // Бицепс снят — предполагать его незачем
        #expect(e[.biceps] == nil)
    }

    @Test func estimates_neverOverrideAMeasuredValue() {
        let m = BodyMeasurement(date: Date())
        m.bicepsRightCm = 40
        m.forearmRightCm = 30   // реально снято и заметно ниже расчётных 32.2

        let e = BodyAnalysis.estimates(for: m)
        #expect(e[.forearm] == nil, "Снятый замер нельзя подменять оценкой")
    }

    @Test func estimates_preferDirectRatioOverFrame() {
        let m = BodyMeasurement(date: Date())
        m.wristRightCm = 17     // МакКаллум дал бы предплечье около 32.0
        m.bicepsRightCm = 44    // прямое соотношение даёт 35.4

        let e = BodyAnalysis.estimates(for: m)
        #expect(e[.forearm].map { abs($0.value - 35.4) < 0.2 } == true,
                "Соотношение с соседней мышцей надёжнее вывода от запястья")
    }

    @Test func estimates_stayWithinPlausibleRanges() {
        // Оценка не должна предлагать то, что сама же форма отвергнет как мусор.
        for wrist in stride(from: 12.0, through: 25.0, by: 0.5) {
            let m = BodyMeasurement(date: Date())
            m.wristRightCm = wrist
            for (site, estimate) in BodyAnalysis.estimates(for: m) {
                #expect(site.isPlausible(estimate.value),
                        "\(site) при запястье \(wrist) вышло за диапазон: \(estimate.value)")
            }
        }
    }

    @Test func estimates_areEmptyWithoutAnyInput() {
        #expect(BodyAnalysis.estimates(for: BodyMeasurement(date: Date())).isEmpty)
    }

    @Test func plausibleRange_rejectsFatFingeredInput() {
        // Реальный случай: слипшиеся цифры при вводе дают обхват в миллиарды сантиметров.
        #expect(!MeasurementSite.chest.isPlausible(10878828196))
        #expect(!MeasurementSite.wrist.isPlausible(176262.5))
        #expect(!MeasurementSite.neck.isPlausible(401261087882))

        // Пустое поле и обнуление — это не ошибка, а «не мерил»
        #expect(MeasurementSite.chest.isPlausible(0))

        // Живые значения проходят, включая края диапазона
        #expect(MeasurementSite.chest.isPlausible(108))
        #expect(MeasurementSite.wrist.isPlausible(17))
        #expect(MeasurementSite.pelvis.isPlausible(81))
        #expect(MeasurementSite.biceps.isPlausible(44))
        #expect(MeasurementSite.wrist.isPlausible(12))
        #expect(MeasurementSite.wrist.isPlausible(25))
        #expect(!MeasurementSite.wrist.isPlausible(11.9))
    }

    @Test func navyInputs_useTheSiteEachSexIsActuallyMeasuredAt() {
        let m = BodyMeasurement(date: Date())
        m.neckCm = 40
        m.waistCm = 78     // узкая талия
        m.beltCm = 84      // на уровне пупка
        m.glutesCm = 96

        // Методика ВМС США у мужчин меряет живот на уровне пупка — это пояс,
        // а вовсе не талия в узком месте. Раньше сюда уходила талия.
        let male = m.navyInputs(for: .male)
        #expect(male.waist == 84)
        #expect(male.neck == 40)
        #expect(male.hip == nil, "Мужчинам бёдра не нужны")

        // У женщин — узкая талия плюс ягодицы
        let female = m.navyInputs(for: .female)
        #expect(female.waist == 78)
        #expect(female.hip == 96)
    }

    @Test func navyInputs_treatUnmeasuredAsMissingNotZero() {
        let m = BodyMeasurement(date: Date())
        m.neckCm = 40
        let male = m.navyInputs(for: .male)
        #expect(male.waist == nil, "Неснятый пояс — это «нет данных», а не ноль")

        // С дырой в данных Navy-метод не должен считаться вовсе
        let profile = UserProfile(
            weightKg: 80, heightCm: 180, age: 30, sex: .male,
            activityLevel: .moderate, goal: .maintenance,
            proteinPerKg: 2.0
        )
        #expect(profile.navyBodyFat(from: m) == nil)
        #expect(!profile.isNavyMethod(from: m))
        // Но оценка по ИМТ всё равно есть — экран не должен остаться пустым
        #expect(profile.bodyFatPercentage(from: m) > 0)
    }

    @Test func bodyFatAppearsInReportOnlyWhenMeasured() {
        let m = BodyMeasurement(date: Date())
        m.neckCm = 40
        m.beltCm = 84

        let p = UserProfile(
            weightKg: 80, heightCm: 180, age: 30, sex: .male,
            activityLevel: .moderate, goal: .maintenance, proteinPerKg: 2.0
        )
        #expect(BodyAnalysis.insights(measurement: m, profile: p).map(\.id).contains("bodyFat"))

        // Без обхватов процент считается по ИМТ, и в отчёт о замерах он не идёт:
        // там ему нечего объяснять — он выведен не из этих замеров.
        let empty = BodyMeasurement(date: Date())
        #expect(!BodyAnalysis.insights(measurement: empty, profile: p).map(\.id).contains("bodyFat"))
    }

    @Test func micronutrients_treatUnknownAsUnknownNotZero() {
        // Разница принципиальная: на нулях день насчитал бы дефицит там,
        // где данных просто нет.
        let empty = Micronutrients()
        #expect(empty.isEmpty)
        #expect(empty[.iron] == nil)

        let known = Micronutrients([.iron: 2.5])
        #expect(known[.iron] == 2.5)
        #expect(known[.zinc] == nil, "Незаполненное вещество не ноль, а неизвестно")
    }

    @Test func micronutrients_scaleAndAddUp() {
        let per100g = Micronutrients([.iron: 2.0, .calcium: 120])
        let eaten = per100g.scaled(by: 250)
        #expect(eaten[.iron] == 5.0)
        #expect(eaten[.calcium] == 300)

        let day = eaten + Micronutrients([.iron: 1.0, .zinc: 3.0])
        #expect(day[.iron] == 6.0)
        #expect(day[.calcium] == 300)
        #expect(day[.zinc] == 3.0)
    }

    @Test func micronutrients_surviveStorageOnAProduct() {
        let food = FoodItem(name: "Печень", caloriesPer100g: 135, protein: 20, fat: 4, carbs: 4, category: .meat)
        #expect(food.micronutrients.isEmpty, "У продукта без данных микронутриентов быть не должно")

        food.micronutrients = Micronutrients([.vitaminA: 4968, .iron: 6.5])
        #expect(food.micronutrients[.vitaminA] == 4968)
        #expect(food.micronutrients[.iron] == 6.5)
        #expect(food.micronutrients[.vitaminC] == nil)
    }

    @Test func usdaNutrientIDsAreDistinct() {
        // Повтор идентификатора тихо подменил бы одно вещество другим.
        let ids = Micronutrient.allCases.map(\.usdaNutrientID)
        #expect(Set(ids).count == ids.count)
    }

    @Test func everyCategoryIconIsARealSymbol() {
        // Несуществующее имя символа рисуется пустотой, а не падает — поэтому
        // опечатку в нём замечаешь только глазами на экране. Пусть замечает тест.
        for category in FoodCategory.allCases {
            #expect(UIImage(systemName: category.icon) != nil,
                    "\(category.rawValue): нет символа «\(category.icon)»")
        }
    }

    @Test func everyBuiltInFoodHasACategory() {
        // «Другое» у встроенного продукта — почти всегда забытая категория,
        // а не осознанный выбор: у нас на каждый из них она проставлена руками.
        let uncategorised = FoodDatabase.items.filter { $0.foodCategory == .other }
        #expect(uncategorised.isEmpty,
                "Без категории остались: \(uncategorised.map(\.name).joined(separator: ", "))")
    }

    @Test func builtInFoodsLandInSensibleCategories() {
        // Раньше здесь стояли точные количества по каждой категории. Со
        // встроенным каталогом это тест не на смысл, а на то, что каталог не
        // пополняли: любая новая позиция красила его в красный. Проверяем то,
        // ради чего он писался — что ни одна категория не осталась пустой и
        // что «Другое» не стало свалкой.
        var counts: [FoodCategory: Int] = [:]
        for item in FoodDatabase.items { counts[item.foodCategory, default: 0] += 1 }

        for category in FoodCategory.allCases where category != .other {
            #expect((counts[category] ?? 0) > 0,
                    "Категория «\(category.rawValue)» осталась без продуктов")
        }
        #expect(counts[.other] == nil)
        #expect(counts.values.reduce(0, +) == FoodDatabase.items.count)
    }

    @Test func catalogIsInTheBundle() {
        // Каталог лежит файлом в бандле, а не в коде, и выпасть из сборки может
        // молча: приложение просто покажет пустой раздел «База». Ловим здесь.
        #expect(!FoodCatalog.isEmpty)
        #expect(FoodCatalog.all.count > 200)
    }

    @Test func catalogIdentifiersAreUnique() {
        // По идентификатору поиск достаёт готовый объект. Совпади два — часть
        // продуктов стала бы недостижимой, и заметили бы это не сразу.
        let identifiers = FoodCatalog.all.map(\.id)
        #expect(Set(identifiers).count == identifiers.count)
    }

    @Test func catalogNumbersAreWithinReason() {
        // Опечатка в разряде — самая дорогая ошибка в калорийном дневнике:
        // она не падает, а тихо врёт человеку про его день.
        for food in FoodCatalog.all {
            #expect(food.kcal >= 0 && food.kcal <= 950, "\(food.en): \(food.kcal) ккал")
            #expect(food.protein >= 0 && food.fat >= 0 && food.carbs >= 0, "\(food.en): минус в макросах")
            #expect(food.protein + food.fat + food.carbs <= 100.5,
                    "\(food.en): макросов больше, чем сто грамм продукта")
        }
    }

    @Test func searchPutsTheExactMatchFirst() {
        // По «milk» человек ждёт молоко, а не молочный коктейль, хотя формально
        // подходят оба.
        let found = FoodCatalog.search("milk")
        #expect(found.first?.en == "Milk 3.2%" || found.first?.en.hasPrefix("Milk") == true,
                "первым нашлось: \(found.first?.en ?? "ничего")")
    }

    @Test func searchIgnoresCaseAndDiacritics() {
        // «ЙОГУРТ», «йогурт» и «Йогурт» — один продукт для человека, и должны
        // быть одним для поиска.
        let lower = FoodCatalog.search("йогурт").map(\.id)
        let upper = FoodCatalog.search("ЙОГУРТ").map(\.id)
        #expect(!lower.isEmpty)
        #expect(lower == upper)
    }

    @Test func searchFindsFoodByEitherLanguage() {
        // Человек с русским интерфейсом набирает «chicken» так же часто, как
        // «курица». Каталог знает оба названия и ищет по обоим сразу.
        #expect(!FoodCatalog.search("курица").isEmpty)
        #expect(!FoodCatalog.search("chicken").isEmpty)
        #expect(!FoodCatalog.search("гречка").isEmpty)
        #expect(!FoodCatalog.search("buckwheat").isEmpty)
    }

    @Test @MainActor func searchReturnsTheSameObjectsEveryTime() {
        // Поиск обязан отдавать те же объекты, а не свежие копии: `FoodItem`
        // опознаётся по `id`, и на новых копиях SwiftUI перестраивал бы весь
        // список на каждое нажатие клавиши вместо того, чтобы его отфильтровать.
        let first = FoodDatabase.search("rice")
        let second = FoodDatabase.search("rice")
        #expect(!first.isEmpty)
        #expect(first.map(\.id) == second.map(\.id))
        #expect(first.first === second.first)
    }

    @Test func searchWithoutQueryDoesNotReturnEverythingAtOnce() {
        // Пустой запрос — это открытый экран, а не команда выгрузить каталог:
        // двумя тысячами строк список только зря соберётся.
        #expect(FoodCatalog.search("", limit: 25).count == 25)
    }

    @Test func foodCategory_survivesReorderingOfTheEnum() {
        // Категория хранится строкой: по индексу «Рыба» однажды тихо стала бы
        // «Молочным» у всех сразу, стоит поменять порядок в перечислении.
        let food = FoodItem(name: "Треска", caloriesPer100g: 82, protein: 18, fat: 0.7, carbs: 0, category: .fish)
        #expect(food.category == "fish")
        #expect(food.foodCategory == .fish)

        food.foodCategory = .dairy
        #expect(food.category == "dairy")
    }

    @Test func foodCategory_defaultsToOtherForOldRecords() {
        // У продуктов, заведённых до появления категорий, поля нет вовсе.
        let legacy = FoodItem(name: "Хлеб", caloriesPer100g: 250, protein: 8, fat: 3, carbs: 48)
        #expect(legacy.foodCategory == .other)

        // И мусор в поле не должен ронять экран
        legacy.category = "не-существует"
        #expect(legacy.foodCategory == .other)
    }

    @Test func sideLabelAgreesWithGender() {
        // Проверяем раскладку по родам, а не текст: подписи локализованы,
        // и в английской локали все формы совпадают.
        // «Левое предплечье», но «левая икра».
        #expect(MeasurementSite.biceps.gender == .masculine)
        #expect(MeasurementSite.quad.gender == .masculine)
        #expect(MeasurementSite.forearm.gender == .neuter)
        #expect(MeasurementSite.wrist.gender == .neuter)
        #expect(MeasurementSite.thigh.gender == .neuter)
        #expect(MeasurementSite.calf.gender == .feminine)

        // У парного места подпись стороны стоит рядом с одной конечностью,
        // поэтому множественное число там было бы ошибкой.
        for site in MeasurementSite.allCases where site.isPaired {
            #expect(site.gender != .plural, "\(site): парное место не может быть во множественном")
        }

        // Каждая пара «сторона + род» должна давать непустую подпись
        for gender in [GrammaticalGender.masculine, .feminine, .neuter, .plural] {
            for side in BodySide.allCases {
                #expect(!side.title(gender).isEmpty)
            }
        }
    }

    @Test func pickerOffersOnlyPlausibleValues() {
        // Колесо — единственный способ ввода, поэтому мусор не должен в нём лежать.
        for site in MeasurementSite.allCases {
            let options = site.pickerTenths
            #expect(!options.isEmpty, "\(site) без вариантов в колесе")
            for tenths in options {
                #expect(site.isPlausible(Double(tenths) / 10),
                        "\(site) предлагает \(Double(tenths) / 10)")
            }
            // Границы диапазона должны быть достижимы
            #expect(Double(options.first!) / 10 == site.plausibleRange.lowerBound)
            #expect(Double(options.last!) / 10 <= site.plausibleRange.upperBound)
            // Шаг 0.5 см: мельче лента не даёт
            if options.count > 1 {
                #expect(options[1] - options[0] == 5)
            }
        }
    }

    @Test func plausibleRange_coversEverySite() {
        // Забыть диапазон для нового места замера — значит пропустить мусор в историю.
        for site in MeasurementSite.allCases {
            #expect(site.plausibleRange.lowerBound > 0, "\(site) без нижней границы")
            #expect(site.plausibleRange.upperBound < 250, "\(site) с бесполезно широкой границей")
        }
    }

    @Test func pelvisMetrics_separateFrameFromSoftTissue() {
        let m = sample()   // плечи 126, талия 78, таз 81, пояс 82, ягодицы 96
        let insights = BodyAnalysis.insights(measurement: m, profile: nil)

        // Знаменатель костный: отношение двигается только за счёт верха, не за счёт диеты
        let structural = insights.first { $0.id == "shouldersPelvis" }
        #expect(structural?.value == "1.56")
        #expect(structural?.verdict == .excellent)

        // 78 / 81 = 0.963: талия уже костяка, но не радикально — это «хорошо», не «отлично»
        let waistPelvis = insights.first { $0.id == "waistPelvis" }
        // Сравниваем вердикт, а не подпись: подпись локализуется и в тесте логики
        // привязываться к её тексту нельзя.
        #expect(waistPelvis?.verdict == .good)

        // Пояс шире талии на 4 см — в пределах нормы
        let visceral = insights.first { $0.id == "beltWaist" }
        #expect(visceral?.value == "+4.0 см")
        #expect(visceral?.verdict == .good)

        // Ягодицы над костяком: 96 − 81
        #expect(insights.first { $0.id == "glutesPelvis" }?.value == "+15.0 см")
    }

    @Test func pelvisMetrics_absentWithoutPelvisMeasurement() {
        let m = sample()
        m.pelvisCm = 0
        let ids = BodyAnalysis.insights(measurement: m, profile: nil).map(\.id)
        #expect(!ids.contains("shouldersPelvis"))
        #expect(!ids.contains("waistPelvis"))
        #expect(!ids.contains("glutesPelvis"))
        #expect(ids.contains("beltWaist"), "Висцеральный индикатор от таза не зависит")
    }

    @Test func vTaper_recognisesGoldenRatio() {
        let m = sample()
        m.shouldersCm = 126
        m.waistCm = 77.9                      // 126 / 77.9 ≈ 1.617
        let vtaper = BodyAnalysis.insights(measurement: m, profile: nil).first { $0.id == "vtaper" }
        #expect(vtaper?.verdict == .good)

        m.waistCm = 77.0                      // ≈ 1.636
        let better = BodyAnalysis.insights(measurement: m, profile: nil).first { $0.id == "vtaper" }
        #expect(better?.verdict == .excellent)
    }
}

@MainActor
@Suite(.serialized)
struct MeasurementSessionTests {

    private let container: ModelContainer
    private let store: CalorieStore

    init() async throws {
        container = try ModelContainer(
            for: FoodEntry.self, FoodItem.self, WeightEntry.self, GoalRecord.self, Dish.self,
                BodyMeasurement.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        store = CalorieStore(context: container.mainContext, defaults: TestDefaults.make(), groupDefaults: nil)
    }

    /// Замеры снимают раз в несколько недель и не все разом. Если новый сеанс
    /// начинать пустым, запись с одним заполненным местом становится последней —
    /// и процент жира с FFMI считаются уже по ней.
    @Test func newSessionInheritsThePrevious() {
        let old = BodyMeasurement(date: Date().addingTimeInterval(-7 * 86_400))
        old.setValue(81, for: .belt)
        old.setValue(38, for: .neck)
        old.setValue(40, for: .biceps, side: .right)
        store.addMeasurement(old)

        let today = store.measurementForToday()

        #expect(Calendar.current.isDateInToday(today.date))
        #expect(today.value(.belt) == 81)
        #expect(today.value(.neck) == 38)
        #expect(today.value(.biceps, .right) == 40)
    }

    /// Правка второго места за тот же день не должна заводить вторую запись.
    @Test func todaysSessionIsReused() {
        let first = store.measurementForToday()
        first.setValue(81, for: .belt)

        let second = store.measurementForToday()

        #expect(first === second)
        #expect(store.measurements.count == 1)
    }

    /// Пустая база: первый сеанс заводится и не падает без предыдущего.
    @Test func firstSessionStartsEmpty() {
        let session = store.measurementForToday()
        #expect(!session.hasAnyValue)
        #expect(store.measurements.count == 1)
    }
}

@MainActor
@Suite(.serialized)
struct MacroBudgetTests {

    private let container: ModelContainer
    private let store: CalorieStore

    init() async throws {
        container = try ModelContainer(
            for: FoodEntry.self, FoodItem.self, WeightEntry.self, GoalRecord.self, Dish.self,
                BodyMeasurement.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        store = CalorieStore(context: container.mainContext, defaults: TestDefaults.make(), groupDefaults: nil)
    }

    private func profile(basis: ProteinBasis = .bodyweight,
                         proteinPerKg: Double = 2.0,
                         proteinPerLeanKg: Double? = nil,
                         fatPerKg: Double? = nil) -> UserProfile {
        UserProfile(
            weightKg: 77, heightCm: 180, age: 30, sex: .male,
            activityLevel: .moderate, goal: .maintenance,
            proteinPerKg: proteinPerKg, proteinPerLeanKg: proteinPerLeanKg,
            proteinBasis: basis, fatPerKg: fatPerKg
        )
    }

    /// Замер, дающий по Navy около 19% жира: пояс 81, шея 38 при росте 180.
    private func measurement() -> BodyMeasurement {
        let m = BodyMeasurement(date: Date())
        m.setValue(81, for: .belt)
        m.setValue(38, for: .neck)
        return m
    }

    @Test func carbsAreWhatIsLeftOfTheGoal() {
        store.updateProfile(profile(), syncDailyGoal: false)
        store.dailyGoal = 2000

        // 154 г белка (2.0 × 77) и 61.6 г жира съедают 616 + 554.4 ккал
        let locked = 154 * 4.0 + 77 * 0.8 * 9
        #expect(store.carbsTarget != nil)
        #expect(abs(store.carbsTarget! - (2000 - locked) / 4) < 0.01)
        #expect(store.macrosOverflow == nil)
    }

    /// Норма выросла — вырос только остаток, обязательства не изменились.
    @Test func aHigherGoalGrowsOnlyTheCarbs() {
        store.updateProfile(profile(), syncDailyGoal: false)
        store.dailyGoal = 2000
        let before = store.carbsTarget!
        let protein = store.proteinTarget!
        let fat = store.fatTarget!

        store.dailyGoal = 2400

        #expect(store.proteinTarget == protein)
        #expect(store.fatTarget == fat)
        #expect(abs(store.carbsTarget! - (before + 100)) < 0.01)
    }

    /// На глубоком дефиците обязательства перестают помещаться, и об этом
    /// надо сказать, а не показать отрицательные углеводы.
    @Test func overflowIsReportedInsteadOfNegativeCarbs() {
        store.updateProfile(profile(proteinPerKg: 2.6), syncDailyGoal: false)
        store.dailyGoal = 1000

        #expect(store.carbsTarget == 0)
        #expect(store.macrosOverflow != nil)
        #expect(store.macrosOverflow! > 0)
    }

    /// У основ разные числа и разный смысл: 2.0 на кг веса — норма, 2.0 на кг
    /// сухой массы — недобор. Поэтому у сухой массы своё значение и свой порядок.
    @Test func eachBasisKeepsItsOwnNumber() {
        let m = measurement()
        let byWeight = profile(basis: .bodyweight).proteinTargetGrams(from: m)
        let byLean = profile(basis: .leanMass, proteinPerLeanKg: 2.5).proteinTargetGrams(from: m)

        #expect(byWeight == 154)
        // 2.5 на кг сухой массы при ~19% жира примерно догоняет 2.0 на кг веса
        #expect(abs(byLean - byWeight) < 10)
    }

    /// Незаданное значение для сухой массы берётся из своего умолчания, а не из
    /// нормы на общий вес — иначе переключатель молча срезал бы четверть белка.
    @Test func leanBasisUsesItsOwnDefaultNotTheBodyweightNumber() {
        let m = measurement()
        let p = profile(basis: .leanMass, proteinPerKg: 2.0, proteinPerLeanKg: nil)

        #expect(p.proteinPerLeanKg == UserProfile.defaultProteinPerLeanKg)
        #expect(p.proteinTargetGrams(from: m) > 2.0 * p.leanMassKg(from: m)!)
    }

    /// Без замеров персональный режим считает от веса, а не отказывает.
    @Test func leanMassBasisFallsBackWithoutMeasurements() {
        let p = profile(basis: .leanMass)
        #expect(p.leanMassKg(from: nil) == nil)
        #expect(p.proteinTargetGrams(from: nil) == 154)
    }

    /// Неделя должна отмечать день попаданием только по набранному белку.
    @Test func theWeekMarksDaysWhereProteinWasHit() {
        store.updateProfile(profile(), syncDailyGoal: false)   // цель по белку 154 г
        store.dailyGoal = 2000
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        store.add(name: "Творог", calories: 800,
                  macros: Macros(protein: 160, fat: 10, carbs: 20), date: yesterday)

        let week = store.macroWeek
        #expect(week.count == 7)

        let day = week.first { Calendar.current.isDate($0.date, inSameDayAs: yesterday) }
        #expect(day?.hasEntries == true)
        #expect(day?.hitProtein == true)
    }

    /// Недобор — это недобор, «почти» не считается.
    @Test func aDayJustShortOfTheTargetIsAMiss() {
        store.updateProfile(profile(), syncDailyGoal: false)
        store.dailyGoal = 2000
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        store.add(name: "Творог", calories: 800,
                  macros: Macros(protein: 153, fat: 10, carbs: 20), date: yesterday)

        let day = store.macroWeek.first { Calendar.current.isDate($0.date, inSameDayAs: yesterday) }
        #expect(day?.hitProtein == false)
    }

    /// Пустой день не попадание, но и не промах — записей просто нет.
    @Test func daysWithoutEntriesAreMarkedEmpty() {
        store.updateProfile(profile(), syncDailyGoal: false)
        store.dailyGoal = 2000

        #expect(store.macroWeek.allSatisfy { !$0.hasEntries })
        #expect(store.macroWeek.allSatisfy { !$0.hitProtein })
    }

    /// Опустил жир — освободившиеся калории ушли в углеводы, а не растворились.
    @Test func loweringFatMovesTheCaloriesIntoCarbs() {
        store.updateProfile(profile(), syncDailyGoal: false)
        store.dailyGoal = 2000
        let carbsAtDefault = store.carbsTarget!

        store.updateProfile(profile(fatPerKg: 0.6), syncDailyGoal: false)

        #expect(store.fatTarget == 77 * 0.6)
        // 0.2 г/кг × 77 кг × 9 ккал = 138.6 ккал, это 34.65 г углеводов
        #expect(abs(store.carbsTarget! - (carbsAtDefault + 34.65)) < 0.01)
    }

    /// Профиль без своей нормы жира берёт общее умолчание.
    @Test func fatFallsBackToTheSharedDefault() {
        let p = profile(fatPerKg: nil)
        #expect(p.fatPerKg == MacroTargets.fatPerKg)
        #expect(p.fatTargetGrams == 77 * MacroTargets.fatPerKg)
    }

    /// Старый сохранённый профиль без поля основы читается как «от веса».
    @Test func profilesSavedBeforeTheSettingDecodeAsBodyweight() throws {
        let json = """
        {"weightKg":77,"heightCm":180,"age":30,"sex":"male",
         "activityLevel":"moderate","goal":"maintenance","proteinPerKg":2.0}
        """
        let decoded = try JSONDecoder().decode(UserProfile.self, from: Data(json.utf8))
        #expect(decoded.proteinBasis == .bodyweight)
        #expect(decoded.proteinTargetGrams(from: nil) == 154)
    }
}


@MainActor
@Suite(.serialized)
struct PlanCompletionTests {

    private let container: ModelContainer
    private let store: CalorieStore

    init() async throws {
        container = try ModelContainer(
            for: FoodEntry.self, FoodItem.self, WeightEntry.self, GoalRecord.self, Dish.self,
                BodyMeasurement.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let defaults = TestDefaults.make()
        defaults.set(true, forKey: "is_premium")
        store = CalorieStore(context: container.mainContext, defaults: defaults, groupDefaults: nil)
        store.isPremium = true
        store.updateProfile(
            UserProfile(weightKg: 77, heightCm: 180, age: 30, sex: .male,
                        activityLevel: .moderate, goal: .fatLoss, proteinPerKg: 2.0)
        )
    }

    private func startedPlan(weeksAgo: Int, weeks: Int, target: Double) -> Plan {
        Plan(startDate: Date().addingTimeInterval(-Double(weeksAgo) * 7 * 86_400),
             durationWeeks: weeks, startWeightKg: 77, targetWeightKg: target)
    }

    /// Цепочка фаз: план на поддержании не должен требовать снижения.
    ///
    /// Самая опасная ошибка соответствия: тянуть прямую от старта к финишу.
    /// На такой прямой поддержание посреди плана выглядит как продолжающийся
    /// дефицит, и приложение обвиняет человека в том, что само же и назначило.
    private func chainedPlan(weeksAgo: Int) -> Plan {
        Plan(startDate: Date().addingTimeInterval(-Double(weeksAgo) * 7 * 86_400),
             startWeightKg: 77,
             phases: [
                PlanPhase(intent: .cut, durationWeeks: 4, weeklyRatePercent: 0.5),
                PlanPhase(intent: .maintenance, durationWeeks: 4)
             ])
    }

    @Test func slowedDownGoalStaysWithinItsPhase() {
        // «Замедлить» пишет число — оно должно действовать, пока идёт та же фаза.
        store.startPlan(chainedPlan(weeksAgo: 1))
        store.dailyGoal = 1234
        #expect(store.effectiveGoal(for: Date()) == 1234)
        // Через четыре недели сушка кончится — там норма уже поддержания по формуле,
        // а не записанное под сушку число.
        let plan = try! #require(store.plan)
        let tdee = try! #require(store.profile?.tdee)
        let inMaintenance = Date().addingTimeInterval(4 * 7 * 86_400)
        #expect(store.effectiveGoal(for: inMaintenance) == plan.dailyCalorieTarget(for: inMaintenance, tdee: tdee))
    }

    @Test func dietBreakWeekIsMaintenanceWithoutCycling() {
        store.startPlan(Plan(startDate: Date().addingTimeInterval(-2 * 86_400), startWeightKg: 77,
                             phases: [PlanPhase(intent: .cut, durationWeeks: 8, weeklyRatePercent: 0.5,
                                                dietBreakEvery: 4)]))
        let tdee = try! #require(store.profile?.tdee)
        let breakDay = Date().addingTimeInterval(30 * 86_400)
        let afterBreak = Date().addingTimeInterval(37 * 86_400)
        #expect(store.effectiveGoal(for: breakDay) == Int(tdee.rounded()))
        #expect(store.effectiveGoal(for: afterBreak) < store.effectiveGoal(for: breakDay))
    }

    @Test func maintenanceIsNotExpectedToKeepLosing() {
        // Шестая неделя: дефицит кончился на четвёртой, идёт поддержание.
        let plan = chainedPlan(weeksAgo: 6)
        store.startPlan(plan)
        let afterCut = 77 - 77 * 0.005 * 4
        // Вес держится на том, к чему пришли после дефицита.
        store.addWeight(afterCut, date: Date().addingTimeInterval(-3 * 86_400))
        store.addWeight(afterCut, date: Date())

        let adherence = try! #require(store.planAdherence())
        #expect(abs(adherence.expectedWeightToday - afterCut) < 0.05,
                "На поддержании ждут тот же вес, а не продолжение снижения")
        #expect(adherence.status == .onTrack)
    }

    @Test func waterComingBackAfterADeficitIsNotCalledFallingBehind() {
        // Пятая неделя: дефицит кончился на четвёртой, калории подняли.
        // Вес прыгнул на полтора килограмма гликогена и воды.
        let plan = chainedPlan(weeksAgo: 5)
        store.startPlan(plan)
        let afterCut = 77 - 77 * 0.005 * 4
        store.addWeight(afterCut, date: Date().addingTimeInterval(-8 * 86_400))
        store.addWeight(afterCut + 1.4, date: Date())

        let adherence = try! #require(store.planAdherence())
        #expect(adherence.isSettlingAfterIncrease, "После подъёма калорий вес ещё устаканивается")
        #expect(adherence.status == .onTrack,
                "Полтора килограмма воды — это не отставание, а то, что сам переход и означает")
    }

    @Test func theRateIsMeasuredWithinTheRunningPhaseNotTheWholePlan() {
        let plan = chainedPlan(weeksAgo: 6)
        store.startPlan(plan)
        let afterCut = 77 - 77 * 0.005 * 4
        store.addWeight(afterCut, date: Date().addingTimeInterval(-14 * 86_400))
        store.addWeight(afterCut, date: Date())

        let adherence = try! #require(store.planAdherence())
        // За план целиком темп был бы заметно отрицательным из-за прошедшей
        // сушки. Внутри идущего поддержания он около нуля — и это ответ
        // на вопрос, который задают: как идёт сейчас.
        let rate = try! #require(adherence.observedWeeklyRateKg)
        #expect(abs(rate) < 0.2, "Темп меряется по идущей фазе, а не по всему плану")
    }

    /// Идущий план итога не имеет — иначе финиш показался бы на середине.
    @Test func aRunningPlanHasNoOutcome() {
        store.startPlan(startedPlan(weeksAgo: 2, weeks: 8, target: 71))
        #expect(store.plan?.isFinished == false)
        #expect(store.planOutcome == nil)
    }

    /// Дошедший до даты финиша план становится итогом.
    @Test func aPlanPastItsEndDateIsFinished() {
        store.startPlan(startedPlan(weeksAgo: 9, weeks: 8, target: 71))
        #expect(store.plan?.isFinished == true)
        #expect(store.planOutcome != nil)
    }

    /// Цель взята, когда пришли к целевому весу или ниже.
    @Test func hittingTheTargetCountsAsReached() {
        store.startPlan(startedPlan(weeksAgo: 9, weeks: 8, target: 71))
        store.addWeight(70.8, date: Date().addingTimeInterval(-86_400))

        let outcome = store.planOutcome
        #expect(outcome?.reachedTarget == true)
        #expect(abs((outcome?.changeKg ?? 0) - (70.8 - 77)) < 0.01)
    }

    /// Недошёл — итог говорит, на сколько именно, а не молчит.
    @Test func fallingShortReportsTheGap() {
        store.startPlan(startedPlan(weeksAgo: 9, weeks: 8, target: 71))
        store.addWeight(73.0, date: Date().addingTimeInterval(-86_400))

        let outcome = store.planOutcome
        #expect(outcome?.reachedTarget == false)
        #expect(abs((outcome?.shortfallKg ?? 0) - 2.0) < 0.01)
    }

    /// Вес упал — TDEE упал, и норма плана должна пойти за ним, а не замереть
    /// на числе, посчитанном в день старта.
    @Test func theGoalFollowsAFallingWeight() {
        store.startPlan(startedPlan(weeksAgo: 1, weeks: 8, target: 71))
        let goalAtStart = store.dailyGoal

        var lighter = store.profile!
        lighter.weightKg = 74
        store.updateProfile(lighter)

        #expect(store.dailyGoal < goalAtStart)
        #expect(store.dailyGoal == store.plan!.dailyCalorieTarget(tdee: lighter.tdee))
    }

    /// Тумблер цикла отвечает только за распределение по дням: следование за весом
    /// должно быть одинаковым и с ним, и без него.
    @Test func cyclingDoesNotChangeWhetherTheGoalFollowsWeight() {
        store.startPlan(Plan(startDate: Date().addingTimeInterval(-7 * 86_400),
                             durationWeeks: 8, startWeightKg: 77, targetWeightKg: 71,
                             cyclingEnabled: true))
        var lighter = store.profile!
        lighter.weightKg = 74
        store.updateProfile(lighter)
        let withCycling = store.dailyGoal

        store.startPlan(Plan(startDate: Date().addingTimeInterval(-7 * 86_400),
                             durationWeeks: 8, startWeightKg: 77, targetWeightKg: 71,
                             cyclingEnabled: false))
        store.updateProfile(lighter)

        #expect(store.dailyGoal == withCycling)
    }

    private func session(_ daysAgo: Int, belt: Double, neck: Double) -> BodyMeasurement {
        let m = BodyMeasurement(date: Date().addingTimeInterval(-Double(daysAgo) * 86_400))
        m.setValue(belt, for: .belt)
        m.setValue(neck, for: .neck)
        return m
    }

    /// Один сеанс замеров сравнивать не с чем.
    @Test func compositionNeedsTwoSessions() {
        store.startPlan(startedPlan(weeksAgo: 4, weeks: 8, target: 71))
        store.addMeasurement(session(20, belt: 86, neck: 38))
        store.addWeight(77, date: Date().addingTimeInterval(-20 * 86_400))

        #expect(store.planCompositionChange == nil)
    }

    /// Жир ушёл, сухая масса на месте — вес уходит правильно.
    @Test func fatComingOffLeavesLeanMassAlone() {
        store.startPlan(startedPlan(weeksAgo: 8, weeks: 12, target: 70))
        store.addMeasurement(session(50, belt: 88, neck: 38))
        store.addWeight(77, date: Date().addingTimeInterval(-50 * 86_400))
        store.addMeasurement(session(2, belt: 81, neck: 38))
        store.addWeight(72, date: Date().addingTimeInterval(-2 * 86_400))

        let change = store.planCompositionChange
        #expect(change != nil)
        #expect((change?.fatDeltaKg ?? 0) < -1)
        #expect(change?.verdict == .withinNoise)
    }

    /// Пояс не изменился, а вес упал — значит ушла сухая масса, и об этом надо
    /// сказать, а не порадоваться минусу на весах.
    @Test func losingWeightWithoutLosingGirthReadsAsLeanLoss() {
        store.startPlan(startedPlan(weeksAgo: 8, weeks: 12, target: 70))
        store.addMeasurement(session(50, belt: 88, neck: 38))
        store.addWeight(85, date: Date().addingTimeInterval(-50 * 86_400))
        store.addMeasurement(session(2, belt: 88, neck: 38))
        store.addWeight(77, date: Date().addingTimeInterval(-2 * 86_400))

        #expect(store.planCompositionChange?.verdict == .leanLoss)
    }

    /// Меньше погрешности метода — это не результат, и выдавать его за результат
    /// нельзя: у Navy около ±3% жира.
    @Test func changesSmallerThanTheMethodsErrorAreCalledNoise() {
        store.startPlan(startedPlan(weeksAgo: 8, weeks: 12, target: 70))
        store.addMeasurement(session(50, belt: 84.0, neck: 38))
        store.addWeight(77.0, date: Date().addingTimeInterval(-50 * 86_400))
        store.addMeasurement(session(2, belt: 83.6, neck: 38))
        store.addWeight(76.6, date: Date().addingTimeInterval(-2 * 86_400))

        let change = store.planCompositionChange
        #expect(change != nil)
        #expect(abs(change!.leanDeltaKg) <= change!.noiseKg)
        #expect(change?.verdict == .withinNoise)
    }

    /// Без взвешиваний подводить итог не по чему, и выдумывать его нельзя.
    @Test func withoutWeighInsThereIsNoVerdict() {
        store.startPlan(startedPlan(weeksAgo: 9, weeks: 8, target: 71))

        let outcome = store.planOutcome
        #expect(outcome != nil)
        #expect(outcome?.finalWeightKg == nil)
        #expect(outcome?.reachedTarget == false)
    }
}


@MainActor
@Suite(.serialized)
struct FastDayTests {

    private let container: ModelContainer
    private let store: CalorieStore

    init() async throws {
        container = try ModelContainer(
            for: FoodEntry.self, FoodItem.self, WeightEntry.self, GoalRecord.self, Dish.self,
                BodyMeasurement.self, FastDay.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let defaults = TestDefaults.make()
        defaults.set(true, forKey: "is_premium")
        store = CalorieStore(context: container.mainContext, defaults: defaults, groupDefaults: nil)
        store.isPremium = true
        store.dailyGoal = 2000
    }

    private func day(_ ago: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -ago, to: Date())!
    }

    /// Совет приходит к своему дню: за три дня — про кофе, накануне — про соль,
    /// в сам день — как выходить. Раньше памятка лежала в настройках целиком.
    @Test func fastingHint_givesTheAdviceForThatDay() {
        #expect(store.fastingHint() == nil)

        store.markFastDay(day(-3), kind: .dry)
        let early = try! #require(store.fastingHint())
        #expect(early.daysUntil == 3)
        #expect(early.items.allSatisfy { $0.daysBefore.contains(3) })
        #expect(!early.items.isEmpty)

        let dayBefore = try! #require(store.fastingHint(now: day(-2)))
        #expect(dayBefore.daysUntil == 1)
        #expect(dayBefore.items.count == FastingAdvice.advice(for: .dry, daysBefore: 1).count)

        let fastDay = try! #require(store.fastingHint(now: day(-3)))
        #expect(fastDay.daysUntil == 0)
        #expect(fastDay.items.allSatisfy { $0.daysBefore == 0...0 })
    }

    /// Совет пить равномерно — только перед сухим голоданием: на воде он лишний.
    @Test func fastingHint_followsTheKind() {
        store.markFastDay(day(-1), kind: .water)
        let water = try! #require(store.fastingHint())
        store.markFastDay(day(-1), kind: .dry)
        let dry = try! #require(store.fastingHint())
        #expect(dry.items.count == water.items.count + 1)
    }

    /// Дальше трёх дней советовать нечего, и прошедшее голодание подсказку не держит.
    @Test func fastingHint_ignoresFarAndPastFasts() {
        store.markFastDay(day(-5), kind: .dry)
        store.markFastDay(day(1), kind: .dry)
        #expect(store.fastingHint() == nil)
    }

    /// В неделе и истории голодание — день в норме, а не пустой.
    @Test func goalHistory_countsAFastAsKept() {
        store.markFastDay(day(1), kind: .dry)
        let yesterday = try! #require(store.goalHistory(days: 2).first)
        #expect(yesterday.hasEntries)
        #expect(yesterday.onGoal)
    }

    /// Голодание не рвёт серию: человек сделал ровно то, что собирался.
    @Test func aMarkedFastKeepsTheStreak() {
        store.add(name: "Обед", calories: 1500, date: day(2))
        store.markFastDay(day(1), kind: .dry)
        store.add(name: "Обед", calories: 1500, date: day(0))

        #expect(store.streak == 3)
    }

    /// Пустой день без отметки серию по-прежнему рвёт — иначе забытый день
    /// стал бы неотличим от намеренного.
    @Test func anUnmarkedEmptyDayStillBreaksTheStreak() {
        store.add(name: "Обед", calories: 1500, date: day(2))
        store.add(name: "Обед", calories: 1500, date: day(0))

        #expect(store.streak == 1)
    }

    /// Отметку можно снять, и серия возвращается к прежнему поведению.
    @Test func unmarkingRestoresTheBrokenStreak() {
        store.add(name: "Обед", calories: 1500, date: day(2))
        store.markFastDay(day(1), kind: .water)
        store.add(name: "Обед", calories: 1500, date: day(0))
        #expect(store.streak == 3)

        store.unmarkFastDay(day(1))
        #expect(store.streak == 1)
    }

    /// В банк отмеченное голодание входит целиком: ноль там настоящий.
    ///
    /// Дата середины недели берётся явно, а не «сегодня»: в первый день недели
    /// банка ещё нет, и тест падал бы раз в семь дней не по делу.
    @Test func aFastFeedsTheBank() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let daysFromFirst = (calendar.component(.weekday, from: today) - calendar.firstWeekday + 7) % 7
        let weekStart = calendar.date(byAdding: .day, value: -daysFromFirst, to: today)!
        let midWeek = calendar.date(byAdding: .day, value: 3, to: weekStart)!
        let fastDate = calendar.date(byAdding: .day, value: 1, to: weekStart)!

        let withoutFast = store.adaptedGoal(for: midWeek)
        store.markFastDay(fastDate, kind: .dry)

        #expect(store.adaptedGoal(for: midWeek) > withoutFast)
    }

    /// Пост с вечера до вечера следующего дня — как Йом Кипур. Он касается
    /// двух суток, и обе считаются постом.
    @Test func aFastFromEveningToEveningCoversTwoDays() throws {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .hour, value: 18, to: today)!
            .addingTimeInterval(20 * 60)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
            .addingTimeInterval(55 * 60)
        let fast = store.markFast(from: start, to: end, kind: .dry)

        #expect(fast.coveredDays.count == 2)
        #expect(store.isFastDay(today))
        #expect(store.isFastDay(calendar.date(byAdding: .day, value: 1, to: today)!))
        #expect(!store.isFastDay(calendar.date(byAdding: .day, value: -1, to: today)!))
        #expect(fast.isRunning(at: start.addingTimeInterval(3600)))
        #expect(!fast.isRunning(at: start.addingTimeInterval(-3600)))
        #expect(store.runningFast(at: start.addingTimeInterval(3600))?.id == fast.id)
    }

    /// Правка времени меняет ту же отметку, а не заводит вторую — даже когда
    /// новое начало попадает на другие сутки.
    @Test func editingAFastKeepsOneMark() throws {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let start = today.addingTimeInterval(18 * 3600)
        let fast = store.markFast(from: start, to: start.addingTimeInterval(25 * 3600), kind: .dry)

        let moved = start.addingTimeInterval(-26 * 3600)
        let same = store.markFast(from: moved, to: moved.addingTimeInterval(25 * 3600),
                                  kind: .water, replacing: fast)
        #expect(same.id == fast.id)
        #expect(store.fastDays.count == 1)
        #expect(same.kind == .water)
        #expect(same.interval.start == moved)
    }

    /// Кончившийся пост не показывает обратный отсчёт, и старая отметка
    /// «днём» — тоже: считать по ней до полуночи неправильно.
    @Test func aFinishedFastStopsCountingDown() throws {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let start = today.addingTimeInterval(-30 * 3600)
        store.markFast(from: start, to: start.addingTimeInterval(25 * 3600), kind: .dry)
        #expect(store.runningFast() == nil)

        store.markFastDay(today, kind: .dry)
        #expect(store.runningFast() == nil, "Отметка днём не должна считаться идущим постом")
        let hint = try #require(store.fastingHint())
        #expect(hint.remaining() == nil)
    }

    /// Норма поднимается накануне начала поста, а не накануне его конца.
    @Test func theBoostLandsOnTheDayTheFastStarts() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: 1, to: today)!.addingTimeInterval(18 * 3600)
        let plain = store.effectiveGoal(for: today)
        store.markFast(from: start, to: start.addingTimeInterval(25 * 3600), kind: .dry)
        #expect(store.effectiveGoal(for: today) > plain)
        #expect(store.isFastEve(today))
    }

    /// Накануне голодания норма выше: за день можно заправить печёночный
    /// гликоген, и тогда пост начинается не с пустых депо.
    @Test func theEveOfAFastGetsMoreCalories() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let plain = store.effectiveGoal(for: today)
        store.markFastDay(calendar.date(byAdding: .day, value: 1, to: today)!, kind: .dry)
        let eve = store.effectiveGoal(for: today)
        #expect(eve > plain)
        #expect(abs(Double(eve) - Double(plain) * CalorieStore.fastEveBoost) <= 10)
        #expect(store.isFastEve(today))
    }

    /// За два дня норма обычная: заправляются накануне, а не всю неделю.
    @Test func twoDaysBeforeAFastTheGoalIsUnchanged() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let plain = store.effectiveGoal(for: today)
        store.markFastDay(calendar.date(byAdding: .day, value: 2, to: today)!, kind: .dry)
        #expect(store.effectiveGoal(for: today) == plain)
        #expect(!store.isFastEve(today))
    }

    /// С планом банк выключен: норму каждого дня задаёт схема, и недобор
    /// в начале недели не должен раздувать день дефицита.
    @Test func aPlanTurnsTheBankOff() throws {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let daysFromFirst = (calendar.component(.weekday, from: today) - calendar.firstWeekday + 7) % 7
        let weekStart = calendar.date(byAdding: .day, value: -daysFromFirst, to: today)!
        let midWeek = calendar.date(byAdding: .day, value: 3, to: weekStart)!
        store.markFastDay(calendar.date(byAdding: .day, value: 1, to: weekStart)!, kind: .dry)
        #expect(store.adaptedGoal(for: midWeek) > store.effectiveGoal(for: midWeek))

        store.startPlan(Plan(startDate: weekStart, startWeightKg: 77,
                             phases: [PlanPhase(intent: .cut, durationWeeks: 8, weeklyRatePercent: 0.5)]))
        try #require(store.plan != nil)
        #expect(store.adaptedGoal(for: midWeek) == store.effectiveGoal(for: midWeek))
    }

    /// А забытый день в банк не идёт: иначе он изображал бы нулевую еду.
    @Test func anEmptyDayDoesNotFeedTheBank() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let daysFromFirst = (calendar.component(.weekday, from: today) - calendar.firstWeekday + 7) % 7
        let weekStart = calendar.date(byAdding: .day, value: -daysFromFirst, to: today)!
        let midWeek = calendar.date(byAdding: .day, value: 3, to: weekStart)!

        #expect(store.adaptedGoal(for: midWeek) == store.effectiveGoal(for: midWeek))
    }
}
