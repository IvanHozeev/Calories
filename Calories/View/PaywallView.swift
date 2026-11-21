import SwiftUI
import StoreKit

/// С какой фичи пользователь пришёл в пейволл. Абстрактная «Подписка» продаёт хуже,
/// чем конкретный ответ на вопрос, который человек задавал секунду назад.
///
/// Продаём не функции, а результат: сбросить вес и не вернуть его. Функции —
/// это «как»; человек платит за «зачем», и за то, что видит путь к нему.
enum PaywallFocus {
    case general
    case plan
    /// Пробный месяц уже был, а подписки нет: отменили в пробном периоде или
    /// она истекла. Разговор не про «попробуй», а про то, что закрылось.
    case trialEnded

    /// Заголовок и подзаголовок — от предложения, собранного по ответам
    /// онбординга; у конца доступа — свои.
    func headline(_ offer: Offer) -> String {
        switch self {
        case .general, .plan: return offer.headline
        case .trialEnded: return String(localized: "Доступ к программе закончился")
        }
    }

    func subtitle(_ offer: Offer) -> String {
        switch self {
        case .general, .plan: return offer.subtitle
        case .trialEnded: return String(localized: "Норма снова считается по формуле. Довести маршрут до финиша и удержать результат — с Premium.")
        }
    }
}

struct PaywallView: View {
    var store: CalorieStore
    var focus: PaywallFocus = .general
    /// Предложение, собранное снаружи, — с финиша онбординга, где ответы ещё
    /// не сохранены.
    var presetOffer: Offer? = nil

    @Environment(PurchaseService.self) private var purchases
    @Environment(\.dismiss) private var dismiss

    @State private var selectedID: String?
    @State private var isPurchasing = false

    /// Пробный месяц уже взят, а подписки нет — говорим об этом, откуда бы ни
    /// открыли пэйвол. Открытому бандлом про конец доступа говорить нечего:
    /// доступ у него есть, и такой заголовок звучал бы как потеря.
    private var shownFocus: PaywallFocus {
        !purchases.introEligible && !purchases.isPremium && !unlockedByBundle ? .trialEnded : focus
    }

    /// Открыто бандлом: своей покупки нет, но пара приложений куплена в
    /// GymLogger. Показывать цены здесь нельзя — человек уже заплатил, и
    /// тарифы читаются как требование заплатить снова.
    private var unlockedByBundle: Bool { store.bundleUnlocked && !purchases.isPremium }

    /// То же предложение, что на финише онбординга: о той боли, о которой
    /// человек сказал в начале. Цель — по плану (первая фаза, что двигает вес,
    /// а не удержание, на котором человек может стоять сейчас), без плана — по
    /// профилю.
    private var offer: Offer {
        if let presetOffer { return presetOffer }
        let intent: PlanIntent?
        if let moving = store.plan?.phases.first(where: { $0.intent != .maintenance }) {
            intent = moving.intent
        } else {
            switch store.profile?.goal {
            case .fatLoss: intent = .cut
            case .muscleGain: intent = .bulk
            case .maintenance: intent = store.plan == nil ? .maintenance : .cut
            case nil: intent = nil
            }
        }
        return Offer.make(intent: intent, answers: OfferAnswers.load(),
                          observesTradition: KosherSettings.shared.isEnabled)
    }

