import SwiftUI
import SwiftData
import OSLog

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Calories", category: "App")

@main
struct CalorieCounterApp: App {
    private let container: ModelContainer?
    private let storageError: String?
    @State private var store: CalorieStore?
    @State private var stepStore = StepStore()
    @State private var purchases = PurchaseService()

    /// Сбой хранилища раньше был fatalError. Синхронизации нет, а резервная копия делается
    /// вручную из настроек — то есть повреждённая база означала разом и неработающее
    /// приложение, и невозможность добраться до своих данных. Теперь показываем экран
    /// с объяснением вместо падения.
    init() {
        do {
            let container = try ModelContainer(
                for: FoodEntry.self, FoodItem.self, WeightEntry.self, GoalRecord.self, Dish.self,
                BodyMeasurement.self
            )
            self.container = container
            self.storageError = nil
            _store = State(initialValue: CalorieStore(context: container.mainContext))
        } catch {
            logger.error("Хранилище не открылось: \(error.localizedDescription)")
            self.container = nil
            self.storageError = error.localizedDescription
            _store = State(initialValue: nil)
        }
    }

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
            if let store, let container {
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
                StorageErrorView(message: storageError ?? "")
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
