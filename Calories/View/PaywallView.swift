import SwiftUI
import StoreKit

/// С какой фичи пользователь пришёл в пейволл. Абстрактная «Подписка» продаёт хуже,
/// чем конкретный ответ на вопрос, который человек задавал секунду назад.
enum PaywallFocus {
    case general
    case plan
    /// Пробные две недели кончились: разговор не про «купи», а про «вот что было
    /// за две недели, и вот что закрылось».
    case trialEnded

    var headline: String {
        switch self {
        case .general: return String(localized: "Норма, которая считает по тебе")
        case .plan: return String(localized: "Персональный план")
        case .trialEnded: return String(localized: "Пробные две недели закончились")
        }
    }

    var subtitle: String? {
        switch self {
        case .general: return String(localized: "Не число из формулы, а расход, измеренный по твоему дневнику и весам.")
        case .plan: return String(localized: "Персональный план калорийности под твои цели")
        case .trialEnded: return String(localized: "План продолжает считать норму. Экран плана, вердикт и настройка — в Premium.")
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

    /// Кончился пробный период — говорим об этом, откуда бы ни открыли пэйвол.
    /// Открытому бандлом про конец пробного периода говорить нечего: доступ
    /// у него есть, и «пробные две недели закончились» звучит как потеря.
    private var shownFocus: PaywallFocus {
        store.trialEnded && !unlockedByBundle ? .trialEnded : focus
    }

    /// Открыто бандлом: своей покупки нет, но пара приложений куплена в
    /// GymLogger. Показывать цены здесь нельзя — человек уже заплатил, и
    /// тарифы читаются как требование заплатить снова.
    private var unlockedByBundle: Bool { store.bundleUnlocked && !purchases.isPremium }

    private var selectedProduct: Product? {
        purchases.products.first { $0.id == selectedID }
            ?? purchases.subscriptions.first
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header
                if shownFocus == .trialEnded { trialSummary }
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
        // Справа не значок, а слово «Восстановить»: места оно занимает втрое
        // больше, и заголовок, посчитанный по одной кнопке, залезал под шеврон.
        .screenTitle(String(localized: "Подписка"), trailingButtons: 3)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Восстановить") {
                    Task { await purchases.restore() }
                }
                .font(.app(.footnote))
            }
        }
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

            Text(shownFocus.headline)
                .font(.app(.title, weight: .bold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            if let subtitle = shownFocus.subtitle {
                Text(subtitle)
                    .font(.app(.subheadline))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }
        }
    }

    /// Что входит — не списком галочек, а с одной строкой объяснения на
    /// каждую.
    ///
    /// Галочка без объяснения продаёт только то, что человек и так знает по
    /// названию. А продаёт здесь ровно то, чего нет у счётчиков калорий:
    /// норма, которая идёт за измеренным расходом, и которая не меняется
    /// у человека за спиной.
    private var features: some View {
        VStack(spacing: 18) {
            featureRow("chart.line.uptrend.xyaxis", "Норма идёт за расходом",
                       "Расход считается по твоему дневнику и весам, а не по формуле: она не знает ни твоей работы, ни адаптации к дефициту.")
            featureRow("hand.raised", "Норма не меняется молча",
                       "Раз в неделю приложение показывает, что посчитало, и спрашивает. До ответа держит прежнюю.")
            featureRow("calendar", "План из фаз",
                       "Сушка, поддержание, набор — у каждой свой темп и срок, и видно, на какой ты неделе.")
            featureRow("fork.knife", "Рефиды и диет-брейки",
                       "По расписанию или вручную. Рефид можно перенести на праздник, не ломая неделю.")
            featureRow("checkmark.seal", "Вердикт, который не врёт",
                       "Если данных мало, так и будет сказано: по трём дням вес не судят.")
        }
        .padding(.horizontal, 24)
    }

    /// Итоги пробного периода: то, что уже работает на человека.
    @ViewBuilder
    private var trialSummary: some View {
        if let summary = store.trialSummary {
            VStack(alignment: .leading, spacing: 10) {
                Text("За две недели")
                    .font(.app(.headline))
                summaryRow("calendar", String(format: String(localized: "Дней с записями: %lld из %lld"),
                                              summary.loggedDays, CalorieStore.trialDays))
                if let change = summary.weightChangeKg {
                    summaryRow("figure.stand", String(format: String(localized: "Вес по тренду: %+.1f кг"), change))
                }
                if let status = store.planAdherence()?.status {
                    summaryRow(status.icon, status.title)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .glassCard()
            .padding(.horizontal, 20)
        }
    }

    private func summaryRow(_ icon: String, _ text: String) -> some View {
        Label {
            Text(verbatim: text)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(.green)
        }
        .font(.app(.subheadline))
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
                .buttonStyle(.borderedProminent)
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
                .buttonStyle(.borderedProminent)
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
                        ProgressView()
                    } else {
                        Text("Оформить Premium")
                            .font(.app(.body, weight: .semibold))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedProduct == nil || isPurchasing)

            Text(introText(for: selectedProduct) ?? String(localized: "Отменить можно в любой момент."))
                .font(.app(.caption2))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
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

    private func introText(for product: Product?) -> String? {
        guard let offer = product?.subscription?.introductoryOffer,
              offer.paymentMode == .freeTrial else { return nil }
        return String(localized: "Первая неделя бесплатно, потом по тарифу. Отменить можно в любой момент.")
    }

    private func featureRow(_ icon: String,
                            _ title: LocalizedStringKey,
                            _ detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.app(.headline))
                .foregroundStyle(ProgressRing.kcalColors[0])
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.app(.headline))
                Text(detail)
                    .font(.app(.footnote))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}
