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

    /// Строка названия: имя, значки свойств и вес, склеенные в один `Text`.
    ///
    /// Склейка, а не `HStack`, ради переноса: `HStack` переносить не умеет,
    /// и вес стоял у первой строки, пока имя уезжало вниз. В одном `Text`
    /// всё течёт по словам — вес встаёт в конец последней строки.
    ///
    /// Части разделены неразрывным пробелом: точка между ними убрана,
    /// строка читается как «Творог 5% 🌿 200 г».
    private func nameLine(text: String, font: Font, color: Color,
                          traits: [FoodTrait], weight: String?) -> Text {
        // Название оборачиваем в изолятор направления (FSI…PDI): если имя на
        // иврите или арабском, общий двунаправленный алгоритм иначе перемешает
        // его с иконками и весом — вес окажется в начале строки,
        // а имя в конце. Для латиницы и кириллицы изолятор не меняет ничего.
        var line = Text("\u{2068}\(text)\u{2069}").font(font).foregroundStyle(color)
        if !traits.isEmpty {
            line = line + Text("\u{00A0}\u{00A0}")
            for (index, trait) in traits.enumerated() {
                if index > 0 { line = line + Text("\u{00A0}\u{00A0}") }
                line = line + Text(Image(systemName: trait.symbol))
                    .font(.app(.caption2, weight: .medium))
                    .foregroundStyle(trait.color)
            }
        }
        if let weight {
            line = line + Text("\u{00A0}\u{00A0}")
            line = line + Text(weight).font(.app(.caption2, weight: .medium)).foregroundStyle(.secondary)
        }
        return line
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
                    // Это один `Text`, а не `HStack`: перенос идёт по словам,
                    // и вес встаёт в конец последней строки, а не висит
                    // у первой.
                    ForEach(parts) { part in
                        nameLine(text: part.name,
                                 font: .app(.callout, weight: .semibold),
                                 color: part.color,
                                 traits: part.traits,
                                 weight: part.grams.flatMap {
                                     $0 > 0 ? String(format: "%.0f \(String(localized: "г"))", $0) : nil
                                 })
                    }
                } else {
                    // Имя, значки свойств и вес — одной строкой. Длинное имя
                    // переносится, а не выталкивает калории за край.
                    nameLine(text: name,
                             // Название — полужирным, как и в любой строке списка:
                             // в строке оно главное, а всё под ним — приметы.
                             font: .app(.callout, weight: .semibold),
                             // Цвет названия — цвет доминирующего макроса порции (по граммам),
                             // чтобы сразу было видно, чем продукт «кормит».
                             color: leadingKind?.color ?? .primary.opacity(0.85),
                             traits: traits,
                             weight: portion.isEmpty ? nil : portion)
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
