import OSLog
import SwiftUI
import UIKit

/// Пункты меню по долгому нажатию на иконку приложения.
///
/// Сюда попало только то, с чего начинают запись: человек уже стоит с телефоном
/// над тарелкой или на весах, и лишний заход через экран «Сегодня» — это две
/// потерянные секунды ровно в тот момент, когда их нет.
enum QuickAction: String, CaseIterable, Identifiable {
    case meal
    case camera
    case scanner
    case weight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .meal:    String(localized: "Приём пищи")
        case .camera:  String(localized: "Снять еду")
        case .scanner: String(localized: "Сканировать штрихкод")
        case .weight:  String(localized: "Взвеситься")
        }
    }

    var symbol: String {
        switch self {
        case .meal:    "fork.knife"
        case .camera:  "camera.fill"
        case .scanner: "barcode.viewfinder"
        case .weight:  "scalemass"
        }
    }

    var shortcutItem: UIApplicationShortcutItem {
        UIApplicationShortcutItem(
            type: rawValue,
            localizedTitle: title,
            localizedSubtitle: nil,
            icon: UIApplicationShortcutIcon(systemImageName: symbol)
        )
    }
}

/// Держит нажатый пункт до момента, когда интерфейс готов его отработать.
///
/// При запуске с нуля действие приходит раньше, чем собран стор и построено дерево
/// экранов, поэтому его нельзя выполнять на месте — только положить сюда и забрать,
/// когда покажется корень.
@MainActor
@Observable
final class QuickActionRouter {
    static let shared = QuickActionRouter()

    var pending: QuickAction?

    private init() {}

    /// Забирает намерение, оставленное контролом из Пункта управления.
    ///
    /// Расширение и приложение — разные процессы, позвать экран напрямую оттуда
    /// нельзя, поэтому контрол кладёт намерение в общий контейнер. Стираем сразу
    /// после чтения: иначе один нажатый контрол открывал бы камеру при каждом
    /// следующем запуске.
    @discardableResult
    func takePendingFromControl() -> Bool {
        let defaults = UserDefaults(suiteName: CalorieStore.appGroup)
        let raw = defaults?.string(forKey: Self.controlActionKey)
        Logger(subsystem: "ivankhozeyev.team.Calories", category: "control")
            .notice("приложение читает намерение контрола: \(raw ?? "пусто")")
        guard let raw, let action = QuickAction(rawValue: raw) else { return false }
        defaults?.removeObject(forKey: Self.controlActionKey)
        pending = action
        return true
    }

    /// Тот же ключ, что в расширении. Он там продублирован строкой: файлы
    /// приложения в таргет виджета не входят, а тащить их туда ради одной
    /// константы дороже, чем держать её в двух местах.
    static let controlActionKey = "pending_quick_action"

    @discardableResult
    func handle(_ item: UIApplicationShortcutItem) -> Bool {
        guard let action = QuickAction(rawValue: item.type) else { return false }
        pending = action
        return true
    }

    /// Меню собирается в коде, а не в Info.plist, по двум причинам. Камера ходит в
    /// Gemini и есть не у всех — статический пункт открывал бы пустоту. И заголовки
    /// так берутся из общего файла переводов, а не из отдельного InfoPlist.xcstrings.
    func refreshShortcutItems() {
        let available = QuickAction.allCases.filter { action in
            action != .camera || GeminiVisionService.isConfigured
        }
        UIApplication.shared.shortcutItems = available.map(\.shortcutItem)
    }
}

/// SwiftUI не отдаёт нажатие на иконку сам: за холодный старт отвечает
/// `willConnectTo`, за нажатие на уже запущенном приложении — `performActionFor`.
/// Окно по-прежнему делает SwiftUI, делегат сцены только ловит эти два вызова.
final class QuickActionSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let item = connectionOptions.shortcutItem else { return }
        // Синхронно: дерево экранов строится следом, и хоп на следующий такт
        // успевает разминуться с ним — действие тогда просто теряется.
        MainActor.assumeIsolated { _ = QuickActionRouter.shared.handle(item) }
    }

    func windowScene(_ windowScene: UIWindowScene,
                     performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        MainActor.assumeIsolated {
            completionHandler(QuickActionRouter.shared.handle(shortcutItem))
        }
    }
}

final class QuickActionAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = QuickActionSceneDelegate.self
        return configuration
    }
}
