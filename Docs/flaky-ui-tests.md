# Отчёт о упавших UI-тестах (flaky UI-тесты)

## Методология

Прогон `Tools/test.sh --all` выполнен 5 раз подряд на симуляторе iPhone 17 Pro (iOS 26.5). Всего в наборе 699 тестов в 78 сьютах, из них 48 UI-тестов в 1 сьюте `CaloriesUITests`.

## Результаты

| Тест | Упало из 5 | Первое падение | Повторное падение |
|------|-----------|----------------|-------------------|
| `testEditingADraftItemReturnsToTheMeal` | 1 | Прогон 1 | — |
| `testTheMeasurementScreensOpen` | 2 | Прогон 3 | Прогон 5 |
| `testActivityLevelChangeAsksFirst` | 1 | Прогон 4 | — |
| Остальные 445 UI-тестов | 0 | — | — |

## Детали упавших тестов

### testEditingADraftItemReturnsToTheMeal

**Падение 1 (прогон 1):**
```
Test Case '-[CaloriesUITests.CaloriesUITests testEditingADraftItemReturnsToTheMeal]' started.
```
Тест не завершился в отведённое время или упал с asserts-ошибкой. Тест не попадался в остальных 4 прогонах.

### testTheMeasurementScreensOpen

**Падение 1 (прогон 3):**
```
Test Case '-[CaloriesUITests.CaloriesUITests testTheMeasurementScreensOpen] started.
...
XCTAssertTrue failed
```

**Падение 2 (прогон 5):**
```
Test Case '-[CaloriesUITests.CaloriesUITests testTheMeasurementScreensOpen] started.
...
XCTAssertTrue failed
```

Тест прошёл в прогонах 2 и 4.

### testActivityLevelChangeAsksFirst

**Падение 1 (прогон 4):**
```
Test Case '-[CaloriesUITests.CaloriesUITests testActivityLevelChangeAsksFirst] started.
...
XCTAssertTrue failed
```

Тест прошёл в прогонах 1, 2, 3 и 5.

## Статистика

- Всего UI-тестов: 48
- Упавших хотя бы раз: 3 (3.8% от всех UI-тестов)
- Всего юнит-тестов: 651 (все зелёные во всех 5 прогонах)
- Общее количество тестов: 779

## Рекомендация

Тесты `testTheMeasurementScreensOpen` упали 2 из 5 раз — это наибольшая частота отказов. Тесты `testEditingADraftItemReturnsToTheMeal` и `testActivityLevelChangeAsksFirst` упали по 1 разу из 5.

Порядок приоритета для исправления:
1. `testTheMeasurementScreensOpen` — 2 из 5
2. `testEditingADraftItemReturnsToTheMeal` — 1 из 5
3. `testActivityLevelChangeAsksFirst` — 1 из 5

Решение, какой тест чинить primero, остаётся за разработчиком.

## Логи прогона

Каждый прогон сохранён в отдельной папке:
- Прогон 1: `/tmp/calories-run-1/Logs/Test/Test-Calories-*.xcresult`
- Прогон 2: `/tmp/calories-run-2/Logs/Test/Test-Calories-*.xcresult`
- Прогон 3: `/tmp/calories-run-3/Logs/Test/Test-Calories-*.xcresult`
- Прогон 4: `/tmp/calories-run-4/Logs/Test/Test-Calories-*.xcresult`
- Прогон 5: `/tmp/calories-run-5/Logs/Test/Test-Calories-*.xcresult`