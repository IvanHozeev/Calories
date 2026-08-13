import SwiftUI

struct PaywallView: View {
    @ObservedObject var store: CalorieStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "sparkles")
                    .font(.system(size: 56))
                    .foregroundStyle(.yellow)

                Text("Premium")
                    .font(.largeTitle.bold())

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

    private func featureRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(text)
            Spacer()
        }
    }
}
