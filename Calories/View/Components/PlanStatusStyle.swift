import SwiftUI

/// Оформление статуса плана — одно на все экраны (карточка в профиле и секция «Как идёт план»).
extension PlanStatus {
    var title: String {
        switch self {
        case .insufficientData: return String(localized: "Собираем данные")
        case .onTrack: return String(localized: "Идёшь по графику")
        case .ahead: return String(localized: "Опережаешь график")
        case .behind: return String(localized: "Отстаёшь от графика")
        }
    }

    var icon: String {
        switch self {
        case .insufficientData: return "clock"
        case .onTrack: return "checkmark.circle.fill"
        case .ahead: return "arrow.up.circle.fill"
        case .behind: return "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .insufficientData: return .secondary
        case .onTrack: return .green
        case .ahead: return .blue
        case .behind: return .orange
        }
    }
}
