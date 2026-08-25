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
