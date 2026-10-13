import SwiftUI
import UIKit

/// Шрифт приложения — и в шапке тоже.
///
/// Заголовок экрана рисует UIKit, а не SwiftUI, и до него не доходит ни
/// `.fontDesign` с корня дерева, ни тем более подключённый файл Nunito:
/// человек выбирал засечки, видел их везде — и ровно там, где надпись самая
/// крупная, оставался системный шрифт. Начертание приходится отдать
/// навигационной панели отдельно, на её языке.
///
/// Трогаем только шрифт заголовка. Собственный `UINavigationBarAppearance`
/// со своим фоном здесь означал бы заодно отнять у панели стекло, которое
/// система рисует сама.
@MainActor
enum NavigationBarFont {

    /// Применить выбранное начертание ко всем шапкам: и к будущим, и к тем,
    /// что уже на экране.
    ///
    /// Прокси `appearance()` действует только на панели, которых ещё нет, —
    /// поэтому после смены шрифта в настройках живую шапку приходится
    /// догонять отдельно, иначе она останется старой до перезапуска.
    static func apply() {
        let inline = font(size: 17, weight: .semibold, textStyle: .headline)
        let large = font(size: 34, weight: .bold, textStyle: .largeTitle)

        let proxy = UINavigationBar.appearance()
        proxy.titleTextAttributes = [.font: inline]
        proxy.largeTitleTextAttributes = [.font: large]

        for bar in liveNavigationBars() {
            for appearance in [bar.standardAppearance, bar.scrollEdgeAppearance, bar.compactAppearance] {
                appearance?.titleTextAttributes[.font] = inline
                appearance?.largeTitleTextAttributes[.font] = large
            }
            bar.setNeedsLayout()
        }
    }

    /// Шрифт заголовка под выбранное начертание, масштабируемый вместе
    /// с системным размером текста — как и всё остальное в приложении.
    private static func font(size: CGFloat, weight: UIFont.Weight, textStyle: UIFont.TextStyle) -> UIFont {
        let base: UIFont
        if let name = AppFont.customName(for: weight.appWeight),
           let custom = UIFont(name: name, size: size) {
            base = custom
        } else {
            let system = UIFont.systemFont(ofSize: size, weight: weight)
            if let design = AppFont.current.uiDesign,
               let descriptor = system.fontDescriptor.withDesign(design) {
                base = UIFont(descriptor: descriptor, size: size)
            } else {
                base = system
            }
        }
        return UIFontMetrics(forTextStyle: textStyle).scaledFont(for: base)
    }

    /// Шапки, которые сейчас на экране.
    private static func liveNavigationBars() -> [UINavigationBar] {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .flatMap { bars(in: $0) }
    }

    private static func bars(in view: UIView) -> [UINavigationBar] {
        if let bar = view as? UINavigationBar { return [bar] }
        return view.subviews.flatMap { bars(in: $0) }
    }
}

extension UIFont.Weight {
    /// Тот же вес на языке SwiftUI: имена начертаний подключённого шрифта
    /// живут в `AppFont`, и спрашивают их там именно так.
    var appWeight: Font.Weight {
        switch self {
        case .bold:     return .bold
        case .semibold: return .semibold
        case .medium:   return .medium
        case .light:    return .light
        case .heavy:    return .heavy
        case .black:    return .black
        default:        return .regular
        }
    }
}

extension AppFont {
    /// Системное начертание на языке UIKit. У Nunito его нет — там свой файл.
    var uiDesign: UIFontDescriptor.SystemDesign? {
        switch self {
        case .system:     return .default
        case .rounded:    return .rounded
        case .serif:      return .serif
        case .monospaced: return .monospaced
        case .nunito:     return nil
        }
    }
}
