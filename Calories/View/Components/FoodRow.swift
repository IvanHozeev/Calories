import SwiftUI

/// Строка продукта или блюда в любом списке выбора. Одна на все экраны: раньше
/// в AddEntryView и MyFoodView лежали свои копии с рассыпанной строкой «Б12 Ж22 У41»
/// и калориями серым шрифтом на втором плане.
struct FoodRow: View {
    let name: String
    let calories: Int
    /// Калорийность ста граммов — для цвета числа. Необязательна: у приёма
    /// пищи и у подсказки её нет, и тогда число остаётся обычным.
    var caloriesPer100g: Int? = nil
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
            Text("Витамины")
        }
        .font(.app(.caption2, weight: .semibold))
        .foregroundStyle(.teal)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .chipSurface(tint: .teal)
        .accessibilityLabel(Text("Можно взять витамины из базы"))
        .accessibilityIdentifier("vitaminOffer")
    }

    /// Ярус примет: сколько ингредиентов, сколько граммов, значки категорий и
    /// свойств. Значки параметром, потому что при нехватке места уходят
    /// первыми именно они — см. `ViewThatFits` в теле строки.
    private func signs(iconLimit: Int, showTraits: Bool) -> some View {
        HStack(spacing: 6) {
            if let detail {
                Text(verbatim: detail)
                Text(verbatim: "·")
            }
            Text(verbatim: portion)
            if iconLimit > 0, !icons.isEmpty {
                Text(verbatim: "·")
                HStack(spacing: 4) {
                    ForEach(icons.prefix(iconLimit), id: \.self) { icon in
                        Image(systemName: icon)
                    }
                }
                .accessibilityHidden(true)
            }
            // Без капсулы: соседи по строке — граммы и значок категории —
            // стоят голыми, и подложка под одним значком делала его кнопкой,
            // которой он не является. Отделяется он тем же, чем отделены они
            // друг от друга, — точкой.
            if showTraits, !traits.isEmpty {
                Text(verbatim: "·")
                HStack(spacing: 4) {
                    ForEach(traits) { trait in
                        Image(systemName: trait.symbol)
                            .foregroundStyle(trait.color)
                            .accessibilityLabel(Text(verbatim: trait.title))
                    }
                }
            }
        }
        .font(.app(.caption))
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Строки прижаты друг к другу: три яруса (название, порция,
            // макросы) с воздухом по шесть точек растягивали ячейку так, что
            // в поиске помещалось пять продуктов. Ярусы остаются — макросы
            // не стоит склеивать с подписью, — а воздух между ними убран.
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    // Название — полужирным, как и в любой строке списка:
                    // в строке оно главное, а всё под ним — приметы. Пока
                    // оно шло тем же весом, что подписи, строка читалась
                    // ровным серым полотном, и глазу не за что было зацепиться.
                    .font(.app(.body, weight: .semibold))
                    .lineLimit(2)
                    // Выключка строки — по интерфейсу, а не по буквам:
                    // см. ту же правку в строке дневника.
                    .multilineTextAlignment(.leading)
                    // Цвет названия — цвет доминирующего макроса порции (по граммам),
                    // чтобы сразу было видно, чем продукт «кормит».
                    .foregroundStyle(leadingKind?.color ?? .primary)

                // Та же строка подписей, что и в дневнике: ячейки продукта
                // должны читаться одинаково, где бы они ни стояли.
                //
                // Значки свойств стоят здесь же, а не у названия. У названия
                // огонёк висел вторым словом и ломал строку в самом неудобном
                // месте — длинное имя переносилось, а значок уезжал за ним.
                // Здесь он стоит в ряду с граммами и значком категории, то
                // есть среди таких же примет продукта.
                // Когда всё не влезает, уступают значки, а не числа.
                //
                // Строка сначала переносилась по словам — и «3260 г» вставало
                // двумя ярусами, где «326» читалось как другое число. Запрет
                // переноса это не вылечил, а поменял: резаться стали числа,
                // «4 ин… · 32…». Оба раза страдало главное, хотя лишнее стоит
                // рядом: значок категории и значок свойства — приметы, они
                // помогают узнать строку, но их отсутствие ничего не искажает.
                // Поэтому берём первую раскладку, которая влезает целиком, и
                // отдаём значки по одному.
                ViewThatFits(in: .horizontal) {
                    signs(iconLimit: 3, showTraits: true)
                    signs(iconLimit: 1, showTraits: true)
                    signs(iconLimit: 0, showTraits: true)
                    signs(iconLimit: 0, showTraits: false)
                }

                if hasMacros || !micros.isEmpty || offersVitamins {
                    HStack(spacing: 8) {
                        if hasMacros {
                            MacroTags(macros: macros, compact: true, leading: leadingKind)
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
            // Полоски ведущего макроса здесь больше нет: о нём говорит сама
            // строка макросов — ведущая цифра крупнее и в своём цвете. Полоска
            // была вторым знаком о том же, и её ещё надо было выучить.

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 1) {
                Text(verbatim: "\(calories)")
                    .font(.app(.subheadline, weight: EnergyDensity.weight(caloriesPer100g)))
                    .monospacedDigit()
                    .foregroundStyle(EnergyDensity.tint(caloriesPer100g))
                Text("ккал")
                    .font(.app(.caption2))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        // Разделитель начинается от края содержимого — там же, где полоска,
        // а не от названия, отодвинутого под неё.
        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
    }
}

/// Свойства продукта строками с пояснением — для экрана порции.
/// Те же свойства, но строками внутри карточки, а не отдельной секцией.
///
/// На экране порции они стоят рядом с числом, которое объясняют. Отдельной
/// карточкой над всем остальным они уезжали под шапку, едва поднималась
/// клавиатура, — то есть именно тогда, когда человек на этот экран и смотрит.
struct FoodTraitLines: View {
    let traits: [FoodTrait]

    var body: some View {
        if !traits.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(traits) { trait in
                    Label {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: trait.title)
                                .font(.app(.footnote, weight: .semibold))
                            Text(verbatim: trait.explanation)
                                .font(.app(.caption2))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } icon: {
                        Image(systemName: trait.symbol)
                            .foregroundStyle(trait.color)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct FoodTraitsSection: View {
    let traits: [FoodTrait]

    var body: some View {
        if !traits.isEmpty {
            Section {
                ForEach(traits) { trait in
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: trait.title)
                                .font(.app(.subheadline, weight: .semibold))
                            Text(verbatim: trait.explanation)
                                .font(.app(.caption))
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
