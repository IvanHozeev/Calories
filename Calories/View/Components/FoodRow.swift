import SwiftUI

/// Строка продукта или блюда в любом списке выбора. Одна на все экраны: раньше
/// в AddEntryView и PantryView лежали свои копии с рассыпанной строкой «Б12 Ж22 У41»
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
    /// Состав приёма по частям: когда передан, каждая часть рисуется своей
    /// строкой в цвет своего доминирующего макроса. Одиночный продукт —
    /// без этого, как раньше.
    var parts: [FoodPart] = []

    /// Одна часть составного приёма: имя, цвет своего доминирующего макроса
    /// и вес в граммах — чтобы показать «Молоко 3% 300 г» вместо просто
    /// «Молоко 3%».
    struct FoodPart: Identifiable {
        let name: String
        let macros: Macros
        /// Вес этой части в граммах. nil — не показываем вес.
        let grams: Double?
        /// Свойства части — листик, огонёк: у записи в дневнике их нет,
        /// их приносит база продуктов по имени части.
        var traits: [FoodTrait] = []
        var id: String { name }
        var color: Color { macros.leadingKind?.color ?? .primary.opacity(0.85) }
    }

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

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Строки прижаты друг к другу: три яруса (название, порция,
            // макросы) с воздухом по шесть точек растягивали ячейку так, что
            // в поиске помещалось пять продуктов. Ярусы остаются — макросы
            // не стоит склеивать с подписью, — а воздух между ними убран.
            VStack(alignment: .leading, spacing: 3) {
                // Составной приём — каждая часть своей строкой в цвет своего
                // доминирующего макроса: «Молоко» — цветом молока, «Протеин»
                // — цветом белка, а не вся строка одним серым.
                if !parts.isEmpty {
                    // Каждая часть приёма — своей строкой в цвет своего
                    // доминирующего макроса: имя, значок свойства и вес.
                    // Длинное имя переносится на вторую строку, а не тянет
                    // строку вправо: колонка ограничена шириной ряда.
                    ForEach(parts) { part in
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text(part.name)
                                // Чуть мельче, чем у одиночного продукта:
                                // в составном приёме строк несколько.
                                .font(.app(.subheadline, weight: .semibold))
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .foregroundStyle(part.color)
                            if !part.traits.isEmpty {
                                Text(verbatim: "·")
                                    .font(.app(.caption, weight: .medium))
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 3) {
                                    ForEach(part.traits) { trait in
                                        Image(systemName: trait.symbol)
                                            .foregroundStyle(trait.color)
                                            .accessibilityLabel(Text(verbatim: trait.title))
                                    }
                                }
                                .font(.app(.caption, weight: .medium))
                            }
                            if let grams = part.grams, grams > 0 {
                                Text(verbatim: "·")
                                    .font(.app(.caption, weight: .medium))
                                    .foregroundStyle(.secondary)
                                Text(String(format: "%.0f г", grams))
                                    .font(.app(.caption, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .fixedSize()
                            }
                        }
                    }
                } else {
                    // Имя, значки свойств и вес — одной строкой. Длинное имя
                    // переносится, а не выталкивает калории за край.
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
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
                            // чтобы сразу было видно, чем продукт «кормит». Если доминирующего
                            // нет — серый, как слово «Calories» на launch screen.
                            .foregroundStyle(leadingKind?.color ?? .primary.opacity(0.85))
                        if !traits.isEmpty {
                            Text(verbatim: "·")
                                .font(.app(.caption, weight: .medium))
                                .foregroundStyle(.secondary)
                            HStack(spacing: 3) {
                                ForEach(traits) { trait in
                                    Image(systemName: trait.symbol)
                                        .foregroundStyle(trait.color)
                                        .accessibilityLabel(Text(verbatim: trait.title))
                                }
                            }
                            .font(.app(.caption, weight: .medium))
                        }
                        if !portion.isEmpty {
                            Text(verbatim: "·")
                                .font(.app(.caption, weight: .medium))
                                .foregroundStyle(.secondary)
                            Text(verbatim: portion)
                                .font(.app(.caption, weight: .medium))
                                .foregroundStyle(.secondary)
                                .fixedSize()
                        }
                    }
                }

                // Подпись слева — сколько ингредиентов у блюда. Всё остальное
                // уже стоит в строке названия, и отдельный ярус ей не нужен.
                if parts.isEmpty, let detail {
                    Text(verbatim: detail)
                        .font(.app(.footnote, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
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
            // Колонке отдаём ровно остаток ширины ряда: имя переносится по
            // словам и не может вытолкнуть число калорий за правый край.
            // Без этой рамки текст берёт натуральную ширину и уезжает.
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 1) {
                Text(verbatim: "\(calories)")
                    .font(.app(.body, weight: EnergyDensity.weight(caloriesPer100g)))
                    .monospacedDigit()
                    .foregroundStyle(EnergyDensity.tint(caloriesPer100g))
                Text("ккал")
                    .font(.app(.caption2))
                    .foregroundStyle(.secondary)
            }
            // Число калорий держится за свой натуральный размер, а колонка
            // текста забирает остаток ряда: так имя переносится и не может
            // вытолкнуть число.
            .fixedSize()
            // Число не липнет к правому краю ячейки: без отступа «ккал»
            // упиралось в границу списка, и строка выглядела обрезанной.
            .padding(.trailing, 6)
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
