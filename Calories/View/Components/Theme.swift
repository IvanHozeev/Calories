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
            // Тень плотная и близкая: широкий мягкий радиус на светлом фоне читается
            // не как объём, а как серая подложка вокруг карточки.
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.40 : 0.06), radius: 6, y: 2)
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
