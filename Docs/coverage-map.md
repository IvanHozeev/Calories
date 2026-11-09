# Карта непокрытой логики CalorieStore и связанных моделей

Покрытие по функциям из `Tools/test.sh --all` прогона (5 прогонов, UI-тесты включены).
Данные из `xcrun xccov view --report --json`.

## Файлы модели с покрытием

| Файл | Покрытие | Строк | Покрытых строк |
|------|----------|-------|----------------|
| ActivityAdjustment.swift | 100.0% | 55 | 55 |
| ActivityHistory.swift | 89.1% | 128 | 114 |
| AdaptiveTDEE.swift | 76.3% | 97 | 74 |
| AppFont.swift | 63.6% | 77 | 49 |
| AppTextSize.swift | 95.2% | 21 | 20 |
| AppTheme.swift | 100.0% | 22 | 22 |
| BackupService.swift | 31.4% | 86 | 27 |
| BodyAnalysis.swift | 94.8% | 383 | 363 |
| BodyBridge.swift | 100.0% | 14 | 14 |
| BodyMeasurement.swift | 100.0% | 189 | 189 |
| CalorieStore+BodyMeasurement.swift | 73.7% | 38 | 28 |
| CalorieStore+Caches.swift | 88.5% | 286 | 253 |
| CalorieStore+Expenditure.swift | 82.0% | 178 | 146 |
| CalorieStore+Fasting.swift | 82.8% | 87 | 72 |
| CalorieStore+Food.swift | 94.9% | 297 | 282 |
| CalorieStore+Goals.swift | 76.2% | 982 | 748 |
| CalorieStore+Kosher.swift | 56.2% | 64 | 36 |
| CalorieStore+Micronutrients.swift | 99.2% | 129 | 128 |
| CalorieStore+Subscription.swift | 97.8% | 45 | 44 |
| CalorieStore+Widget.swift | 100.0% | 69 | 69 |
| CalorieStore.swift | 79.0% | 816 | 645 |
| CookingYield.swift | 100.0% | 23 | 23 |
| DataExport.swift | 50.3% | 143 | 72 |
| DayAnalysis.swift | 95.3% | 192 | 183 |
| DayCategories.swift | 100.0% | 26 | 26 |
| DecimalInput.swift | 100.0% | 7 | 7 |
| Diagnostics.swift | 95.0% | 40 | 38 |
| DiagnosticsStore.swift | 26.9% | 52 | 14 |
| Diary.swift | 94.1% | 152 | 143 |
| DishBatch.swift | 94.4% | 54 | 51 |
| DishKind.swift | 96.0% | 25 | 24 |
| ExplanationLevel.swift | 80.6% | 31 | 25 |
| FastDay.swift | 61.9% | 63 | 39 |
| FastingAdvice.swift | 92.7% | 55 | 51 |
| FoodCatalog.swift | 95.9% | 241 | 231 |
| FoodCategory.swift | 100.0% | 54 | 54 |
| FoodDataCentralService.swift | 38.3% | 81 | 31 |
| FoodDatabase.swift | 100.0% | 68 | 68 |
| FoodSearch.swift | 0.0% | 7 | 0 |
| FoodTrait.swift | 88.7% | 71 | 63 |
| GeminiVisionService.swift | 5.1% | 117 | 6 |
| GymBridge.swift | 96.4% | 56 | 54 |
| HealthInventory.swift | 0.0% | 212 | 0 |
| Kosher.swift | 97.5% | 79 | 77 |
| KosherActivity.swift | 22.7% | 75 | 17 |
| KosherSettings.swift | 68.6% | 51 | 35 |
| MealAdherence.swift | 93.6% | 157 | 147 |
| MealPairs.swift | 98.8% | 82 | 81 |
| MealPeriod.swift | 73.1% | 104 | 76 |
| MealReminders.swift | 65.4% | 159 | 104 |
| MealSchedule.swift | 97.9% | 243 | 238 |
| MealScheduleSettings.swift | 84.0% | 25 | 21 |
| MealSuggestions.swift | 100.0% | 168 | 168 |
| Micronutrient.swift | 95.0% | 201 | 191 |
| OpenFoodService.swift | 69.4% | 144 | 100 |
| PhaseHistory.swift | 93.5% | 77 | 72 |
| Plan.swift | 86.5% | 615 | 532 |
| PlanOutcome.swift | 59.3% | 248 | 147 |
| PurchaseService.swift | 41.8% | 110 | 46 |
| RecipeHint.swift | 92.8% | 69 | 64 |
| RecoverySignal.swift | 89.9% | 109 | 98 |
| ReminderStore.swift | 65.2% | 92 | 60 |
| RestingPulse.swift | 94.4% | 36 | 34 |
| SleepAnalysis.swift | 98.1% | 52 | 51 |
| StallReport.swift | 91.0% | 89 | 81 |
| StepStore.swift | 69.5% | 765 | 532 |
| UserProfile.swift | 92.6% | 189 | 175 |
| UsualMeal.swift | 89.3% | 131 | 117 |
| WeekReview.swift | 97.5% | 159 | 155 |
| WeightTrendFit.swift | 92.9% | 42 | 39 |

## Функции с нулевым покрытием (0% покрытия)

