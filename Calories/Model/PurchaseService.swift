import Foundation
import StoreKit
import Observation
import OSLog

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Calories", category: "Purchases")

/// Покупки на StoreKit 2. Источник истины о премиуме — текущие права
/// (`Transaction.currentEntitlements`), а не флаг в UserDefaults: флаг остаётся
/// только кэшем, чтобы на старте не мигал платный контент до ответа StoreKit.
///
/// Пока работает против локального `Products.storekit` — платный аккаунт разработчика
/// для этого не нужен. Когда продукты появятся в App Store Connect, поменяются только
/// идентификаторы: остальной код и так ходит в настоящий StoreKit.
@Observable
@MainActor
final class PurchaseService {

    enum ProductID {
        static let monthly = "ivankhozeyev.team.Calories.premium.monthly"
        static let yearly = "ivankhozeyev.team.Calories.premium.yearly"
        static let lifetime = "ivankhozeyev.team.Calories.premium.lifetime"
        /// Пара приложений одной покупкой. Открывает и GymLogger — он читает
        /// флаг из общей папки, так же как мы читаем его.
        static let bundleYearly = "ivankhozeyev.team.Calories.premium.bundle.yearly"
        static let bundleLifetime = "ivankhozeyev.team.Calories.premium.bundle.lifetime"

        static let bundles: Set<String> = [bundleYearly, bundleLifetime]

        static let all: [String] = [monthly, yearly, lifetime, bundleYearly, bundleLifetime]
    }

    private(set) var products: [Product] = []
    private(set) var purchasedIDs: Set<String> = []
    private(set) var isLoading = false
    private(set) var loadFailed = false
    var purchaseError: String?

    var isPremium: Bool { !purchasedIDs.isEmpty }

    /// Куплена пара приложений, а не один Calories.
    var hasBundle: Bool { !purchasedIDs.isDisjoint(with: ProductID.bundles) }

    /// Тарифы на пару — отдельно: в пейволе они стоят своим блоком, иначе
    /// читаются как ещё два непонятных тира Calories.
    var bundleProducts: [Product] {
        products.filter { ProductID.bundles.contains($0.id) }
            .sorted { $0.price < $1.price }
    }

    /// Подписки отдельно от разовой покупки — в интерфейсе они подаются по-разному.
    var subscriptions: [Product] {
        products.filter { $0.type == .autoRenewable && !ProductID.bundles.contains($0.id) }
            .sorted { $0.price < $1.price }
    }

    var lifetime: Product? {
        products.first { $0.id == ProductID.lifetime }
    }

    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    init() {
        // Слушать обновления надо с самого запуска: покупка может завершиться вне приложения
        // (Family Sharing, подтверждение «Ask to Buy», возврат средств).
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else { return }
                await self.handle(update)
            }
        }
    }

    deinit { updatesTask?.cancel() }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            products = try await Product.products(for: ProductID.all)
            loadFailed = products.isEmpty
        } catch {
            logger.error("Не удалось загрузить продукты: \(error.localizedDescription)")
            loadFailed = true
        }
        await refreshEntitlements()
    }

    /// Пересобирает права с нуля, а не добавляет: подписка может истечь или быть возвращена.
    func refreshEntitlements() async {
        var active: Set<String> = []
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.revocationDate == nil {
                active.insert(transaction.productID)
            }
        }
        purchasedIDs = active
        publishBundle()
    }

    /// Сказать соседу, что пара куплена здесь.
    ///
    /// Правило у обоих приложений одинаковое и держится на одном условии: в
    /// общую папку уходит только собственная покупка. Подаренное соседом
    /// право мы туда не пишем — иначе бандл открывал бы сам себя по кругу, и
    /// никто уже не сказал бы, за что человек заплатил.
    ///
    /// Пишем на каждом пересчёте прав, а не один раз при покупке: подписку
    /// возвращают и она истекает, и тогда флаг надо снять, а не оставить
    /// навсегда.
    private func publishBundle() {
        UserDefaults(suiteName: CalorieStore.appGroup)?
            .set(hasBundle, forKey: "shared_is_bundle")
    }

    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                await handle(verification)
                return isPremium
            case .userCancelled:
                return false
            case .pending:
                // «Ask to Buy» и подобное — покупка досогласуется позже, придёт в Transaction.updates.
                return false
            @unknown default:
                return false
            }
        } catch {
            logger.error("Покупка не прошла: \(error.localizedDescription)")
            purchaseError = error.localizedDescription
            return false
        }
    }

    func restore() async {
        do {
            try await AppStore.sync()
        } catch {
            logger.error("Восстановление не прошло: \(error.localizedDescription)")
            purchaseError = error.localizedDescription
        }
        await refreshEntitlements()
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result else {
            // Неподписанную транзакцию не засчитываем и не завершаем — пусть StoreKit повторит.
            logger.warning("Транзакция не прошла проверку подписи")
            return
        }
        await transaction.finish()
        await refreshEntitlements()
    }
}