    private var selectedProduct: Product? {
        purchases.products.first { $0.id == selectedID }
            ?? purchases.featured
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header
                features

                if purchases.isPremium {
                    activeState
                } else if unlockedByBundle {
                    bundleState
                } else if purchases.isLoading {
                    ProgressView().padding(.vertical, 40)
                } else if purchases.loadFailed {
                    failedState
                } else {
                    offers
                }
            }
            .padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
        .screenTitle(String(localized: "Подписка"))
        // Кнопка покупки — у нижней кромки, а не в конце прокрутки.
        //
        // Она лежала последней в списке, и на экране с четырьмя фичами и тремя
        // тарифами до неё надо было доскроллить: человек соглашался купить и
        // искал, чем. Теперь она на месте, где палец её и ждёт.
        .safeAreaBar(edge: .bottom) {
            if !purchases.isPremium, !unlockedByBundle, !purchases.isLoading, !purchases.loadFailed {
                purchaseBar
            }
        }
        .task {
            if purchases.products.isEmpty { await purchases.load() }
            selectedID = purchases.featured?.id
        }
        .alert("Не удалось оформить подписку", isPresented: Binding(
            get: { purchases.purchaseError != nil },
            set: { if !$0 { purchases.purchaseError = nil } }
        )) {
            Button("Понятно", role: .cancel) { purchases.purchaseError = nil }
        } message: {
            Text(purchases.purchaseError ?? "")
        }
    }

    // MARK: - Части экрана

    private var header: some View {
        VStack(spacing: 14) {
            // Знак приложения, а не универсальные искры: искрами помечают
            // платное в любом приложении магазина, и шапка не говорила, чьё
            // это Premium. Кольцо в режиме нормы — полные дуги — то же, что
            // человек видит на «Сегодня» каждый день.
            ProgressRing(consumed: 0, goal: 1, showsTargets: true, miniature: 96, onOpen: {})
                .padding(.top, 8)
                .accessibilityHidden(true)

            Text(shownFocus.headline(offer))
                .font(.app(.title, weight: .bold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Text(shownFocus.subtitle(offer))
                .font(.app(.subheadline))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            if let route {
                Text(verbatim: route)
                    .font(.app(.subheadline, weight: .semibold))
                    .foregroundStyle(ProgressRing.kcalColors[0])
                    .monospacedDigit()
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(ProgressRing.kcalColors[0].opacity(0.14), in: Capsule())
                    .padding(.horizontal, 24)
                    .accessibilityIdentifier("paywallRoute")
            }
        }
    }

    /// Свой маршрут одной строкой, если план уже есть: «80.2 → 75.7 кг к
    /// 13 марта». Предложение с твоими цифрами читается как обещание, а не
    /// как реклама. Когда вес по плану не меняется, двигаться некуда — строки нет.
    private var route: String? {
        guard let plan = store.plan,
              abs(plan.targetWeightKg - plan.startWeightKg) >= 0.5 else { return nil }
        return String(format: String(localized: "Твой маршрут: %1$@ → %2$@ кг к %3$@"),
                      String(format: "%.1f", plan.startWeightKg),
                      String(format: "%.1f", plan.targetWeightKg),
                      PlanView.planDate(plan.targetReachedDate))
    }

    /// Что получаешь — результатами, а не функциями, с одной строкой о том,
    /// за счёт чего. Порядок — от боли человека: первой та, ради которой он
    /// пришёл.
    private var features: some View {
        VStack(spacing: 18) {
            ForEach(offer.benefits, id: \.kind) { benefit in
                featureRow(benefit.icon, benefit.title, benefit.detail)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tileSurface(cornerRadius: 20)
        .padding(.horizontal, 20)
    }

    /// То же место, где обычно тарифы, но вместо них — откуда взялся доступ.
    private var bundleState: some View {
        VStack(spacing: 10) {
            Label("Открыто бандлом", systemImage: "checkmark.seal.fill")
                .font(.app(.headline))
                .foregroundStyle(.green)
            Text("Calories и GymLogger куплены вместе — платить второй раз не нужно.")
                .font(.app(.subheadline))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            // Честно про границу подарка: флаг живёт в общей папке двух
            // приложений, и если соседа снести, доступ вернётся к своей
            // покупке. Узнать об этом лучше здесь, чем на закрытом экране.
            Text("Доступ держится, пока GymLogger стоит на этом телефоне.")
                .font(.app(.caption))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Button("Готово") { dismiss() }
                .buttonStyle(.mainAction)
                .padding(.top, 4)
        }
        .padding(.top, 12)
        .padding(.horizontal, 24)
        .accessibilityIdentifier("bundleUnlocked")
    }

    private var activeState: some View {
        VStack(spacing: 10) {
            Label("Premium активен", systemImage: "checkmark.seal.fill")
                .font(.app(.headline))
                .foregroundStyle(.green)
            Button("Готово") { dismiss() }
                .buttonStyle(.mainAction)
        }
        .padding(.top, 12)
    }

    private var failedState: some View {
        VStack(spacing: 10) {
            Label("Не удалось загрузить предложения", systemImage: "wifi.slash")
                .font(.app(.subheadline))
                .foregroundStyle(.secondary)
            Button("Повторить") {
                Task { await purchases.load() }
            }
            .buttonStyle(.bordered)
            // Восстановлению тарифы не нужны: оно спрашивает App Store, что
            // уже куплено, — и должно работать, даже когда цены не пришли.
            restoreLink
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

            // Пара приложений — своим блоком и ниже своих тарифов.
            //
            // Вперемешку с ними она читалась бы как ещё два непонятных тира
            // Calories: человек сравнивал бы 44.99 с 59.99, не понимая, за
            // что доплачивает. Отдельным заголовком видно, что это уже не
            // про это приложение.
            if !purchases.bundleProducts.isEmpty {
                VStack(spacing: 8) {
                    Text("Вместе с GymLogger")
                        .font(.app(.subheadline, weight: .semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                    Text("Журнал тренировок того же автора. Одна покупка открывает оба приложения.")
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(purchases.bundleProducts) { product in
                        offerCard(product)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    /// Кнопка покупки и строка мелким под ней — у нижней кромки экрана.
    private var purchaseBar: some View {
        VStack(spacing: 6) {
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
                        ProgressView().tint(Color(.systemBackground))
                    } else {
                        Text(verbatim: selectedProduct?.purchaseTitle(introEligible: purchases.introEligible)
                             ?? String(localized: "Начать программу"))
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.mainAction)
            .disabled(selectedProduct == nil || isPurchasing)

            Text(verbatim: selectedProduct?.termsText(introEligible: purchases.introEligible)
                 ?? String(localized: "Отменить можно в любой момент."))
                .font(.app(.caption2))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            restoreLink
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
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
                        .font(.app(.subheadline, weight: .semibold))
                    if let period = periodText(for: product) {
                        Text(period)
                            .font(.app(.caption))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Text(product.displayPrice)
                    .font(.app(.headline))
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

    /// Восстановить покупку — ссылкой под условиями, а не кнопкой в тулбаре.
    ///
    /// App Review требует, чтобы она была. Но это действие для того, кто уже
    /// заплатил (новый телефон, переустановка), а в тулбаре напротив «Начать
    /// программу» оно читалось как вторая главная кнопка. Под ценой и
    /// условиями её ищут те, кому она нужна, — там она во всех приложениях.
    private var restoreLink: some View {
        Button("Восстановить покупки") {
            Task { await purchases.restore() }
        }
        .font(.app(.caption, weight: .semibold))
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("restorePurchases")
    }

    private func featureRow(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.app(.headline))
                .foregroundStyle(ProgressRing.kcalColors[0])
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: title)
                    .font(.app(.headline))
                Text(verbatim: detail)
                    .font(.app(.footnote))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}