| Файл | Функция | Строки |
|------|---------|--------|
| ActivityHistory.swift | ActivityDay.id.getter | 0 |
| ActivityHistory.swift | closure #1 in ActivityHistory.rememberSteps(_:source:) | 0 |
| ActivityHistory.swift | closure #1 in ActivityHistory.rememberEnergy(_:) | 0 |
| ActivityHistory.swift | ActivityHistory.usualSleepHours(window:minimumNights:now:) | 0 |
| ActivityHistory.swift | closure #1 in ActivityHistory.usualSleepHours(window:minimumNights:now:) | 0 |
| ActivityHistory.swift | implicit closure #1 in ActivityHistory.usualSleepHours(window:minimumNights:now:) | 0 |
| ActivityHistory.swift | implicit closure #2 in ActivityHistory.usualSleepHours(window:minimumNights:now:) | 0 |
| AdaptiveTDEE.swift | AdaptiveTDEE.Confidence.title.getter | 0 |
| AdaptiveTDEE.swift | static AdaptiveTDEE.trend(_:alpha:) | 0 |
| AdaptiveTDEE.swift | closure #1 in static AdaptiveTDEE.trend(_:alpha:) | 0 |
| AdaptiveTDEE.swift | closure #2 in static AdaptiveTDEE.trend(_:alpha:) | 0 |
| AdaptiveTDEE.swift | implicit closure #1 in static AdaptiveTDEE.trend(_:alpha:) | 0 |
| AppFont.swift | static Font.baseSize(_:) | 0 |
| AppTextSize.swift | AppTextSize.id.getter | 0 |
| BackupService.swift | BackupService.useFolder(_:) | 0 |
| BackupService.swift | implicit closure #1 in BackupService.useFolder(_:) | 0 |
| BackupService.swift | static BackupService.filename(for:) | 0 |
| BackupService.swift | BackupService.backupNow(_:now:) | 0 |
| BackupService.swift | implicit closure #1 in BackupService.backupNow(_:now:) | 0 |
| BackupService.swift | BackupService.prune(in:) | 0 |
| BodyAnalysis.swift | BodyAnalysis.SymmetryResult.id.getter | 0 |
| CalorieStore+BodyMeasurement.swift | implicit closure #1 in CalorieStore.addMeasurement(_:) | 0 |
| CalorieStore+BodyMeasurement.swift | CalorieStore.deleteMeasurement(_:) | 0 |
| CalorieStore+BodyMeasurement.swift | implicit closure #1 in CalorieStore.deleteMeasurement(_:) | 0 |
| CalorieStore+BodyMeasurement.swift | closure #1 in CalorieStore.deleteMeasurement(_:) | 0 |
| CalorieStore+BodyMeasurement.swift | implicit closure #1 in CalorieStore.saveMeasurementEdits() | 0 |
| CalorieStore+BodyMeasurement.swift | closure #1 in CalorieStore.saveMeasurementEdits() | 0 |
| CalorieStore+Caches.swift | CalorieStore.rebuildTimings() | 0 |
| CalorieStore+Caches.swift | measure #1 (_:_:) in CalorieStore.rebuildTimings() | 0 |
| CalorieStore+Caches.swift | closure #1 in CalorieStore.rebuildTimings() | 0 |
| CalorieStore+Caches.swift | closure #2 in CalorieStore.rebuildTimings() | 0 |
| CalorieStore+Caches.swift | closure #3 in CalorieStore.rebuildTimings() | 0 |
| CalorieStore+Caches.swift | closure #4 in CalorieStore.rebuildTimings() | 0 |
| CalorieStore+Caches.swift | closure #5 in CalorieStore.rebuildTimings() | 0 |
| CalorieStore+Caches.swift | closure #6 in CalorieStore.rebuildTimings() | 0 |
| CalorieStore+Caches.swift | closure #7 in CalorieStore.rebuildTimings() | 0 |
| CalorieStore+Caches.swift | closure #8 in CalorieStore.rebuildTimings() | 0 |
| CalorieStore+Caches.swift | closure #8 in CalorieStore.rebuildLookups(_:) | 0 |
| CalorieStore+Caches.swift | implicit closure #1 in closure #4 in CalorieStore.rebuildDays(_:) | 0 |
| CalorieStore+Expenditure.swift | implicit closure #2 in CalorieStore.activityAdjustment(on:expenditure:) | 0 |
| CalorieStore+Expenditure.swift | implicit closure #1 in CalorieStore.sleep(on:) | 0 |
| CalorieStore+Expenditure.swift | closure #1 in CalorieStore.sleep(on:) | 0 |
| CalorieStore+Expenditure.swift | implicit closure #2 in CalorieStore.sleep(on:) | 0 |
| CalorieStore+Expenditure.swift | implicit closure #3 in CalorieStore.sleep(on:) | 0 |
| CalorieStore+Expenditure.swift | implicit closure #4 in CalorieStore.sleep(on:) | 0 |
| CalorieStore+Expenditure.swift | closure #1 in CalorieStore.pulses(lastDays:now:) | 0 |
| CalorieStore+Expenditure.swift | implicit closure #1 in CalorieStore.pulses(lastDays:now:) | 0 |
| CalorieStore+Expenditure.swift | implicit closure #1 in static CalorieStore.historyKey(_:) | 0 |
| CalorieStore+Expenditure.swift | implicit closure #2 in static CalorieStore.historyKey(_:) | 0 |
| CalorieStore+Expenditure.swift | implicit closure #3 in static CalorieStore.historyKey(_:) | 0 |
| CalorieStore+Expenditure.swift | implicit closure #1 in closure #1 in CalorieStore.rebuildExpenditure(_:) | 0 |
| CalorieStore+Expenditure.swift | closure #1 in CalorieStore.refreshActivityBaseline(_:today:) | 0 |
| CalorieStore+Expenditure.swift | closure #2 in CalorieStore.refreshActivityBaseline(_:today:) | 0 |
| CalorieStore+Expenditure.swift | implicit closure #1 in closure #2 in CalorieStore.refreshActivityBaseline(_:today:) | 0 |
| CalorieStore+Expenditure.swift | closure #3 in CalorieStore.refreshActivityBaseline(_:today:) | 0 |
| CalorieStore+Expenditure.swift | implicit closure #1 in closure #1 in CalorieStore.rebuildFocusMacro() | 0 |
| CalorieStore+Expenditure.swift | implicit closure #2 in closure #1 in CalorieStore.rebuildFocusMacro() | 0 |
| CalorieStore+Fasting.swift | CalorieStore.nearestFast(to:) | 0 |
| CalorieStore+Fasting.swift | closure #1 in CalorieStore.nearestFast(to:) | 0 |
| CalorieStore+Fasting.swift | implicit closure #2 in CalorieStore.markFast(from:to:kind:replacing:) | 0 |
| CalorieStore+Fasting.swift | implicit closure #3 in CalorieStore.markFast(from:to:kind:replacing:) | 0 |
| CalorieStore+Fasting.swift | closure #1 in CalorieStore.markFast(from:to:kind:replacing:) | 0 |
| CalorieStore+Fasting.swift | implicit closure #1 in CalorieStore.markFastDay(_:kind:) | 0 |
| CalorieStore+Fasting.swift | implicit closure #2 in CalorieStore.markFastDay(_:kind:) | 0 |
| CalorieStore+Fasting.swift | implicit closure #1 in CalorieStore.unmarkFastDay(_:) | 0 |
| CalorieStore+Food.swift | implicit closure #1 in CalorieStore.pairSuggestions(draft:days:) | 0 |
| CalorieStore+Food.swift | implicit closure #1 in closure #2 in closure #2 in CalorieStore.batchState(of:now:) | 0 |
| CalorieStore+Food.swift | closure #2 in CalorieStore.liveBatches(now:) | 0 |
| CalorieStore+Food.swift | closure #1 in CalorieStore.batchHint(now:) | 0 |
| CalorieStore+Food.swift | closure #2 in CalorieStore.batchHint(now:) | 0 |
| CalorieStore+Food.swift | implicit closure #1 in CalorieStore.usualMeals(period:days:) | 0 |
| CalorieStore+Food.swift | implicit closure #1 in CalorieStore.mealSuggestions(remaining:days:) | 0 |
| CalorieStore+Food.swift | closure #3 in CalorieStore.mealSuggestions(remaining:days:) | 0 |
| CalorieStore+Food.swift | implicit closure #1 in closure #3 in CalorieStore.mealSuggestions(remaining:days:) | 0 |
| CalorieStore+Food.swift | implicit closure #1 in CalorieStore.recentMeals(limit:days:) | 0 |
| CalorieStore+Food.swift | implicit closure #1 in closure #2 in CalorieStore.dishes(containing:) | 0 |
| CalorieStore+Food.swift | implicit closure #2 in closure #2 in CalorieStore.dishes(containing:) | 0 |
| CalorieStore+Goals.swift | implicit closure #2 in CalorieStore.weekStripWeeks(maxWeeks:) | 0 |
| CalorieStore+Goals.swift | implicit closure #1 in CalorieStore.computeProteinStreak() | 0 |
| CalorieStore+Goals.swift | implicit closure #1 in CalorieStore.computeStreak() | 0 |
| CalorieStore+Goals.swift | implicit closure #3 in CalorieStore.computeStreak() | 0 |
| CalorieStore+Goals.swift | CalorieStore.achievements.getter | 0 |
| CalorieStore+Goals.swift | CalorieStore.macroSuggestion.getter | 0 |
| CalorieStore+Goals.swift | implicit closure #1 in CalorieStore.macroSuggestion.getter | 0 |
| CalorieStore+Goals.swift | CalorieStore.todayGoal.getter | 0 |
| CalorieStore+Goals.swift | CalorieStore.summary(for:) | 0 |
| CalorieStore+Goals.swift | implicit closure #1 in CalorieStore.summary(for:) | 0 |
| CalorieStore+Goals.swift | CalorieStore.lastDays(_:) | 0 |
| CalorieStore+Goals.swift | closure #1 in CalorieStore.lastDays(_:) | 0 |
| CalorieStore+Goals.swift | implicit closure #1 in closure #1 in CalorieStore.lastDays(_:) | 0 |
| CalorieStore+Goals.swift | implicit closure #1 in CalorieStore.planCompositionChange.getter | 0 |
| CalorieStore+Goals.swift | implicit closure #1 in CalorieStore.slots(on:schedule:now:) | 0 |
| CalorieStore+Goals.swift | CalorieStore.adherenceDays(back:schedule:now:) | 0 |
| CalorieStore+Goals.swift | closure #1 in CalorieStore.adherenceDays(back:schedule:now:) | 0 |
| CalorieStore+Goals.swift | implicit closure #1 in closure #1 in CalorieStore.adherenceDays(back:schedule:now:) | 0 |
| CalorieStore+Goals.swift | closure #1 in closure #1 in CalorieStore.adherenceDays(back:schedule:now:) | 0 |
| CalorieStore+Goals.swift | implicit closure #2 in CalorieStore.weekReviewInput(now:) | 0 |
| CalorieStore+Goals.swift | closure #6 in CalorieStore.weekReviewInput(now:) | 0 |
| CalorieStore+Goals.swift | implicit closure #3 in CalorieStore.weekReviewInput(now:) | 0 |
| CalorieStore+Goals.swift | implicit closure #4 in CalorieStore.weekReviewInput(now:) | 0 |
| CalorieStore+Goals.swift | implicit closure #1 in CalorieStore.recoveryInput(now:) | 0 |
| CalorieStore+Goals.swift | implicit closure #2 in CalorieStore.recoveryInput(now:) | 0 |
| CalorieStore+Goals.swift | implicit closure #3 in CalorieStore.recoveryInput(now:) | 0 |
| CalorieStore+Goals.swift | closure #1 in CalorieStore.recoveryInput(now:) | 0 |
| CalorieStore+Goals.swift | closure #2 in CalorieStore.recoveryInput(now:) | 0 |
| CalorieStore+Goals.swift | closure #1 in closure #2 in CalorieStore.recoveryInput(now:) | 0 |
| CalorieStore+Goals.swift | implicit closure #4 in CalorieStore.recoveryInput(now:) | 0 |
| CalorieStore+Goals.swift | CalorieStore.stallWeeks(now:plannedWeeklyKg:) | 0 |
| CalorieStore+Goals.swift | CalorieStore.tdeeDropPercent(now:days:) | 0 |
| CalorieStore+Goals.swift | CalorieStore.stallInput(window:now:) | 0 |
| CalorieStore+Goals.swift | implicit closure #1 in CalorieStore.stallInput(window:now:) | 0 |
| CalorieStore+Goals.swift | implicit closure #2 in CalorieStore.stallInput(window:now:) | 0 |
| CalorieStore+Goals.swift | implicit closure #3 in implicit closure #2 in CalorieStore.stallInput(window:now:) | 0 |
| CalorieStore+Goals.swift | closure #1 in CalorieStore.stallInput(window:now:) | 0 |
| CalorieStore+Goals.swift | implicit closure #1 in closure #1 in CalorieStore.stallInput(window:now:) | 0 |
| CalorieStore+Goals.swift | closure #2 in CalorieStore.stallInput(window:now:) | 0 |
| CalorieStore+Goals.swift | closure #3 in CalorieStore.stallInput(window:now:) | 0 |
| CalorieStore+Goals.swift | closure #4 in CalorieStore.stallInput(window:now:) | 0 |
| CalorieStore+Goals.swift | closure #5 in CalorieStore.stallInput(window:now:) | 0 |
| CalorieStore+Goals.swift | closure #6 in CalorieStore.stallInput(window:now:) | 0 |
| CalorieStore+Goals.swift | closure #7 in CalorieStore.stallInput(window:now:) | 0 |
| CalorieStore+Goals.swift | implicit closure #1 in closure #7 in CalorieStore.stallInput(window:now:) | 0 |
| CalorieStore+Goals.swift | implicit closure #4 in CalorieStore.stallInput(window:now:) | 0 |
| CalorieStore+Goals.swift | implicit closure #5 in CalorieStore.stallInput(window:now:) | 0 |
| CalorieStore+Goals.swift | closure #1 in CalorieStore.dayContext(on:) | 0 |
| CalorieStore+Goals.swift | closure #2 in CalorieStore.dayContext(on:) | 0 |
| CalorieStore+Goals.swift | implicit closure #2 in CalorieStore.computePlanAdherence() | 0 |
| CalorieStore+Goals.swift | implicit closure #3 in CalorieStore.computePlanAdherence() | 0 |
| CalorieStore+Goals.swift | implicit closure #5 in CalorieStore.computePlanAdherence() | 0 |
| CalorieStore+Goals.swift | implicit closure #1 in CalorieStore.syncGoalWithExpenditure() | 0 |
| CalorieStore+Goals.swift | closure #2 in CalorieStore.rememberTodaysGoal(_:) | 0 |
| CalorieStore+Goals.swift | implicit closure #1 in CalorieStore.rememberTodaysGoal(_:) | 0 |
| CalorieStore+Goals.swift | implicit closure #1 in CalorieStore.lockPastGoals() | 0 |
| CalorieStore+Kosher.swift | closure #3 in CalorieStore.kosherParts(named:) | 0 |
| CalorieStore+Kosher.swift | CalorieStore.kosherStatus(of:) | 0 |
| CalorieStore+Kosher.swift | implicit closure #1 in CalorieStore.kosherStatus(of:) | 0 |
| CalorieStore+Kosher.swift | CalorieStore.isKosherMixed(_:) | 0 |
| CalorieStore+Kosher.swift | implicit closure #1 in CalorieStore.isKosherMixed(_:) | 0 |
| CalorieStore+Kosher.swift | CalorieStore.isKosherMixed(draft:) | 0 |
| CalorieStore+Kosher.swift | closure #1 in CalorieStore.isKosherMixed(draft:) | 0 |
| CalorieStore+Kosher.swift | implicit closure #1 in CalorieStore.isKosherMixed(draft:) | 0 |
| CalorieStore+Kosher.swift | CalorieStore.hasForbidden(_:) | 0 |
| CalorieStore+Kosher.swift | closure #1 in CalorieStore.hasForbidden(_:) | 0 |
| CalorieStore+Kosher.swift | CalorieStore.setKosher(_:hardCheese:forFoodNamed:) | 0 |
| CalorieStore+Kosher.swift | closure #1 in CalorieStore.setKosher(_:hardCheese:forFoodNamed:) | 0 |
| CalorieStore+Micronutrients.swift | implicit closure #1 in MicronutrientDay.fiber.getter | 0 |
| CalorieStore+Subscription.swift | implicit closure #1 in CalorieStore.trialDaysLeft.getter | 0 |
| CalorieStore.swift | implicit closure #1 in variable initialization expression of storeLogger | 0 |
| CalorieStore.swift | implicit closure #1 in CalorieStore.refreshSharedEntitlements() | 0 |
| CalorieStore.swift | implicit closure #3 in implicit closure #2 in CalorieStore.refreshSharedEntitlements() | 0 |
| CalorieStore.swift | closure #1 in CalorieStore.init(context:defaults:groupDefaults:) | 0 |
| CalorieStore.swift | implicit closure #6 in CalorieStore.init(context:defaults:groupDefaults:) | 0 |
| CalorieStore.swift | implicit closure #1 in CalorieStore.refresh() | 0 |
| CalorieStore.swift | implicit closure #2 in CalorieStore.refresh() | 0 |
| CalorieStore.swift | implicit closure #3 in CalorieStore.refresh() | 0 |
| CalorieStore.swift | implicit closure #4 in CalorieStore.refresh() | 0 |
| CalorieStore.swift | implicit closure #5 in CalorieStore.refresh() | 0 |
| CalorieStore.swift | implicit closure #6 in CalorieStore.refresh() | 0 |
| CalorieStore.swift | implicit closure #7 in CalorieStore.refresh() | 0 |
| CalorieStore.swift | implicit closure #8 in CalorieStore.refresh() | 0 |
| CalorieStore.swift | implicit closure #9 in CalorieStore.refresh() | 0 |
| CalorieStore.swift | implicit closure #10 in CalorieStore.refresh() | 0 |
| CalorieStore.swift | implicit closure #1 in CalorieStore.restoreCroppedNames() | 0 |
| CalorieStore.swift | closure #1 in CalorieStore.restoreCroppedNames() | 0 |
| CalorieStore.swift | implicit closure #2 in CalorieStore.restoreCroppedNames() | 0 |
| CalorieStore.swift | implicit closure #7 in CalorieStore.restore(from:) | 0 |
| CalorieStore.swift | implicit closure #8 in CalorieStore.restore(from:) | 0 |
| CalorieStore.swift | closure #1 in CalorieStore.maintenanceSince.getter | 0 |
| CalorieStore.swift | implicit closure #2 in CalorieStore.maintenanceSince.getter | 0 |
| CalorieStore.swift | implicit closure #3 in implicit closure #2 in CalorieStore.maintenanceSince.getter | 0 |
| CalorieStore.swift | CalorieStore.rememberFinishedPlan(_:now:) | 0 |
| CalorieStore.swift | closure #1 in CalorieStore.rememberFinishedPlan(_:now:) | 0 |
| CalorieStore.swift | implicit closure #1 in CalorieStore.rememberFinishedPlan(_:now:) | 0 |
| CalorieStore.swift | implicit closure #2 in implicit closure #1 in CalorieStore.rememberFinishedPlan(_:now:) | 0 |
| CalorieStore.swift | CalorieStore.cancelPlan() | 0 |
| CalorieStore.swift | CalorieStore.moveRefeed(to:) | 0 |
| CalorieStore.swift | CalorieStore.startDietBreak(weeks:from:) | 0 |
| CalorieStore.swift | CalorieStore.cancelPendingDietBreak(on:) | 0 |
| CalorieStore.swift | CalorieStore.undoRefeedMove(on:) | 0 |
| CalorieStore.swift | CalorieStore.savePlanKeepingGoal(_:) | 0 |
| CalorieStore.swift | CalorieStore.goalAgreedAt.getter | 0 |
| CalorieStore.swift | implicit closure #1 in CalorieStore.proposeGoalChange(plan:) | 0 |
| CalorieStore.swift | CalorieStore.acceptProposedGoal() | 0 |
| CalorieStore.swift | implicit closure #1 in CalorieStore.add(name:calories:macros:grams:date:components:) | 0 |
| CalorieStore.swift | implicit closure #1 in CalorieStore.delete(entry:) | 0 |
| CalorieStore.swift | implicit closure #1 in CalorieStore.updateEntry(_:name:calories:macros:grams:date:components:) | 0 |
| CalorieStore.swift | closure #1 in CalorieStore.updateEntry(_:name:calories:macros:grams:date:components:) | 0 |
| CalorieStore.swift | implicit closure #1 in CalorieStore.addCustomFood(name:caloriesPer100g:protein:fat:carbs:category:defaultGrams:micronutrients:catalogID:micronutrientsAreEstimated:producer:) | 0 |
| CalorieStore.swift | CalorieStore.saveToMyFoods(_:) | 0 |
| CalorieStore.swift | implicit closure #1 in CalorieStore.deleteCustomFood(_:) | 0 |
| CalorieStore.swift | implicit closure #1 in CalorieStore.updateCustomFood(_:name:caloriesPer100g:protein:fat:carbs:category:defaultGrams:micronutrients:catalogID:micronutrientsAreEstimated:producer:) | 0 |
| CalorieStore.swift | closure #1 in CalorieStore.updateCustomFood(_:name:caloriesPer100g:protein:fat:carbs:category:defaultGrams:micronutrients:catalogID:micronutrientsAreEstimated:producer:) | 0 |
| CalorieStore.swift | implicit closure #1 in CalorieStore.persistCustomFoods() | 0 |
| CalorieStore.swift | closure #1 in CalorieStore.persistCustomFoods() | 0 |
| CalorieStore.swift | implicit closure #1 in CalorieStore.addDish(name:ingredients:servingGrams:kind:) | 0 |
| CalorieStore.swift | implicit closure #1 in CalorieStore.persistDishes() | 0 |
| CalorieStore.swift | CalorieStore.updateDish(_:name:ingredients:servingGrams:kind:) | 0 |
| CalorieStore.swift | implicit closure #1 in CalorieStore.updateDish(_:name:ingredients:servingGrams:kind:) | 0 |
| CalorieStore.swift | implicit closure #1 in CalorieStore.deleteDish(_:) | 0 |
| CalorieStore.swift | implicit closure #1 in CalorieStore.addWeight(_:date:) | 0 |
| CalorieStore.swift | implicit closure #1 in CalorieStore.deleteWeight(_:) | 0 |
| CalorieStore.swift | CalorieStore.propagate(dishNamed:renamedTo:) | 0 |
| CalorieStore.swift | CalorieStore.foodNamed(_:) | 0 |
| CalorieStore.swift | implicit closure #1 in CalorieStore.foodNamed(_:) | 0 |
| CalorieStore.swift | closure #1 in implicit closure #1 in CalorieStore.foodNamed(_:) | 0 |
| CalorieStore.swift | implicit closure #1 in CalorieStore.weightHistory(lastDays:) | 0 |
| CalorieStore.swift | closure #1 in CalorieStore.weightHistory(lastDays:) | 0 |
| DataExport.swift | implicit closure #1 in CalorieStore.makeBackup() | 0 |
| DataExport.swift | closure #4 in CalorieStore.makeBackup() | 0 |
| DataExport.swift | CalorieStore.makeDiaryCSV() | 0 |
| DataExport.swift | closure #1 in CalorieStore.makeDiaryCSV() | 0 |
| DataExport.swift | closure #2 in CalorieStore.makeDiaryCSV() | 0 |
| DataExport.swift | implicit closure #1 in CalorieStore.makeDiaryCSV() | 0 |
| DataExport.swift | CalorieStore.makeGymProfileCSV(now:) | 0 |
| DataExport.swift | implicit closure #1 in CalorieStore.makeGymProfileCSV(now:) | 0 |
| DataExport.swift | implicit closure #2 in implicit closure #1 in CalorieStore.makeGymProfileCSV(now:) | 0 |
| DataExport.swift | CalorieStore.makeGymWeightsCSV() | 0 |
| DataExport.swift | closure #1 in CalorieStore.makeGymWeightsCSV() | 0 |
| DataExport.swift | static CalorieStore.csvEscape(_:) | 0 |
| DataExport.swift | implicit closure #1 in static CalorieStore.csvEscape(_:) | 0 |
| DataExport.swift | implicit closure #2 in static CalorieStore.csvEscape(_:) | 0 |
| DataExport.swift | static ExportDocument.readableContentTypes.getter | 0 |
| DataExport.swift | ExportDocument.init(text:type:) | 0 |
| DataExport.swift | ExportDocument.init(configuration:) | 0 |
| DataExport.swift | implicit closure #1 in ExportDocument.init(configuration:) | 0 |
| DataExport.swift | ExportDocument.fileWrapper(configuration:) | 0 |
| Diagnostics.swift | implicit closure #4 in static Diagnostics.reports(fromPayload:now:) | 0 |
| Diagnostics.swift | implicit closure #5 in static Diagnostics.reports(fromPayload:now:) | 0 |
| DiagnosticsStore.swift | implicit closure #1 in variable initialization expression of static DiagnosticsStore.logger | 0 |
| DiagnosticsStore.swift | DiagnosticsStore.didReceive(_:) | 0 |
| DiagnosticsStore.swift | closure #1 in DiagnosticsStore.didReceive(_:) | 0 |
| DiagnosticsStore.swift | closure #2 in DiagnosticsStore.didReceive(_:) | 0 |
| DiagnosticsStore.swift | DiagnosticsStore.didReceive(_:) | 0 |
| DiagnosticsStore.swift | DiagnosticsStore.record(_:now:) | 0 |
| DiagnosticsStore.swift | implicit closure #1 in DiagnosticsStore.record(_:now:) | 0 |
| DiagnosticsStore.swift | DiagnosticsStore.payloadFiles.getter | 0 |
| DiagnosticsStore.swift | implicit closure #1 in DiagnosticsStore.payloadFiles.getter | 0 |
| DiagnosticsStore.swift | closure #1 in DiagnosticsStore.payloadFiles.getter | 0 |
| DiagnosticsStore.swift | DiagnosticsStore.clear() | 0 |
| DiagnosticsStore.swift | DiagnosticsStore.save() | 0 |
| Diary.swift | MacroKind.id.getter | 0 |
| Diary.swift | implicit closure #1 in FoodEntry.components.getter | 0 |
| Diary.swift | implicit closure #1 in Dish.init(id:name:ingredients:createdAt:) | 0 |
| Diary.swift | implicit closure #1 in Dish.ingredients.getter | 0 |
| Diary.swift | implicit closure #1 in Dish.ingredients.setter | 0 |
| Diary.swift | variable initialization expression of MealItem.id | 0 |
| Diary.swift | variable initialization expression of MealItem.grams | 0 |
| Diary.swift | MacroDay.id.getter | 0 |
| Diary.swift | DaySummary.id.getter | 0 |
| DishBatch.swift | implicit closure #1 in static DishBatch.state(cookedAt:totalGrams:eatenGrams:servingGrams:now:calendar:) | 0 |
| DishBatch.swift | implicit closure #2 in static DishBatch.state(cookedAt:totalGrams:eatenGrams:servingGrams:now:calendar:) | 0 |
| DishBatch.swift | implicit closure #1 in static DishBatch.advice(_:now:calendar:) | 0 |
| DishKind.swift | DishKind.id.getter | 0 |
| ExplanationLevel.swift | ExplanationSettings.wasAsked.getter | 0 |
| ExplanationLevel.swift | implicit closure #1 in ExplanationSettings.init(defaults:) | 0 |
| FastDay.swift | implicit closure #1 in FastDay.kind.getter | 0 |
| FastDay.swift | implicit closure #3 in implicit closure #2 in FastDay.interval.getter | 0 |
| FastDay.swift | FastKind.id.getter | 0 |
| FastDay.swift | FastKind.title.getter | 0 |
| FastDay.swift | variable initialization expression of FastingHint.interval | 0 |
| FastDay.swift | FastingHint.isRunning(at:) | 0 |
| FastDay.swift | implicit closure #1 in FastingHint.isRunning(at:) | 0 |
| FastDay.swift | static FastingHint.== infix(_:_:) | 0 |
| FastDay.swift | implicit closure #1 in static FastingHint.== infix(_:_:) | 0 |
| FastDay.swift | implicit closure #2 in static FastingHint.== infix(_:_:) | 0 |
| FastDay.swift | implicit closure #3 in static FastingHint.== infix(_:_:) | 0 |
| FastDay.swift | implicit closure #4 in implicit closure #3 in static FastingHint.== infix(_:_:) | 0 |
| FastDay.swift | implicit closure #5 in implicit closure #3 in static FastingHint.== infix(_:_:) | 0 |
| FastingAdvice.swift | variable initialization expression of FastingAdvice.Item.id | 0 |
| FastingAdvice.swift | static FastingAdvice.medicalNote.getter | 0 |
| FoodCatalog.swift | implicit closure #1 in CatalogFood.foodCategory.getter | 0 |
| FoodCatalog.swift | implicit closure #1 in static FoodCatalog.prefersRussian.getter | 0 |
| FoodCatalog.swift | closure #2 in variable initialization expression of static FoodCatalog.nutrientProfilesByName | 0 |
| FoodCatalog.swift | implicit closure #2 in static FoodCatalog.search(_:limit:) | 0 |
| FoodCatalog.swift | implicit closure #4 in static FoodCatalog.donors(forName:caloriesPer100g:macrosPer100g:category:limit:) | 0 |
| FoodDataCentralService.swift | FoodDataCentralService.ServiceError.errorDescription.getter | 0 |
| FoodDataCentralService.swift | closure #1 in variable initialization expression of static FoodDataCentralService.session | 0 |
| FoodDataCentralService.swift | static FoodDataCentralService.apiKey.getter | 0 |
| FoodDataCentralService.swift | static FoodDataCentralService.isConfigured.getter | 0 |
| FoodDataCentralService.swift | static FoodDataCentralService.search(query:) | 0 |
| FoodDataCentralService.swift | implicit closure #1 in static FoodDataCentralService.search(query:) | 0 |
| FoodDataCentralService.swift | implicit closure #1 in static FoodDataCentralService.item(from:) | 0 |
| FoodSearch.swift | static FoodSearch.providesMicronutrients.getter | 0 |
| FoodSearch.swift | static FoodSearch.search(query:) | 0 |
| FoodTrait.swift | FoodTrait.isWarning.getter | 0 |
| FoodTrait.swift | implicit closure #1 in static FoodTrait.traits(caloriesPer100g:macros:category:) | 0 |
| FoodTrait.swift | Dish.traits.getter | 0 |
| GeminiVisionService.swift | GeminiVisionService.ServiceError.errorDescription.getter | 0 |
| GeminiVisionService.swift | closure #1 in variable initialization expression of static GeminiVisionService.session | 0 |
| GeminiVisionService.swift | static GeminiVisionService.answerLanguage.getter | 0 |
| GeminiVisionService.swift | implicit closure #1 in static GeminiVisionService.answerLanguage.getter | 0 |
| GeminiVisionService.swift | implicit closure #2 in static GeminiVisionService.answerLanguage.getter | 0 |
| GeminiVisionService.swift | static GeminiVisionService.prompt.getter | 0 |
| GeminiVisionService.swift | static GeminiVisionService.recognize(imageData:) | 0 |
| GeminiVisionService.swift | implicit closure #1 in static GeminiVisionService.recognize(imageData:) | 0 |
| GeminiVisionService.swift | implicit closure #2 in static GeminiVisionService.recognize(imageData:) | 0 |
| GeminiVisionService.swift | static GeminiVisionService.endpoint(apiKey:) | 0 |
| GeminiVisionService.swift | static GeminiVisionService.mealItem(from:) | 0 |
| GeminiVisionService.swift | implicit closure #1 in static GeminiVisionService.mealItem(from:) | 0 |
| GeminiVisionService.swift | implicit closure #2 in static GeminiVisionService.mealItem(from:) | 0 |
| GeminiVisionService.swift | implicit closure #3 in static GeminiVisionService.mealItem(from:) | 0 |
| GymBridge.swift | implicit closure #1 in static GymBridge.Freshness.days(between:and:_:) | 0 |
| GymBridge.swift | implicit closure #1 in static GymBridge.isDeload(_:now:calendar:) | 0 |
| HealthInventory.swift | variable initialization expression of HealthInventory.Row.isDaily | 0 |
| HealthInventory.swift | variable initialization expression of HealthInventory.healthStore | 0 |
| HealthInventory.swift | variable initialization expression of HealthInventory.rows | 0 |
| HealthInventory.swift | variable initialization expression of HealthInventory.isChecking | 0 |
| HealthInventory.swift | HealthInventory.probes.getter | 0 |
| HealthInventory.swift | HealthInventory.check() | 0 |
| HealthInventory.swift | implicit closure #1 in HealthInventory.check() | 0 |
| HealthInventory.swift | HealthInventory.row(for:title:since:) | 0 |
| HealthInventory.swift | closure #1 in HealthInventory.row(for:title:since:) | 0 |
| HealthInventory.swift | closure #2 in HealthInventory.row(for:title:since:) | 0 |
| HealthInventory.swift | closure #3 in HealthInventory.row(for:title:since:) | 0 |
| HealthInventory.swift | closure #4 in HealthInventory.row(for:title:since:) | 0 |
| HealthInventory.swift | closure #5 in HealthInventory.row(for:title:since:) | 0 |
| HealthInventory.swift | implicit closure #1 in HealthInventory.row(for:title:since:) | 0 |
| HealthInventory.swift | closure #6 in HealthInventory.row(for:title:since:) | 0 |
| HealthInventory.swift | closure #7 in HealthInventory.row(for:title:since:) | 0 |
| HealthInventory.swift | closure #8 in HealthInventory.row(for:title:since:) | 0 |
| HealthInventory.swift | closure #9 in HealthInventory.row(for:title:since:) | 0 |
| HealthInventory.swift | closure #10 in HealthInventory.row(for:title:since:) | 0 |
| HealthInventory.swift | closure #11 in HealthInventory.row(for:title:since:) | 0 |
| HealthInventory.swift | implicit closure #2 in HealthInventory.row(for:title:since:) | 0 |
| HealthInventory.swift | closure #12 in HealthInventory.row(for:title:since:) | 0 |
| HealthInventory.swift | closure #13 in HealthInventory.row(for:title:since:) | 0 |
| HealthInventory.swift | implicit closure #3 in HealthInventory.row(for:title:since:) | 0 |
| HealthInventory.swift | implicit closure #4 in HealthInventory.row(for:title:since:) | 0 |
| HealthInventory.swift | HealthInventory.quantityRow(_:_:_:_:unit:format:since:) | 0 |
| HealthInventory.swift | closure #1 in HealthInventory.quantityRow(_:_:_:_:unit:format:since:) | 0 |
| HealthInventory.swift | closure #1 in closure #1 in HealthInventory.quantityRow(_:_:_:_:unit:format:since:) | 0 |
| HealthInventory.swift | closure #2 in HealthInventory.quantityRow(_:_:_:_:unit:format:since:) | 0 |
| HealthInventory.swift | implicit closure #1 in closure #2 in HealthInventory.quantityRow(_:_:_:_:unit:format:since:) | 0 |
| HealthInventory.swift | HealthInventory.fetch(_:since:) | 0 |
| HealthInventory.swift | closure #1 in HealthInventory.fetch(_:since:) | 0 |
| HealthInventory.swift | closure #1 in closure #1 in HealthInventory.fetch(_:since:) | 0 |
| HealthInventory.swift | implicit closure #1 in closure #1 in closure #1 in HealthInventory.fetch(_:since:) | 0 |
| HealthInventory.swift | static HealthInventory.isDense(days:window:) | 0 |
| Kosher.swift | KosherStatus.id.getter | 0 |
| KosherActivity.swift | static KosherActivity.current.getter | 0 |
| KosherActivity.swift | implicit closure #1 in static KosherActivity.sync(waits:enabled:) | 0 |
| KosherActivity.swift | closure #1 in static KosherActivity.sync(waits:enabled:) | 0 |
| KosherActivity.swift | static KosherActivity.end() | 0 |
| KosherActivity.swift | closure #1 in static KosherActivity.end() | 0 |
| KosherActivity.swift | static KosherActivity.request(blocked:since:state:) | 0 |
| KosherSettings.swift | KosherStatus.title.getter | 0 |
| KosherSettings.swift | KosherStatus.symbol.getter | 0 |
| MealAdherence.swift | MealAdherence.Habit.id.getter | 0 |
| MealAdherence.swift | implicit closure #3 in closure #1 in static MealAdherence.habits(_:minimumDays:) | 0 |
| MealAdherence.swift | implicit closure #4 in closure #1 in static MealAdherence.habits(_:minimumDays:) | 0 |
| MealAdherence.swift | MealAdherence.Suggestion.id.getter | 0 |
| MealPairs.swift | MealPairs.Suggestion.id.getter | 0 |
| MealPeriod.swift | MealPeriod.timeTitle.getter | 0 |
| MealPeriod.swift | MealPeriod.representativeHour.getter | 0 |
| MealPeriod.swift | implicit closure #1 in closure #3 in static MealPeriod.group(_:) | 0 |
| MealPeriod.swift | implicit closure #2 in closure #3 in static MealPeriod.group(_:) | 0 |
| MealPeriod.swift | closure #1 in closure #3 in static MealPeriod.group(_:) | 0 |
| MealPeriod.swift | implicit closure #1 in closure #1 in closure #3 in static MealPeriod.group(_:) | 0 |
| MealReminders.swift | implicit closure #1 in variable initialization expression of logger | 0 |
| MealReminders.swift | implicit closure #1 in static MealReminders.reschedule(settings:store:center:) | 0 |
| MealReminders.swift | implicit closure #1 in closure #2 in static MealReminders.reschedule(settings:store:center:) | 0 |
| MealReminders.swift | closure #1 in closure #2 in static MealReminders.reschedule(settings:store:center:) | 0 |
| MealReminders.swift | implicit closure #2 in closure #2 in static MealReminders.reschedule(settings:store:center:) | 0 |
| MealReminders.swift | implicit closure #3 in closure #2 in static MealReminders.reschedule(settings:store:center:) | 0 |
| MealReminders.swift | implicit closure #4 in closure #2 in static MealReminders.reschedule(settings:store:center:) | 0 |
| MealReminders.swift | implicit closure #5 in closure #2 in static MealReminders.reschedule(settings:store:center:) | 0 |
| MealReminders.swift | static MealReminders.snooze(_:center:) | 0 |
| MealReminders.swift | implicit closure #1 in static MealReminders.snooze(_:center:) | 0 |
| MealSchedule.swift | implicit closure #1 in at #1 (_:) in static MealSchedule.times(wake:sleep:count:calendar:) | 0 |
| MealSchedule.swift | implicit closure #1 in static MealSchedule.times(wake:sleep:count:calendar:) | 0 |
| MealSchedule.swift | implicit closure #2 in static MealSchedule.times(wake:sleep:count:calendar:) | 0 |
| MealScheduleSettings.swift | implicit closure #1 in MealScheduleSettings.today(_:now:) | 0 |
| MealScheduleSettings.swift | implicit closure #2 in MealScheduleSettings.today(_:now:) | 0 |
| MealScheduleSettings.swift | implicit closure #3 in MealScheduleSettings.today(_:now:) | 0 |
| MealScheduleSettings.swift | implicit closure #1 in static MealScheduleSettings.time(_:hour:) | 0 |
| Micronutrient.swift | Micronutrient.unit.getter | 0 |
| OpenFoodService.swift | OpenFoodService.ServiceError.errorDescription.getter | 0 |
| OpenFoodService.swift | closure #1 in variable initialization expression of static OpenFoodService.session | 0 |
| OpenFoodService.swift | static OpenFoodService.search(query:) | 0 |
| OpenFoodService.swift | implicit closure #1 in closure #1 in static OpenFoodService.parseSearch(_:) | 0 |
| OpenFoodService.swift | implicit closure #2 in closure #1 in static OpenFoodService.parseSearch(_:) | 0 |
| OpenFoodService.swift | implicit closure #4 in closure #1 in static OpenFoodService.parseSearch(_:) | 0 |
| OpenFoodService.swift | implicit closure #5 in closure #1 in static OpenFoodService.parseSearch(_:) | 0 |
| OpenFoodService.swift | implicit closure #6 in closure #1 in static OpenFoodService.parseSearch(_:) | 0 |
| OpenFoodService.swift | static OpenFoodService.product(barcode:) | 0 |
| OpenFoodService.swift | implicit closure #1 in static OpenFoodService.parseProduct(_:barcode:) | 0 |
| OpenFoodService.swift | implicit closure #2 in static OpenFoodService.parseProduct(_:barcode:) | 0 |
| OpenFoodService.swift | variable initialization expression of BarcodeProduct.micronutrients | 0 |
| PhaseHistory.swift | PhaseRecord.changeKg.getter | 0 |
| PhaseHistory.swift | closure #3 in static PhaseAdvice.recommend(history:maintenanceSince:bodyFatPercent:today:brief:) | 0 |
| Plan.swift | WeekendStyle.id.getter | 0 |
| Plan.swift | WeekendStyle.title.getter | 0 |
| Plan.swift | WeekendStyle.subtitle.getter | 0 |
| Plan.swift | Plan.currentWeek.getter | 0 |
| Plan.swift | implicit closure #1 in Plan.currentWeek.getter | 0 |
| Plan.swift | Plan.weeksRemaining.getter | 0 |
| Plan.swift | implicit closure #1 in Plan.init(from:) | 0 |
| Plan.swift | implicit closure #2 in Plan.init(from:) | 0 |
| Plan.swift | implicit closure #3 in Plan.init(from:) | 0 |
| Plan.swift | implicit closure #4 in Plan.init(from:) | 0 |
| Plan.swift | implicit closure #1 in Plan.endDate.getter | 0 |
| Plan.swift | implicit closure #1 in Plan.startDate(ofPhaseAt:) | 0 |
| Plan.swift | implicit closure #1 in Plan.phaseIndex(on:) | 0 |
| Plan.swift | Plan.currentPhase.getter | 0 |
| Plan.swift | implicit closure #1 in Plan.currentPhase.getter | 0 |
| Plan.swift | implicit closure #1 in Plan.projectedWeight(on:) | 0 |
| Plan.swift | Plan.dailyCalorieDelta.getter | 0 |
| Plan.swift | implicit closure #1 in Plan.dailyCalorieDelta(on:) | 0 |
| Plan.swift | implicit closure #2 in Plan.dailyCalorieDelta(on:) | 0 |
| Plan.swift | implicit closure #1 in Plan.isSettling(on:) | 0 |
| Plan.swift | implicit closure #2 in Plan.isSettling(on:) | 0 |
| Plan.swift | implicit closure #1 in static Plan.weekStart(for:) | 0 |
| Plan.swift | Plan.progress.getter | 0 |
| Plan.swift | Plan.daysRemaining.getter | 0 |
| Plan.swift | implicit closure #1 in Plan.daysRemaining.getter | 0 |
| Plan.swift | implicit closure #1 in Plan.rescheduled(toEnd:) | 0 |
| Plan.swift | closure #1 in Plan.rescheduled(toEnd:) | 0 |
| Plan.swift | implicit closure #1 in Plan.dietBreakStartWeek(from:) | 0 |
| Plan.swift | implicit closure #1 in Plan.startDate(ofWeek:) | 0 |
| Plan.swift | implicit closure #1 in Plan.cutWeeksElapsed(inPhaseWithID:on:) | 0 |
| Plan.swift | Plan.nextDietBreakStart(after:) | 0 |
| Plan.swift | Plan.firstNonBreakDay(from:) | 0 |
| Plan.swift | implicit closure #1 in Plan.firstNonBreakDay(from:) | 0 |
| PlanOutcome.swift | implicit closure #1 in CompositionChange.days.getter | 0 |
| PlanOutcome.swift | PhaseCompositionVerdict.title.getter | 0 |
| PlanOutcome.swift | PhaseCompositionVerdict.icon.getter | 0 |
| PlanOutcome.swift | CompositionVerdict.title.getter | 0 |
| PlanOutcome.swift | CompositionVerdict.explanation.getter | 0 |
| PlanOutcome.swift | AdherenceDataGap.progress.getter | 0 |
| PlanOutcome.swift | PlanAdherence.projectedEndRange(from:) | 0 |
| PlanOutcome.swift | closure #1 in PlanAdherence.projectedEndRange(from:) | 0 |
| PlanOutcome.swift | PlanAdherence.rateIsIndistinguishableFromZero.getter | 0 |
| PlanOutcome.swift | PlanAdherence.deviationKg.getter | 0 |
| PlanOutcome.swift | Achievement.id.getter | 0 |
| PlanOutcome.swift | Achievement.isUnlocked.getter | 0 |
| PlanOutcome.swift | Achievement.progress.getter | 0 |
| PlanOutcome.swift | Achievement.title.getter | 0 |
| PlanOutcome.swift | Achievement.requirement.getter | 0 |
| PlanOutcome.swift | Achievement.icon.getter | 0 |
| PurchaseService.swift | implicit closure #1 in variable initialization expression of logger | 0 |
| PurchaseService.swift | PurchaseService.bundleProducts.getter | 0 |
| PurchaseService.swift | closure #1 in PurchaseService.bundleProducts.getter | 0 |
| PurchaseService.swift | closure #2 in PurchaseService.bundleProducts.getter | 0 |
| PurchaseService.swift | closure #1 in PurchaseService.subscriptions.getter | 0 |
| PurchaseService.swift | implicit closure #1 in closure #1 in PurchaseService.subscriptions.getter | 0 |
| PurchaseService.swift | closure #2 in PurchaseService.subscriptions.getter | 0 |
| PurchaseService.swift | PurchaseService.lifetime.getter | 0 |
| PurchaseService.swift | closure #1 in PurchaseService.lifetime.getter | 0 |
| PurchaseService.swift | implicit closure #1 in PurchaseService.load() | 0 |
| PurchaseService.swift | PurchaseService.purchase(_:) | 0 |
| PurchaseService.swift | implicit closure #1 in PurchaseService.purchase(_:) | 0 |
| PurchaseService.swift | PurchaseService.restore() | 0 |
| PurchaseService.swift | implicit closure #1 in PurchaseService.restore() | 0 |
| PurchaseService.swift | PurchaseService.handle(_:) | 0 |
| RecipeHint.swift | RecipeHint.Match.id.getter | 0 |
| RecipeHint.swift | static RecipeHint.Match.== infix(_:_:) | 0 |
| RecipeHint.swift | implicit closure #1 in static RecipeHint.Match.== infix(_:_:) | 0 |
| ReminderStore.swift | implicit closure #1 in static ReminderStore.loadTime(from:key:hour:minute:) | 0 |
| ReminderStore.swift | ReminderStore.enableNotifications() | 0 |
| SleepAnalysis.swift | variable initialization expression of SleepNight.fromBedOnly | 0 |
| StallReport.swift | variable initialization expression of StallReport.Input.days | 0 |
| StallReport.swift | variable initialization expression of StallReport.Input.plannedWeeklyRateKg | 0 |
| StallReport.swift | variable initialization expression of StallReport.Input.loggedDays | 0 |
| StallReport.swift | variable initialization expression of StallReport.Input.weighIns | 0 |
| StallReport.swift | implicit closure #1 in static StallReport.make(_:) | 0 |
| StepStore.swift | implicit closure #2 in StepStore.init(defaults:groupDefaults:) | 0 |
| StepStore.swift | StepStore.requestAuthorization() | 0 |
| StepStore.swift | closure #1 in StepStore.requestAuthorization() | 0 |
| StepStore.swift | closure #1 in closure #1 in StepStore.requestAuthorization() | 0 |
| StepStore.swift | StepStore.setupObserver() | 0 |
| StepStore.swift | closure #1 in StepStore.setupObserver() | 0 |
| StepStore.swift | closure #1 in closure #1 in StepStore.setupObserver() | 0 |
| StepStore.swift | closure #2 in StepStore.setupObserver() | 0 |
| StepStore.swift | closure #2 in StepStore.updateDerivedStats() | 0 |
| StepStore.swift | closure #3 in StepStore.updateDerivedStats() | 0 |
| StepStore.swift | implicit closure #1 in StepStore.updateGoalStreak() | 0 |
| StepStore.swift | closure #1 in StepStore.samplePredicate(from:to:) | 0 |
| StepStore.swift | implicit closure #1 in static StepStore.best(_:in:) | 0 |
| StepStore.swift | closure #1 in static StepStore.best(_:in:) | 0 |
| StepStore.swift | implicit closure #2 in static StepStore.best(_:in:) | 0 |
| StepStore.swift | closure #1 in closure #1 in StepStore.fetchSources() | 0 |
| StepStore.swift | closure #1 in closure #2 in closure #1 in StepStore.fetchSources() | 0 |
| StepStore.swift | closure #2 in closure #2 in closure #1 in StepStore.fetchSources() | 0 |
| StepStore.swift | closure #1 in closure #1 in StepStore.fetchActiveCaloriesHistory(days:) | 0 |
| StepStore.swift | closure #2 in closure #1 in StepStore.fetchActiveCaloriesHistory(days:) | 0 |
| StepStore.swift | implicit closure #2 in closure #1 in StepStore.fetchWorkouts(days:) | 0 |
| StepStore.swift | implicit closure #3 in closure #1 in StepStore.fetchWorkouts(days:) | 0 |
| StepStore.swift | closure #1 in closure #1 in StepStore.fetchWorkouts(days:) | 0 |
| StepStore.swift | closure #2 in closure #1 in StepStore.fetchWorkouts(days:) | 0 |
| StepStore.swift | implicit closure #1 in static StepStore.widgetAccent(defaults:) | 0 |
| StepStore.swift | implicit closure #3 in static StepStore.widgetAccent(defaults:) | 0 |
| StepStore.swift | closure #1 in closure #1 in StepStore.fetchSleep(days:) | 0 |
| StepStore.swift | closure #2 in closure #1 in StepStore.fetchSleep(days:) | 0 |
| StepStore.swift | closure #3 in closure #1 in StepStore.fetchSleep(days:) | 0 |
| StepStore.swift | closure #4 in closure #1 in StepStore.fetchSleep(days:) | 0 |
| StepStore.swift | closure #5 in closure #1 in StepStore.fetchSleep(days:) | 0 |
| StepStore.swift | closure #6 in closure #1 in StepStore.fetchSleep(days:) | 0 |
| StepStore.swift | closure #1 in closure #1 in StepStore.fetchRestingPulse(days:) | 0 |
| StepStore.swift | closure #2 in closure #1 in StepStore.fetchRestingPulse(days:) | 0 |
| StepStore.swift | closure #1 in closure #2 in closure #1 in StepStore.fetchRestingPulse(days:) | 0 |
| StepStore.swift | StepStore.sleep(on:) | 0 |
| StepStore.swift | closure #1 in StepStore.sleep(on:) | 0 |
| StepStore.swift | implicit closure #1 in StepStore.sleep(on:) | 0 |
| StepStore.swift | static StepStore.title(of:) | 0 |
| StepStore.swift | closure #1 in closure #1 in StepStore.fetchHistory(days:) | 0 |
| UserProfile.swift | implicit closure #1 in UserProfile.age.getter | 0 |
| UserProfile.swift | UserProfile.proteinBasis.setter | 0 |
| UserProfile.swift | UserProfile.proteinPerLeanKg.setter | 0 |
| UserProfile.swift | implicit closure #1 in static UserProfile.birthDateRange(now:) | 0 |
| UserProfile.swift | implicit closure #2 in static UserProfile.birthDateRange(now:) | 0 |
| UserProfile.swift | implicit closure #1 in static UserProfile.birthDateGuess(forAge:now:) | 0 |
| UsualMeal.swift | UsualMeal.Suggestion.macros.getter | 0 |
| UsualMeal.swift | closure #1 in UsualMeal.Suggestion.macros.getter | 0 |
| UsualMeal.swift | UsualMeal.Suggestion.id.getter | 0 |
| UsualMeal.swift | implicit closure #1 in UsualMeal.Suggestion.id.getter | 0 |
| WeightTrendFit.swift | WeightTrendFit.range.getter | 0 |