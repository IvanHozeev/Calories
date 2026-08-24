import SwiftUI
import StoreKit

/// С какой фичи пользователь пришёл в пейволл. Абстрактная «Подписка» продаёт хуже,
/// чем конкретный ответ на вопрос, который человек задавал секунду назад.
enum PaywallFocus {
    case general
    case plan

    var headline: String {
        switch self {
        case .general: return String(localized: "Premium")
        case .plan: return String(localized: "Персональный план")
        }
    }

    var subtitle: String? {
        switch self {
        case .general: return nil
        case .plan: return String(localized: "Персональный план калорийности под твои цели")
        }
    }
}

struct PaywallView: View {
    var store: CalorieStore
    var focus: PaywallFocus = .general

    @Environment(PurchaseService.self) private var purchases
    @Environment(\.dismiss) private var dismiss

    @State private var selectedID: String?
    @State private var isPurchasing = false

    private var selectedProduct: Product? {
        purchases.products.first { $0.id == selectedID }
            ?? purchases.subscriptions.first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    header
                    features

                    if purchases.isPremium {
                        activeState
                    } else if purchases.isLoading {
                        ProgressView()
                            .padding(.vertical, 40)
                    } else if purchases.loadFailed {
                        failedState
                    } else {
                        offers
                    }
                }
                .padding(.bottom, 24)
            }
            .navigationTitle("Подписка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Восстановить") {
                        Task { await purchases.restore() }
                    }
                    .font(.footnote)
                }
            }
            .task {
                if purchases.products.isEmpty { await purchases.load() }
                selectedID = purchases.subscriptions.last?.id
            }
            .alert("Не удалось", isPresented: Binding(
                get: { purchases.purchaseError != nil },
                set: { if !$0 { purchases.purchaseError = nil } }
            )) {
                Button("OK", role: .cancel) { purchases.purchaseError = nil }
            } message: {
                Text(purchases.purchaseError ?? "")
            }
        }
    }

    // MARK: - Части экрана

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 52))
                .foregroundStyle(.yellow)
                .padding(.top, 20)

            Text(focus.headline)
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)

            if let subtitle = focus.subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }
        }
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: 14) {
            featureRow("Персональный план: срок в неделях, целевой вес, точная дневная норма калорий")
            featureRow("Автоматический пересчёт темпа и предупреждение, если он слишком агрессивный")
            featureRow("Прогресс плана прямо на главном экране")
        }
        .padding(.horizontal, 28)
    }

    private var activeState: some View {
        VStack(spacing: 10) {
            Label("Premium активен", systemImage: "checkmark.seal.fill")
                .font(.headline)
                .foregroundStyle(.green)
            Button("Готово") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding(.top, 12)
    }

    private var failedState: some View {
        VStack(spacing: 10) {
            Label("Не удалось загрузить предложения", systemImage: "wifi.slash")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Повторить") {
                Task { await purchases.load() }
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 24)
    }

    private var offers: some View {
        VStack(spacing: 12) {
            ForEach(purchases.subscriptions) { product in
                offerCard(product)
            }

            if let lifetime = purchases.lifetime {
                offerCard(lifetime)
            }

            Button {
                guard let product = selectedProduct else { return }
                isPurchasing = true
                Task {
                    await purchases.purchase(product)
                    isPurchasing = false
                    if purchases.isPremium { dismiss() }
                }
            } label: {
                Group {
                    if isPurchasing {
                        ProgressView()
                    } else {
                        Text("Оформить Premium")
                            .font(.body.weight(.semibold))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedProduct == nil || isPurchasing)
            .padding(.top, 6)

            if let intro = introText(for: selectedProduct) {
                Text(intro)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private func offerCard(_ product: Product) -> some View {
        let isSelected = product.id == selectedID
        return Button {
            selectedID = product.id
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(product.displayName)
                        .font(.subheadline.weight(.semibold))
                    if let period = periodText(for: product) {
                        Text(period)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Text(product.displayPrice)
                    .font(.headline)
                    .monospacedDigit()
            }
            .padding(14)
            .glassCard()
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private func periodText(for product: Product) -> String? {
        guard let period = product.subscription?.subscriptionPeriod else {
            return String(localized: "Разовая покупка, без продления")
        }
        switch period.unit {
        case .month: return String(localized: "Списывается каждый месяц")
        case .year:  return String(localized: "Списывается раз в год")
        case .week:  return String(localized: "Списывается каждую неделю")
        default:     return nil
        }
    }

    private func introText(for product: Product?) -> String? {
        guard let offer = product?.subscription?.introductoryOffer,
              offer.paymentMode == .freeTrial else { return nil }
        return String(localized: "Первая неделя бесплатно, потом по тарифу. Отменить можно в любой момент.")
    }

    private func featureRow(_ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(text)
            Spacer()
        }
    }
}
