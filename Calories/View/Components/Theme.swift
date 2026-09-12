import SwiftUI

/// Матовое стекло вместо плоской серой подложки карточек.
/// Тонкий градиентный кант сверху вниз — то, что отличает «премиальную» вёрстку
/// от прямоугольника с заливкой: он имитирует блик по верхней кромке.
struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = 16
    @Environment(\.colorScheme) private var colorScheme

    private var strokeColors: [Color] {
        colorScheme == .dark
            ? [.white.opacity(0.18), .white.opacity(0.02)]
            : [.white.opacity(0.90), .black.opacity(0.04)]
    }

    /// Карточка почти не отличается от фона по цвету — отделяет её тень, а не заливка.
    /// Прежние 0.55 белого поверх материала давали серое пятно на сером фоне: границы
    /// читались, но выглядело грязно.
    private var tint: Color {
        colorScheme == .dark ? .white.opacity(0.08) : .white.opacity(0.92)
    }

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: cornerRadius).fill(tint))
            }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        LinearGradient(colors: strokeColors, startPoint: .top, endPoint: .bottom),
                        lineWidth: 1
                    )
            )
            // Без тени: любая заметная тень на светлом сером фоне читается как подложка,
            // а не как объём, и карточка начинает отличаться от строк списка,
            // у которых тени нет. Разделяют заливка и кант.
    }
}

extension View {
    /// Карточка из матового стекла с градиентным кантом.
    func glassCard(cornerRadius: CGFloat = 16) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius))
    }

}

/// Стеклянная подложка строки списка. Нужна там, где контент — обычные ячейки Form/List,
/// а не самостоятельные карточки: insetGrouped сам скругляет секцию, поэтому заливаем
/// прямоугольником, а не RoundedRectangle.
struct GlassRow: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    private var tint: Color {
        colorScheme == .dark ? .white.opacity(0.08) : .white.opacity(0.92)
    }

    func body(content: Content) -> some View {
        content.listRowBackground(
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Rectangle().fill(tint))
        )
    }
}

extension View {
    /// Строки секции на матовом стекле — как карточки на «Сегодня».
    func glassRow() -> some View {
        modifier(GlassRow())
    }
}

/// Вдавленность: канавка, прорезанная в поверхности карточки.
///
/// Приём один на кольцо, полосу и всё остальное, что показывает прогресс, поэтому
/// цвета живут здесь, а не расползаются по компонентам.
///
/// Физика простая, её стоит держать в голове при правке чисел: свет падает
/// сверху. Верхняя стенка канавки бросает тень внутрь и вниз, нижняя — ловит
/// свет. Две встречные внутренние тени и дают глубину; одна, без ответной
/// подсветки, читается не как углубление, а как грязное пятно.
///
/// Тени именно `.shadow(.inner(…))`, а не собранные руками из размытых копий
/// контура. Руками выходит быстрее и заманчивее, но смещение там глобальное:
/// на верхе и низе кольца полоса горизонтальна и всё работает, а на боках она
/// вертикальна — тень едет вдоль канавки, и кольцо превращается в лежащую
/// поверх трубку. Внутренняя тень считается от границы самой фигуры, поэтому
/// на кольце, капсуле и любой другой форме ведёт себя одинаково правильно.
/// Пустая канавка как стиль заливки.
///
/// Отдельный тип, а не функция от `ColorScheme`, чтобы на месте вызова не
/// заводить `@Environment`. Экраны вроде «Плана» и «Активности» большие, и
/// каждое лишнее хранимое свойство там — это риск получить от компилятора
/// «unable to type-check in reasonable time» на ровном месте. `resolve(in:)`
/// сам достаёт тему из окружения в момент отрисовки.
struct ChannelStyle: ShapeStyle {
    var thickness: CGFloat = 9

    func resolve(in environment: EnvironmentValues) -> some ShapeStyle {
        Engraving.channel(for: environment.colorScheme, thickness: thickness)
    }
}

extension ShapeStyle where Self == ChannelStyle {
    /// Канавка: пустая часть любой полосы или кольца прогресса.
    static func channel(thickness: CGFloat = 9) -> ChannelStyle {
        ChannelStyle(thickness: thickness)
    }
}

