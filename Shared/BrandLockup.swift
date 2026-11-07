import SwiftUI

/// Размеры знака с названием — для лаунч-скрина и заставки.
///
/// Заставка продолжает лаунч-скрин: её первый кадр обязан совпасть с ним до
/// точки, иначе на запуске видно подмену. Один раз они уже разошлись — на
/// картинку добавили название, а заставка осталась с прежним кольцом на 150
/// и без надписи, и сквозь неё просвечивал серый призрак слова с кадра под
/// ней.
///
/// Поэтому числа лежат здесь, а не в каждом месте свои. Второй их экземпляр —
/// в `Tools/brand_assets.swift`, который рисует саму картинку: скрипт живёт
/// вне таргета и импортировать это не может. Менять только вместе.
enum BrandLockup {
    static let markSize: CGFloat = 96
    static let titleSize: CGFloat = 28
    /// Просвет между кольцом и словом — как в подписи внизу настроек.
    static let gap: CGFloat = markSize * 4 / 22
    /// Серый, а не чёрный: на запуске знак главный, название под ним — подпись.
    static let ink = Color(red: 0x8E / 255, green: 0x8E / 255, blue: 0x93 / 255)
    /// Шрифт приложения прямым именем, а не через выбор человека: картинка
    /// лаунч-скрина нарисована именно им, и заставка обязана совпасть.
    ///
    /// Имя — то единственное, под которым система знает подключённый файл.
    /// Nunito у нас изменчивый, одним файлом на все веса, и под своим именем
    /// он зарегистрирован ровно одним — `Nunito-ExtraLight`, как называется
    /// его начертание по умолчанию. Имена вроде `Nunito-SemiBold` живут
    /// внутри файла как именованные экземпляры, но наружу их система не
    /// отдаёт: `Font.custom` такое имя не находит и молча берёт системный
    /// шрифт. Так заставка и разошлась с лаунч-скрином — на одном Nunito, на
    /// другом SF Pro, и это было видно глазом.
    static let font = "Nunito-ExtraLight"
    /// Вес, которым набрано название. Задаётся осью изменчивого шрифта —
    /// именем его не выбрать, см. выше. Тем же весом рисует картинку
    /// `Tools/brand_assets.swift`.
    static let titleWeight: CGFloat = 600
}

#if canImport(UIKit)
import UIKit

extension UIFont {
    /// Nunito нужного веса: имя даёт файл, вес — ось `wght`.
    ///
    /// Четырёхбуквенный тег оси — то же самое число, которым его записывают
    /// в шрифте: `wght` байтами и есть этот идентификатор.
    static func brandNunito(size: CGFloat, weight: CGFloat = BrandLockup.titleWeight) -> UIFont {
        let base = UIFont(name: BrandLockup.font, size: size) ?? .systemFont(ofSize: size)
        let weightAxis = 0x77676874
        let descriptor = base.fontDescriptor.addingAttributes([
            UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): [weightAxis: weight]
        ])
        return UIFont(descriptor: descriptor, size: size)
    }
}

extension Font {
    /// Название приложения на заставке — тем же шрифтом и весом, что на
    /// картинке лаунч-скрина.
    static var brandTitle: Font {
        Font(UIFont.brandNunito(size: BrandLockup.titleSize))
    }
}
#endif
