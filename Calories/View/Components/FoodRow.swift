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
    /// Положить в приём одним касанием, с обычной порцией. nil — кнопки нет:
    /// в дневнике и в «Рационе» строку нажимают, чтобы открыть, а не добавить.
    var quickAdd: (() -> Void)? = nil
    /// Уже в приёме: кнопка рисуется галочкой, повторное нажатие убирает.
    var isAdded: Bool = false

    /// Одна часть составного приёма: имя, цвет своего доминирующего макроса
    /// и вес в граммах — чтобы показать «Молоко 3% 300 г» вместо просто
    /// «Молоко 3%».
    struct FoodPart: Identifiable {
        let name: String
        let macros: Macros
        /// Вес этой части в граммах. nil — не показываем вес.
        let grams: Double?
        /// Штуки — у продукта «на штуку», у которого граммов нет.
        var pieces: Double? = nil
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

    /// Название и значки его свойств. Значки не падают на строку одни.
    ///
    /// Раньше значок был частью одного `Text` с названием, и перенос шёл по
    /// словам внутри него — неразрывные пробелы должны были держать значок
    /// у последнего слова, но на длинном названии он всё равно уходил на
    /// вторую строку один: «Протеин со вкусом печенья» в одну строку, а 🔥
    /// под ней. Теперь два раскладочных варианта, и выбирает их `ViewThatFits`:
    ///
    /// - название и значки целиком в одну строку, если помещаются;
    /// - иначе название переносится, а значки стоят после последнего слова
    ///   на его строке — «Протеин со вкусом / печенья 🔥».
    ///
    /// Третьего, с одиноким значком, нет: он всегда рядом с последним словом.
    ///
    /// Вес — по желанию: у частей составного приёма он стоит в той же строке,
    /// что название, после значков («Молоко 3% 🌿 300 г»), а не отдельной
    /// строкой, как у одиночного продукта: иначе приём из пяти частей
    /// занимал бы десять строк.
    /// Название без последнего слова и само последнее слово.
    ///
    /// Значки встают рядом с последним словом, поэтому оно обязано быть
    /// настоящим: пробелы на концах и двойные пробелы внутри пустых слов не
    /// порождают.
    static func splitName(_ text: String) -> (head: String, last: String) {
        let words = text.split(whereSeparator: \.isWhitespace)
        return (words.dropLast().joined(separator: " "), words.last.map(String.init) ?? text)
    }

    @ViewBuilder
    private func nameBlock(text: String, font: Font, color: Color,
                           traits: [FoodTrait], weight: String? = nil) -> some View {
        // Название оборачиваем в изолятор направления (FSI…PDI): если имя на
        // иврите или арабском, общий двунаправленный алгоритм иначе перемешает
        // его со значками. Для латиницы и кириллицы изолятор не меняет ничего.
        //
        // Слова — без пустых: имя с пробелом на конце («Протеин со вкусом
        // печенья ») давало пустое последнее слово, и значок оставался один
        // на третьей строке. Теперь «последнее слово» — последнее настоящее.
        let (head, last) = Self.splitName(text)
        if traits.isEmpty {
            // Без значков — один `Text`: перенос идёт по словам, а вес
            // встаёт в конец последней строки. Пробел перед весом и внутри
            // него неразрывный, чтобы «300 г» не разрывалось.
            let name = Text("\u{2068}\(text)\u{2069}").font(font).foregroundStyle(color)
            if let weight {
                name + Text("\u{00A0}\u{00A0}" + weight.replacingOccurrences(of: " ", with: "\u{00A0}"))
                    .font(.app(.caption2, weight: .medium)).foregroundStyle(.secondary)
            } else {
                name
            }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\u{2068}\(text)\u{2069}").font(font).foregroundStyle(color).lineLimit(1)
                    traitGlyphs(traits)
                    weightLabel(weight)
                }
                VStack(alignment: .leading, spacing: 0) {
                    if !head.isEmpty {
                        Text("\u{2068}\(head)\u{2069}").font(font).foregroundStyle(color)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\u{2068}\(last)\u{2069}").font(font).foregroundStyle(color)
                        traitGlyphs(traits)
                        weightLabel(weight)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func weightLabel(_ weight: String?) -> some View {
        if let weight {
            Text(verbatim: weight.replacingOccurrences(of: " ", with: "\u{00A0}"))
                .font(.app(.caption2, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private func traitGlyphs(_ traits: [FoodTrait]) -> some View {
        HStack(spacing: 4) {
            ForEach(traits) { trait in
                Image(systemName: trait.symbol)
                    .font(.app(.caption2, weight: .medium))
                    .foregroundStyle(trait.color)
            }
        }
    }

    /// Количество — отдельной строкой под названием у одиночного продукта.
    private func portionLine(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.app(.caption, weight: .medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

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

    /// «+» в круге; в приёме — чёрная галочка. Круг 28 точек, касание 44.
    ///
    /// Строка целиком открывает экран порции, и обычную порцию там
    /// подтверждали вторым касанием. Для продукта, который едят всегда в
    /// одном количестве, это лишнее: «+» кладёт его в приём сразу, с той
    /// порцией, что стоит в строке.
    private func quickAddButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isAdded ? Color.primary : Color.secondary.opacity(0.16))
                Image(systemName: isAdded ? "checkmark" : "plus")
                    .font(.app(size: 13, weight: .bold))
                    .foregroundStyle(isAdded ? Color(.systemBackground) : Color.accentColor)
            }
            .frame(width: 28, height: 28)
            .frame(width: 44, height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: "\(String(localized: "Добавить")) \(name)"))
        .accessibilityAddTraits(isAdded ? .isSelected : [])
        .accessibilityIdentifier("quickAdd")
        .padding(.trailing, -6)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Строки прижаты друг к другу: три яруса (название, порция,
            // макросы) с воздухом по шесть точек растягивали ячейку так, что
            // в поиске помещалось пять продуктов. Ярусы остаются — макросы
            // не стоит склеивать с подписью, — а воздух между ними убран.
            VStack(alignment: .leading, spacing: 2) {
                // Составной приём — каждая часть своей строкой в цвет своего
                // доминирующего макроса: «Молоко» — цветом молока, «Протеин»
                // — цветом белка, а не вся строка одним серым.
                if !parts.isEmpty {
                    // Каждая часть приёма — названием, значками и весом в одной
                    // строке: частей бывает пять, и вес отдельной строкой
                    // удваивал бы высоту приёма.
                    //
                    // Исключение — приём из одной части. Это одиночный
                    // продукт, просто записанный через состав, и вес у него
                    // — отдельной строкой под названием, как у продукта в
                    // «Рационе»: строка названия и вес рядом читались как
                    // одно длинное название («Shweppes Fruit Water 485 г»).
                    if parts.count == 1, let only = parts.first {
                        nameBlock(text: only.name,
                                  font: .app(.callout, weight: .semibold),
                                  color: .primary,
                                  traits: only.traits)
                        if let weight = PortionLabel.text(grams: only.grams, pieces: only.pieces) {
                            portionLine(weight)
                        } else if !portion.isEmpty {
                            portionLine(portion)
                        }
                    } else {
                        ForEach(parts) { part in
                            nameBlock(text: part.name,
                                      font: .app(.callout, weight: .semibold),
                                      color: .primary,
                                      traits: part.traits,
                                      weight: PortionLabel.text(grams: part.grams, pieces: part.pieces))
                        }
                    }
                } else {
                    // Имя, значки свойств и вес — одной строкой. Длинное имя
                    // переносится, а не выталкивает калории за край.
                    nameBlock(text: name,
                              // Название — полужирным, как и в любой строке списка:
                              // в строке оно главное, а всё под ним — приметы.
                              font: .app(.callout, weight: .semibold),
                              // Название чёрное: цвет макросов теперь в полоске справа
                              // (`MacroShareBar`). Раньше им красилось и название, и
                              // буквы под ним, и число калорий — четыре кода без подписей.
                              color: .primary,
                              traits: traits)
                    // Порция — второй строкой, а не хвостом названия: «Тунец
                    // консервированный 🔥 108 г» переносился по словам, и вес
                    // оказывался то в конце первой строки, то в начале второй.
                    if !portion.isEmpty {
                        portionLine(portion)
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

                if !micros.isEmpty || offersVitamins {
                    HStack(spacing: 8) {
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

            if hasMacros {
                MacroShareBar(macros: macros)
            }

            VStack(alignment: .trailing, spacing: 1) {
                Text(verbatim: "\(calories)")
                    .font(.app(.subheadline, weight: EnergyDensity.weight(caloriesPer100g)))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
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
            .padding(.trailing, quickAdd == nil ? 6 : 0)

            if let quickAdd {
                quickAddButton(quickAdd)
            }
        }
        // Чуть компактнее, но не вплотную: ярусы через две точки, вертикальный
        // отступ ячейки девять. В шесть и с зазором в одну точку строки с
        // тремя ярусами и значками слипались.
        .padding(.vertical, 0)
        .listRowInsets(EdgeInsets(top: 9, leading: 16, bottom: 9, trailing: 16))
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