enum Engraving {
    /// Пустая канавка: дно плюс стенки.
    ///
    /// В светлой теме дно темнее поверхности — так и выглядит углубление.
    /// В тёмной наоборот, светлее: фон там чёрный, темнее уже некуда, и дно,
    /// затемнённое ещё раз, просто исчезло бы. А канавку надо видеть целиком —
    /// по ней читается, сколько ещё осталось до цели.
    static func channel(for scheme: ColorScheme, thickness: CGFloat = 9) -> AnyShapeStyle {
        let floor: Color = scheme == .dark ? .white.opacity(0.08) : .black.opacity(0.12)
        let depth: Color = scheme == .dark ? .black.opacity(0.9) : .black.opacity(0.5)
        let light: Color = scheme == .dark ? .white.opacity(0.26) : .white.opacity(1)
        // Тени привязаны к толщине канавки, а не заданы числами: на кольце в 9
        // пунктов и на полосе в 4 одни и те же 3 пункта размытия дают совершенно
        // разное — во втором случае тень съедает канавку целиком.
        let wall = thickness / 3
        return AnyShapeStyle(
            floor
                .shadow(.inner(color: depth, radius: wall, x: 0, y: wall))
                .shadow(.inner(color: light, radius: wall * 0.7, x: 0, y: -wall * 0.7))
        )
    }

}

extension View {
    /// Свечение налитого цвета.
    ///
    /// Канавка прорезана в поверхности, но сам цвет в ней не камень: он светится
    /// и подсвечивает края. Рельеф на заливке — вторая тень поверх первой —
    /// выглядит честнее физически, но мертвее: цвет тускнеет и превращается
    /// в закрашенную канавку. Светится — живее, и это сознательный выбор
    /// в пользу вида, а не в пользу физики.
    func glowingFill(_ color: Color, thickness: CGFloat = 9) -> some View {
        shadow(color: color.opacity(0.45), radius: thickness * 0.55)
    }
}

/// Линейный прогресс в той же канавке, что кольцо и полосы.
///
/// Свой стиль, а не `.tint` поверх системного: системная полоса рисует трек
/// собственной заливкой, вклиниться в неё нечем. Цвет идёт параметром, потому
/// что внутри стиля системный tint не прочитать.
struct EngravedProgressViewStyle: ProgressViewStyle {
    let color: Color
    var thickness: CGFloat = 6

    func makeBody(configuration: Configuration) -> some View {
        Bar(value: configuration.fractionCompleted ?? 0, color: color, thickness: thickness)
    }

    private struct Bar: View {
        let value: Double
        let color: Color
        let thickness: CGFloat

        var body: some View {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.channel(thickness: thickness))
                    Capsule()
                        .fill(color)
                        // Ноль остаётся нулём: полоски-огрызка на пустом прогрессе
                        // быть не должно, иначе «ещё не начато» выглядит как «чуть-чуть».
                        .frame(width: max(0, geometry.size.width * min(max(value, 0), 1)))
                        .glowingFill(color, thickness: thickness)
                }
            }
            .frame(height: thickness)
        }
    }
}

extension ProgressViewStyle where Self == EngravedProgressViewStyle {
    static func engraved(_ color: Color, thickness: CGFloat = 6) -> EngravedProgressViewStyle {
        EngravedProgressViewStyle(color: color, thickness: thickness)
    }
}

/// Цвет пламени по длине серии. Пороги были продублированы в бейдже тулбара
/// и в hero-карточке «Активности» — при правке одного места они разъезжались.
enum StreakStyle {
    static func color(for streak: Int) -> Color {
        if streak >= 100 { return Color(red: 1, green: 0.75, blue: 0) }
        if streak >= 30 { return .red }
        if streak >= 7 { return .orange }
        return streak > 0 ? .orange : .secondary
    }
}

/// Цвет категории процента жира. Общий для экрана профиля и экрана замеров.
enum BodyFatStyle {
    static func color(for category: String) -> Color {
        switch category {
        case "Атлетический", "Фитнес": return .green
        case "Норма": return .yellow
        default: return .red
        }
    }
}
