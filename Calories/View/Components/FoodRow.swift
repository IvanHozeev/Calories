import SwiftUI

/// Строка продукта или блюда в любом списке выбора. Одна на все экраны: раньше
/// в AddEntryView и MyFoodView лежали свои копии с рассыпанной строкой «Б12 Ж22 У41»
/// и калориями серым шрифтом на втором плане.
struct FoodRow: View {
    let name: String
    let calories: Int
    /// Порция, к которой относятся цифры: «100 г», «250 г».
    let portion: String
    let macros: Macros
    /// Подпись слева от порции — например, число ингредиентов у блюда.
    var detail: String? = nil
    /// Значки категорий. У продукта он один, у блюда — по одному на каждую
    /// категорию его состава: так видно, из чего блюдо, не открывая его.
    var icons: [String] = []
    /// Чем продукт богат в показанной порции.
    var micros: [Micronutrient] = []
    /// У продукта нет витаминов, но каталог может их дать — зайди и возьми.
    /// Метка, а не автоматическая подстановка: «Творог мой» похож на «Творог 5%»,
    /// и приписать чужой состав молча — то же враньё, только незаметное.
    var offersVitamins: Bool = false
    /// По чему судить о ведущем макросе, если показанная порция не сто грамм.
    /// «Богат белком» — свойство продукта, а не порции: иначе один и тот же
    /// творог в разных списках то подсвечен, то нет.
    var leadingMacros: Macros? = nil
    /// Свойства продукта: можно много, термический эффект, легко переесть.
    var traits: [FoodTrait] = []

    private var leadingKind: MacroKind? { (leadingMacros ?? macros).leadingKind }

    private var hasMacros: Bool {
        macros.protein > 0 || macros.fat > 0 || macros.carbs > 0
    }

    /// Метка «здесь есть что взять».
    ///
    /// Мягкая и без цифр: это приглашение зайти, а не ошибка и не недостача.
    /// Искры, потому что значок должен читаться как находка, а не как
    /// предупреждение — предупреждающий цвет в этом приложении уже занят
    /// натрием и перебором калорий.
    private var vitaminOffer: some View {
        HStack(spacing: 3) {
            Image(systemName: "sparkles")
            Text("витамины")
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.teal)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.teal.opacity(0.14), in: Capsule())
        .accessibilityLabel(Text("Можно взять витамины из базы"))
        .accessibilityIdentifier("vitaminOffer")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                // Значки свойств — рядом с названием: это про сам продукт,
                // а не про порцию, и читаются они до цифр.
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(name)
                        .lineLimit(2)
                    ForEach(traits) { trait in
                        Image(systemName: trait.symbol)
                            .font(.caption)
                            .foregroundStyle(trait.color)
                            .accessibilityLabel(Text(verbatim: trait.title))
                    }
                }

                // Та же строка подписей, что и в дневнике: ячейки продукта
                // должны читаться одинаково, где бы они ни стояли.
                HStack(spacing: 6) {
                    if let detail {
                        Text(verbatim: detail)
                        Text(verbatim: "·")
                    }
                    Text(verbatim: portion)
                    if !icons.isEmpty {
                        Text(verbatim: "·")
                        HStack(spacing: 4) {
                            ForEach(icons.prefix(3), id: \.self) { icon in
                                Image(systemName: icon)
                            }
                        }
                        .accessibilityHidden(true)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if hasMacros || !micros.isEmpty || offersVitamins {
                    HStack(spacing: 8) {
                        if hasMacros {
                            MacroTags(macros: macros, compact: true)
                        }
                        if !micros.isEmpty {
                            MicroTags(nutrients: micros)
                        }
                        if offersVitamins {
                            vitaminOffer
                        }
                    }
                }
            }
            // Полоска ведущего макроса — ровно от названия до чипов: по высоте
            // блока текста, а не всей ячейки, и чуть левее букв, в поле строки.
            //
            // Со слабым свечением своего цвета, и только им. Дымка по всей
            // строке была лишней: сигнал и так читается по полоске, а цветной
            // фон спорил с чипами и делал соседние строки пёстрыми.
            // Место под полоску занято всегда, даже когда её нет: иначе
            // названия подсвеченных и обычных строк стояли бы на разной высоте
            // по левому краю.
            .padding(.leading, 11)
            .overlay(alignment: .leading) {
                if let leadingKind {
                    Capsule()
                        .fill(leadingKind.color)
                        .frame(width: 3)
                        .shadow(color: leadingKind.color.opacity(0.55), radius: 4)
                        .accessibilityHidden(true)
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 1) {
                Text(verbatim: "\(calories)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                Text("ккал")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        // Разделитель начинается от края содержимого — там же, где полоска,
        // а не от названия, отодвинутого под неё.
        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
    }
}

/// Свойства продукта строками с пояснением — для экрана порции.
struct FoodTraitsSection: View {
    let traits: [FoodTrait]

    var body: some View {
        if !traits.isEmpty {
            Section {
                ForEach(traits) { trait in
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: trait.title)
                                .font(.subheadline.weight(.semibold))
                            Text(verbatim: trait.explanation)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } icon: {
                        Image(systemName: trait.symbol)
                            .foregroundStyle(trait.color)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}
