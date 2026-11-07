import Foundation

/// Публикация дневных чисел в общие настройки группы для виджетов и соседей.
///
/// Виджеты живут в своих процессах и не дотягиваются до SwiftData, поэтому
/// приложение кладёт им готовый ответ в `group.calories.shared`. GymLogger
/// читает баланс и признак подписки из той же группы.
extension CalorieStore {

    /// Числа для виджета калорий и макросов — в общие настройки группы.
    ///
    /// День, к которому относятся числа: после полуночи виджет не должен
    /// показывать вчерашнее съеденное, пока приложение не открыли.
    ///
    /// Вызывается из `rebuildCaches()` при каждом пересчёте и из `rebuildTimings()`
    /// для замеров производительности.
    func publishToWidget(_ calendar: Calendar) {
        // День, к которому относятся числа: после полуночи виджет не должен
        // показывать вчерашнее съеденное, пока приложение не открыли.
        groupDefaults?.set(calendar.startOfDay(for: Date()), forKey: "widget_day")
        groupDefaults?.set(consumedToday, forKey: "widget_consumed_today")
        groupDefaults?.set(adaptedTodayGoal, forKey: "widget_goal_today")
        // Макросы виджету: съеденное и цели. Углеводы без цели — это минимум
        // RDA, а не «сколько влезет», поэтому подставляем его, а не ноль.
        groupDefaults?.set(macrosToday.protein, forKey: "widget_protein")
        groupDefaults?.set(macrosToday.fat, forKey: "widget_fat")
        groupDefaults?.set(macrosToday.carbs, forKey: "widget_carbs")
        groupDefaults?.set(proteinTarget ?? 0, forKey: "widget_protein_target")
        groupDefaults?.set(fatTarget ?? 0, forKey: "widget_fat_target")
        groupDefaults?.set(carbsTarget ?? MacroTargets.carbsMinimum, forKey: "widget_carbs_target")
        publishShared()
        publishMealsToWidget()
        publishLastMeal()
    }

    /// То, что о дне и подписке должны знать соседние приложения.
    ///
    /// Читать общую группу GymLogger умеет, а писать в неё может только тот,
    /// кому эти числа принадлежат. Баланс дня нужен ему, чтобы не звать на
    /// тяжёлую тренировку в глубоком дефиците, а признак подписки — чтобы
    /// купленное здесь открывалось и там, без второй покупки.
    ///
    /// Баланс кладём готовым числом, хотя норму и съеденное отдаём рядом:
    /// вычесть одно из другого несложно, но тогда правило «что такое баланс»
    /// живёт в двух приложениях и расходится в тот день, когда изменится здесь.
    private func publishShared() {
        groupDefaults?.set(adaptedTodayGoal - consumedToday, forKey: "shared_balance_today")
        // Своё, а не подаренное: иначе открытое по бандлу соседа уходило бы
        // к нему же обратно как «премиум Calories», и никто бы уже не сказал,
        // за что именно человек заплатил.
        groupDefaults?.set(hasPurchasedPremium || isTrialActive, forKey: "shared_is_premium")
    }

    /// Когда человек ел в последний раз и насколько плотно.
    ///
    /// Нужно не виджету, а соседнему приложению — журналу тренировок: после
    /// плотной еды полтора часа под штангой даются тяжело, и предупредить об
    /// этом может только тот, кто знает про еду. Приложение публикует факт —
    /// время и размер приёма; что с ним делать, решает тот, кто читает.
    ///
    /// Размер отдаём вместе со временем намеренно: двести килокалорий кофе с
    /// молоком и девятьсот обеда — это не одно и то же ожидание, и одинаковый
    /// совет на оба был бы чушью.
    private func publishLastMeal() {
        guard let last = entries.first else {
            groupDefaults?.removeObject(forKey: "last_meal_at")
            groupDefaults?.removeObject(forKey: "last_meal_calories")
            return
        }
        groupDefaults?.set(last.date, forKey: "last_meal_at")
        groupDefaults?.set(last.calories, forKey: "last_meal_calories")
    }

    /// Расписание приёмов — виджету на экране блокировки.
    ///
    /// Отдаём весь день, а не один ближайший приём: виджет живёт своей
    /// временной лентой и должен сам перейти с обеда на ужин в семь вечера, не
    /// дожидаясь, пока приложение откроют.
    ///
    /// Завтрашний день сюда не кладём: нормы на него ещё нет, а без нормы
    /// расписание не считается. Поздним вечером, когда впереди на сегодня уже
    /// ничего, виджет сам сдвигает первый приём на сутки — время у приёмов
    /// каждый день одно и то же, а калории он в таком случае не показывает,
    /// потому что их никто не считал.
    func publishMealsToWidget() {
        let schedule = MealScheduleSettings.shared
        guard schedule.isEnabled else {
            groupDefaults?.removeObject(forKey: "widget_meals")
            return
        }
        // Перекус пропускаем: это не окно расписания, а всё, что съедено мимо
        // окон, и его «время» ничего не значит.
        let payload = slots(on: Date(), schedule: schedule).filter { $0.end > $0.start }.map {
            ["period": $0.period.rawValue,
             "time": $0.time.timeIntervalSince1970,
             "start": $0.start.timeIntervalSince1970,
             "end": $0.end.timeIntervalSince1970,
             "calories": Double($0.calories),
             // Съеденное окно закрыто, даже если его время ещё идёт: виджет
             // обязан переходить к следующему приёму тогда же, когда «Сегодня».
             "state": $0.state.rawValue] as [String: Any]
        }
        groupDefaults?.set(try? JSONSerialization.data(withJSONObject: payload), forKey: "widget_meals")
    }
}
