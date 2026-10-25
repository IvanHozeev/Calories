import SwiftUI

/// Заголовок секции, переезжающий в шапку.
///
/// Каталог длинный и разложен по категориям: рыба, крупы, молочное.
/// Приклеенный заголовок говорит, где человек находится, но стоит ему уехать —
/// и экран снова называется просто «Рацион», хотя под пальцем уже третья
/// категория. Здесь заголовок не дублируется в шапке, а **переезжает** в неё:
/// секция гаснет ровно в том темпе, в каком имя проявляется наверху.
///
/// Устройство взято у соседнего приложения, вместе с тремя его граблями —
/// каждая из них стоила бы нам того же времени:
///
/// 1. Переход ведётся **долей пути**, а не порогом. Порог с гистерезисом —
///    величина булева, и на стыке секций имя мигает от движения пальца на
///    пиксель. Доля непрерывна, и дёргаться нечему.
/// 2. Приклеенный заголовок приходит в покой **не на нуле**: список едет под
///    шапкой, и упирается заголовок в линию безопасной зоны плюс собственный
///    отступ. Сравнение с нулём не срабатывает никогда.
/// 3. Во время переезда список держит на экране **два экземпляра** одного
///    заголовка — приклеенный и тот, что на своём месте. Оба сообщают
///    координату, и без склейки имя оказывается в шапке и в списке разом.
struct SectionHead: Equatable {
    var label: String
    var y: CGFloat
}

struct SectionHeadKey: PreferenceKey {
    static var defaultValue: [SectionHead] { [] }

    static func reduce(value: inout [SectionHead], nextValue: () -> [SectionHead]) {
        value.append(contentsOf: nextValue())
    }
}

/// Линия, на которой заголовок приходит в покой. Меряем, а не задаём числом:
/// у каждого экрана своя безопасная зона.
struct PinLineKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Состояние переезда: что в шапке сейчас, что подъезжает и насколько.
///
/// Отдельным наблюдаемым объектом, а не состоянием экрана. Прокрутка меняет
/// его десятки раз в секунду, и будь это `@State` экрана — на каждом кадре
/// перестраивался бы весь список.
@Observable
@MainActor
final class SectionHeadState {
    /// Имя, стоящее в шапке.
    private(set) var current: String?
    /// Имя, которое подъезжает ему на смену.
    private(set) var next: String?
    /// Доля пути от 0 до 1: ноль — ещё ничего не началось, единица — смена.
    private(set) var blend: CGFloat = 0

    /// Длина дорожки перехода в точках. Сорок — путь, который палец проходит
    /// заметно, но не настолько долго, чтобы шапка жила в полупрозрачности.
    static let handover: CGFloat = 40

    /// - Parameter order: секции в том порядке, в каком они на экране. Без
    ///   него имя держалось бы только пока виден сам заголовок.
    func update(heads: [SectionHead], order: [String],
                pinLine: CGFloat, headTopInset: CGFloat = 16) {
        let rest = pinLine + headTopInset

        // Одна запись на секцию — та, что ближе к линии покоя. Без этого
        // приклеенная копия и копия на своём месте считаются двумя секциями.
        let unique = Dictionary(grouping: heads, by: \.label).values.compactMap {
            $0.min { abs($0.y - rest) < abs($1.y - rest) }
        }

        let reached = unique.filter { $0.y <= rest + 1 }.max { $0.y < $1.y }?.label
        let upcoming = unique
            .filter { $0.y > rest + 1 && $0.label != reached }
            .min { $0.y < $1.y }

        // Имя держится всю секцию, а не пока виден её заголовок.
        //
        // В сгруппированном списке заголовки не прилипают — они уезжают
        // вместе с содержимым. У длинной категории заголовок давно за
        // экраном, а человек всё ещё внутри неё; опираться на видимость
        // значило бы посреди «Круп и хлеба» показывать имя экрана.
        //
        // Поэтому, когда наверху не видно ни одного заголовка, текущей
        // считается та секция, что стоит перед первой видимой: раз её
        // заголовок уже выше экрана, мы внутри неё.
        if let reached {
            current = reached
        } else if let firstBelow = unique.min(by: { $0.y < $1.y }),
                  let index = order.firstIndex(of: firstBelow.label), index > 0 {
            current = order[index - 1]
        } else {
            // Выше первой секции — значит человек в начале списка.
            current = nil
        }
        if let upcoming, upcoming.y - rest < Self.handover {
            next = upcoming.label
            // Сглаживание: у краёв дорожки движение замедляется, и переход
            // не выглядит линейной протяжкой.
            let raw = 1 - (upcoming.y - rest) / Self.handover
            blend = raw * raw * (3 - 2 * raw)
        } else {
            next = nil
            blend = 0
        }
    }

    /// Насколько погасить сам заголовок секции: он уходит в шапку, а не
    /// остаётся на экране вторым экземпляром.
    func opacity(of label: String) -> Double {
        if label == current { return Double(max(0, 1 - blend * 1.45)) }
        return 1
    }
}

extension View {
    /// Заголовок секции сообщает своё положение в списке.
    func tracksSectionHead(_ label: String) -> some View {
        background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: SectionHeadKey.self,
                    value: [SectionHead(label: label,
                                        y: geometry.frame(in: .scrollView(axis: .vertical)).minY)])
            }
        }
    }

    /// Измерить линию покоя — верхнюю безопасную зону этого экрана.
    func measuresPinLine() -> some View {
        background {
            GeometryReader { geometry in
                Color.clear.preference(key: PinLineKey.self, value: geometry.safeAreaInsets.top)
            }
        }
    }
}

/// Пара имён в шапке: уходящее и подъезжающее.
///
/// Отдельной вьюхой — чтобы прокрутка перерисовывала её, а не весь экран.
/// Прозрачности не встречаются на половине пути: уходящее гаснет на первых
/// двух третях, приходящее проявляется на последней. Встречаясь посередине,
/// оба по половине, они читались как смаз.
struct SectionHeadTitle: View {
    let state: SectionHeadState
    /// Имя экрана — то, что стоит в шапке, пока ни одна секция не доехала.
    let fallback: String

    var body: some View {
        ZStack {
            title(state.current ?? fallback)
                .opacity(1 - min(1, Double(state.blend) * 1.45))
                .offset(y: -11 * state.blend)
            if let next = state.next {
                title(next)
                    .opacity(max(0, (Double(state.blend) - 0.32) / 0.68))
                    .offset(y: 13 * (1 - state.blend))
            }
        }
        .frame(height: 34)
        .clipped()
    }

    private func title(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.app(.headline, weight: .bold))
            .lineLimit(1)
    }
}
