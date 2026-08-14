import SwiftUI

struct MacrosRow: View {
    let macros: Macros

    var body: some View {
        HStack(spacing: 20) {
            macroItem(title: "Белки", value: macros.protein, color: .blue)
            macroItem(title: "Жиры", value: macros.fat, color: .orange)
            macroItem(title: "Углеводы", value: macros.carbs, color: .purple)
        }
    }

    private func macroItem(title: String, value: Double, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(formatted(value))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func formatted(_ value: Double) -> String {
        String(format: "%.0f г", value)
    }
}
