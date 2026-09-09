import WidgetKit
import SwiftUI

@main
struct CaloriesWidgetBundle: WidgetBundle {
    var body: some Widget {
        CaloriesWidget()
        MacrosWidget()
        StepsWidget()
        // Контролы появились в iOS 18, а приложение живёт с 17.6.
        if #available(iOS 18.0, *) {
            QuickAddControl()
            PhotographFoodControl()
            ScanBarcodeControl()
            TakeMeasurementsControl()
        }
    }
}
