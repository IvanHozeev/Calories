import SwiftUI

/// Строка подсказки взвеситься или заполнить профиль под кольцом калорий.
///
/// Показывается только когда профиль не заполнен или вес за сегодня не внесён.
struct WeighInPromptRow: View {
    let profileIsEmpty: Bool
    let hasWeighedToday: Bool
    let onWeighIn: () -> Void
    let onOpenProfile: () -> Void

    var body: some View {
        if profileIsEmpty {
            NavigationLink {
                // Открывается вызывающей стороной через onOpenProfile
            } label: {
                promptRow(
                    icon: "person.crop.circle.badge.questionmark",
                    title: "Заполнить профиль",
                    color: .blue
                )
            }
            .buttonStyle(.plain)
            .onTapGesture { onOpenProfile() }
        } else if !hasWeighedToday {
            Button(action: onWeighIn) {
                promptRow(
                    icon: "scalemass",
                    title: "Взвешивание",
                    color: .orange
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func promptRow(icon: String, title: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.app(.footnote))
            Text(title)
                .font(.app(.caption))
            Spacer()
            Image(systemName: "chevron.right")
                .font(.app(.caption2))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
