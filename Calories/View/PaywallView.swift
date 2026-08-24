import SwiftUI

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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "sparkles")
                    .font(.system(size: 56))
                    .foregroundStyle(.yellow)

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

                VStack(alignment: .leading, spacing: 14) {
                    featureRow("Персональный план: срок в неделях, целевой вес, точная дневная норма калорий")
                    featureRow("Автоматический пересчёт темпа и предупреждение, если он слишком агрессивный")
                    featureRow("Прогресс плана прямо на главном экране")
                }
                .padding(.horizontal, 28)

                Spacer()

                VStack(spacing: 8) {
                    Button {
                        store.isPremium = true
                        dismiss()
                    } label: {
                        Text("Оформить Premium")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    .buttonStyle(.borderedProminent)

                    Text("Демо-заглушка: без реальной оплаты, просто включает Premium.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .navigationTitle("Подписка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
        }
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
