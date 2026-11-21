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
    /// Сохранить в дневник сразу, с обычной порцией, не заходя на экран порции:
    /// «+» кладёт в собираемый приём, галочка записывает. nil — кнопки нет.
    var quickSave: (() -> Void)? = nil
    /// Уже в приёме: «+» рисуется чёрной «−», повторное нажатие убирает.
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

    /// Порция для нижней строки: у приёма из одной части — вес этой части,
    /// у продукта — переданная порция. У составного приёма вес стоит в строке
    /// каждой части, и отдельной порции нет.
    private var portionText: String? {
        if !parts.isEmpty {
            guard parts.count == 1, let only = parts.first else { return nil }
            if let weight = PortionLabel.text(grams: only.grams, pieces: only.pieces) { return weight }
            return portion.isEmpty ? nil : portion
        }
        return portion.isEmpty ? nil : portion
    }

    private var leadingKind: MacroKind? { (leadingMacros ?? macros).leadingKind }

    @Environment(\.colorScheme) private var colorScheme

    /// Цвет названия — доминирующего макроса: белковое голубое, жирное
    /// персиковое, углеводное сиреневое. В светлой теме пастель на белом
    /// читается плохо, поэтому там цвет темнее на треть.
    private func nameColor(_ kind: MacroKind?) -> Color {
        guard let kind else { return .primary }
        return colorScheme == .dark ? kind.color : kind.color.mix(with: .black, by: 0.35)
    }

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
                Image(systemName: isAdded ? "minus" : "plus")
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
    }

    /// Галочка: записать в дневник сразу, без экрана порции.
    private func quickSaveButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle().fill(Color.secondary.opacity(0.16))
                Image(systemName: "checkmark")
                    .font(.app(size: 13, weight: .bold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 28, height: 28)
            .frame(width: 36, height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: "\(String(localized: "Записать")) \(name)"))
        .accessibilityIdentifier("quickSave")
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
                                  color: nameColor(only.macros.leadingKind),
                                  traits: only.traits)

                    } else {
                        ForEach(parts) { part in
                            nameBlock(text: part.name,
                                      font: .app(.callout, weight: .semibold),
                                      color: nameColor(part.macros.leadingKind),
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
                              // Название — цветом доминирующего макроса, как и было;
                              // подписи и числа под ним остаются нейтральными, чтобы
                              // цвет значил одно.
                              color: nameColor(leadingKind),
                              traits: traits)
                }

                // Подпись слева — сколько ингредиентов у блюда. Всё остальное
                // уже стоит в строке названия, и отдельный ярус ей не нужен.
                if parts.isEmpty, let detail {
                    Text(verbatim: detail)
                        .font(.app(.footnote, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                // Полоска долей макросов — внизу столбца, под названием и
                // значками: справа она стояла между текстом и числом калорий и
                // отнимала ширину у названия.
                if hasMacros {
                    MacroShareBar(macros: macros, width: 56)
                        .padding(.top, 2)
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

                // Граммы — самой нижней строкой, под полоской макросов и
                // витаминами: порция
                // отдельной строкой, а не хвостом названия («Тунец
                // консервированный 🔥 108 г» переносился по словам, и вес
                // оказывался то в конце первой строки, то в начале второй).
                if let text = portionText {
                    portionLine(text)
                }
            }
            // Колонке отдаём ровно остаток ширины ряда: имя переносится по
            // словам и не может вытолкнуть число калорий за правый край.
            // Без этой рамки текст берёт натуральную ширину и уезжает.
            .frame(maxWidth: .infinity, alignment: .leading)

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
                    .padding(.trailing, quickSave == nil ? -6 : 0)
            }
            if let quickSave {
                quickSaveButton(quickSave)
                    .padding(.trailing, -6)
            }
        }
        // Воздуха побольше: ярусы через три точки, вертикальный отступ
        // ячейки двенадцать. Шесть и девять выходили тесно — строки с тремя
        // ярусами и значками слипались.
        .padding(.vertical, 0)
        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
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
