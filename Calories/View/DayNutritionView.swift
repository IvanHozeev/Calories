import SwiftUI

/// Разбор дня: макросы и микронутриенты на одном экране.
///
/// Раньше про макросы рассказывали три всплывающих окошка на карточке — по
/// одному на белки, жиры и углеводы. Их приходилось открывать по очереди,
/// сравнить их между собой было нельзя, а для витаминов места в таком формате
/// не нашлось бы вовсе. Здесь всё лежит рядом и читается сверху вниз.
struct DayNutritionView: View {
    var store: CalorieStore
    var date: Date = Date()

    private var macros: Macros {
        let day = Calendar.current.startOfDay(for: date)
        return (store.entriesByDay[day] ?? []).reduce(Macros.zero) { $0 + $1.macros }
    }

    private var micronutrients: MicronutrientDay {
        store.micronutrients(on: date)
    }

    var body: some View {
        List {
            Section {
                macroRow(.protein, value: macros.protein, target: store.proteinTarget, color: .blue)
                macroRow(.fat, value: macros.fat, target: store.fatTarget, color: .orange)
                macroRow(.carbs, value: macros.carbs,
                         target: store.carbsTarget ?? MacroTargets.carbsMinimum, color: .purple)
            } header: {
                Text("Белки, жиры, углеводы")
            }

            micronutrientSection
        }
        .glassRow()
        .listStyle(.insetGrouped)
        .scrollIndicators(.hidden)
        .navigationTitle("Разбор дня")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Макросы

    private func macroRow(_ kind: MacroKind, value: Double, target: Double?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(LocalizedStringKey(kind.title))
                Spacer()
                Text(String(format: "%.0f \(String(localized: "г"))", value))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(color)
                    .monospacedDigit()
                if let target {
                    Text(verbatim: "/ \(Int(target.rounded()))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }

            // Граммы на килограмм — то, в чём цели и задаются. Без пересчёта
            // «120 г белка» ничего не говорит: много это или мало, зависит от веса.
            if kind != .carbs, let weightKg = store.weightKg, weightKg > 0 {
                Text(String(format: String(localized: "%.2f г/кг при весе %.1f кг"), value / weightKg, weightKg))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Text(note(for: kind))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }

    private func note(for kind: MacroKind) -> String {
        switch kind {
        case .protein:
            return String(localized: "Норма белка из профиля — от веса или от сухой массы, смотря что выбрано.")
        case .fat:
            return String(localized: "Норма жира из профиля. Ниже 0.5 г/кг рискуешь гормонами — жир нужен телу постоянно.")
        case .carbs:
            return store.carbsTarget == nil
                ? String(localized: "130 г/день — RDA, минимум глюкозы для работы мозга, не зависит от веса.")
                : String(localized: "Остаток дневной нормы после белка и жира — то, чем управляешь ты.")
        }
    }

    // MARK: - Витамины и минералы

    @ViewBuilder
    private var micronutrientSection: some View {
        let day = micronutrients
        Section {
            if day.totalCalories == 0 {
                Text("За этот день ещё ничего не записано.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if !day.isTrustworthy {
                // Показать числа тут было бы враньём умолчанием: они посчитаны
                // по такой части дня, что означают что угодно.
                Text("Слишком мало известно о составе съеденного, чтобы считать. Витамины есть у продуктов встроенной базы; у своей еды и товаров из Open Food Facts их нет.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(Micronutrient.allCases) { nutrient in
                    if let amount = day.totals[nutrient] {
                        nutrientRow(nutrient, amount: amount)
                    }
                }
            }
        } header: {
            Text("Витамины и минералы")
        } footer: {
            if day.totalCalories > 0 {
                Text(String(format: String(localized: "Посчитано по %lld%% съеденного за день."),
                            Int((day.coverage * 100).rounded())))
            }
        }
    }

    private func nutrientRow(_ nutrient: Micronutrient, amount: Double) -> some View {
        let share = amount / nutrient.dailyValue
        // У натрия шкала означает обратное: заполнилась — плохо. Поэтому он
        // оранжевый с самого начала, а не зелёный до какого-то порога.
        let color: Color = nutrient.isCeiling
            ? (share > 1 ? .red : .orange)
            : (share >= 1 ? .green : .blue)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(nutrient.title)
                Spacer()
                Text(verbatim: formatted(amount, nutrient))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Text(verbatim: "\(Int((share * 100).rounded()))%")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
                    .monospacedDigit()
            }
            ProgressView(value: min(share, 1))
                .progressViewStyle(.engraved(color))
        }
        .padding(.vertical, 2)
    }

    /// Один формат на все нутриенты давал бы либо «0 мкг» у B12, либо «558.0 мг»
    /// у калия: они различаются на три порядка.
    private func formatted(_ amount: Double, _ nutrient: Micronutrient) -> String {
        let digits = amount < 10 ? 1 : 0
        return String(format: "%.\(digits)f \(nutrient.unit)", amount)
    }
}
