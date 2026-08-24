import SwiftUI

/// Доли белков, жиров и углеводов в калорийности — одной полосой.
/// Граммы не отвечают на вопрос «жирный ли это продукт»: 31 г жира и 58 г углеводов
/// выглядят сопоставимо, хотя жир даёт вдвое больше калорий на грамм. Полоса считает
/// именно калории и показывает перекос сразу.
struct MacroSplitBar: View {
    let macros: Macros
    var showsLabels: Bool = true

    private var kcal: (protein: Double, fat: Double, carbs: Double, total: Double) {
        let p = macros.protein * MacroTargets.kcalPerProteinGram
        let f = macros.fat * MacroTargets.kcalPerFatGram
        let c = macros.carbs * MacroTargets.kcalPerCarbGram
        return (p, f, c, p + f + c)
    }

    private func percent(_ value: Double) -> Int {
        guard kcal.total > 0 else { return 0 }
        return Int((value / kcal.total * 100).rounded())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    segment(kcal.protein, color: .blue, width: geo.size.width)
                    segment(kcal.fat, color: .orange, width: geo.size.width)
                    segment(kcal.carbs, color: .purple, width: geo.size.width)
                }
            }
            .frame(height: 8)
            .clipShape(Capsule())

            if showsLabels {
                HStack(spacing: 12) {
                    label("Белки", percent(kcal.protein), .blue)
                    label("Жиры", percent(kcal.fat), .orange)
                    label("Углеводы", percent(kcal.carbs), .purple)
                }
            }
        }
    }

    private func segment(_ value: Double, color: Color, width: CGFloat) -> some View {
        let share = kcal.total > 0 ? value / kcal.total : 0
        return Capsule()
            .fill(color)
            .frame(width: max(0, width * share))
    }

    private func label(_ title: LocalizedStringKey, _ percent: Int, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(verbatim: "\(percent)%")
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
        }
    }
}
