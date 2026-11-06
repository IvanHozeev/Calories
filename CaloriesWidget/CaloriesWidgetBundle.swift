import WidgetKit
import SwiftUI

@main
struct CaloriesWidgetBundle: WidgetBundle {
    var body: some Widget {
        CaloriesWidget()
        MacrosWidget()
        StepsWidget()
        MealWidget()
        KosherWaitLiveActivity()
        // Контролы появились в iOS 18, а минимальная версия приложения — 26,
        // поэтому проверка доступности здесь не нужна.
        QuickAddControl()
        PhotographFoodControl()
        ScanBarcodeControl()
        TakeMeasurementsControl()
        MealControl()
    }
}
