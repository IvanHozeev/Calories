import SwiftUI
import SwiftData
import OSLog

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Calories", category: "App")

@main
struct CalorieCounterApp: App {
    @UIApplicationDelegateAdaptor(QuickActionAppDelegate.self) private var appDelegate
    // Контейнер и стор живут в SharedStore: до них должны дотягиваться не только
    // экраны, но и команды Сири, которые выполняются в этом же процессе без сцены.
    private let shared = SharedStore.shared
    @State private var stepStore = StepStore()
    @State private var purchases = PurchaseService()

    /// StoreKit может выдать премиум, но не отобрать.
    ///
    /// Первая версия просто присваивала `store.isPremium = purchases.isPremium`, и это
    /// отбирало доступ у всех, у кого StoreKit не ответил: нет сети, не подхватилась
    /// конфигурация, покупка ещё не восстановлена. Отзыв прав вернём, когда продукты
    /// будут приходить из App Store Connect и пустой ответ можно будет считать
    /// достоверным «не куплено».
    private func applyEntitlements(store: CalorieStore) {
        if purchases.isPremium {
            store.isPremium = true
        }
    }

    var body: some Scene {
        WindowGroup {
            if let store = shared.store, let container = shared.container {
                RootView(store: store, stepStore: stepStore, purchases: purchases)
                    .task {
                        await purchases.load()
                        applyEntitlements(store: store)
                    }
                    .onChange(of: purchases.isPremium) { _, _ in
                        applyEntitlements(store: store)
                    }
                    .modelContainer(container)
            } else {
                StorageErrorView(message: shared.storageError ?? "")
            }
        }
    }
}

/// Показывается вместо приложения, когда база данных не открылась.
private struct StorageErrorView: View {
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 56))
                .foregroundStyle(.orange)
            Text("Не удалось открыть данные")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
            Text("Записи не потеряны, но приложение не смогло их прочитать. Попробуй перезапустить устройство. Не переустанавливай приложение — это сотрёт дневник.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if !message.isEmpty {
                Text(verbatim: message)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
            }
        }
        .padding(32)
    }
}
