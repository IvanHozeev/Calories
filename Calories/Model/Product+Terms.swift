import Foundation
import StoreKit

/// Что и когда спишут — одними словами на финише онбординга и в пэйволе.
///
/// App Review требует, чтобы рядом с кнопкой было видно, сколько и за какой
/// срок человек заплатит после пробного периода. «Потом по тарифу» сумму не
/// называло; здесь — цена и срок выбранного тарифа.
extension Product {

    /// Бесплатный пробный период, который этому человеку ещё положен.
    ///
    /// Пробный период App Store даёт один раз на группу подписок и Apple ID:
    /// кто уже брал месяц, тому обещать его снова нельзя — App Store спишет
    /// полную цену сразу.
    func freeTrial(eligible: Bool) -> Product.SubscriptionPeriod? {
        guard eligible, let offer = subscription?.introductoryOffer,
              offer.paymentMode == .freeTrial else { return nil }
        return offer.period
    }

    /// Строка мелким под кнопкой покупки.
    func termsText(introEligible: Bool) -> String {
        guard let subscription else {
            return String(format: String(localized: "%@ один раз, без подписки."), displayPrice)
        }
        let price = Self.pricePerPeriod(displayPrice, subscription.subscriptionPeriod)
        if let trial = freeTrial(eligible: introEligible) {
            return String(format: String(localized: "Пробный период — %1$@, потом %2$@. Отменить можно в любой момент."),
                          Self.duration(trial), price)
        }
        return String(format: String(localized: "%@. Отменить можно в любой момент."), price)
    }

    /// Надпись на кнопке: «Попробовать месяц бесплатно», а без пробного —
    /// «Начать программу».
    ///
    /// Срок не подставляется числом: «Попробовать 1 неделя» не склоняется, а
    /// склонять под каждый язык ради одной кнопки незачем. Месяц — то, что
    /// мы и обещаем; любой другой срок назван в строке под кнопкой.
    func purchaseTitle(introEligible: Bool) -> String {
        guard let trial = freeTrial(eligible: introEligible) else {
            return String(localized: "Начать программу")
        }
        if trial.unit == .month, trial.value == 1 {
            return String(localized: "Попробовать месяц бесплатно")
        }
        return String(localized: "Попробовать бесплатно")
    }

    static func pricePerPeriod(_ price: String, _ period: Product.SubscriptionPeriod) -> String {
        switch period.unit {
        case .year: return String(format: String(localized: "%@ в год"), price)
        case .month: return String(format: String(localized: "%@ в месяц"), price)
        case .week: return String(format: String(localized: "%@ в неделю"), price)
        default: return price
        }
    }

    /// «1 месяц», «1 неделя» — словами системы, на языке интерфейса.
    static func duration(_ period: Product.SubscriptionPeriod) -> String {
        var parts = DateComponents()
        switch period.unit {
        case .day: parts.day = period.value
        case .week: parts.weekOfMonth = period.value
        case .month: parts.month = period.value
        case .year: parts.year = period.value
        @unknown default: parts.day = period.value
        }
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = [.day, .weekOfMonth, .month, .year]
        return formatter.string(from: parts) ?? ""
    }
}
