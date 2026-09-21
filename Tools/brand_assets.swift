import Foundation
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Знак Calories: «С» из трёх дуг — углеводы, жиры, белки. Незамкнутое кольцо макросов.
// Генерирует иконку (светлая, тёмная, tinted), логотип лаунч-скрина и иконку
// вкладки «Сегодня».
//
// Запуск из корня репозитория:
//   mkdir -p /tmp/brand && swift Tools/brand_assets.swift /tmp/brand
// Потом файлы разложить по Calories/Assets.xcassets: AppIcon.appiconset,
// LaunchLogo.imageset и TodayTab.imageset.
//
// Вайб — лёгкость и свежесть: плоские дуги цветами кольца «Сегодня» на светлом
// поле, без стекла, канавок и свечения. Прежний знак, прорезанный в чёрном
// стекле, спорил с приложением, которое стало светлым и тихим.

let out = URL(fileURLWithPath: CommandLine.arguments[1])
let space = CGColorSpace(name: CGColorSpace.displayP3)!

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [CGFloat((hex >> 16) & 0xFF) / 255,
                                            CGFloat((hex >> 8) & 0xFF) / 255, CGFloat(hex & 0xFF) / 255, a])!
}
func gray(_ v: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(colorSpace: space, components: [v, v, v, a])! }

/// Рисуем в 16 битах на канал: плавные градиенты фона в 8 битах расходились
/// ступенями. Сохраняется уже в 8 бит одним переводом в конце.
func context(_ w: Int, _ h: Int) -> CGContext {
    CGContext(data: nil, width: w, height: h, bitsPerComponent: 16, bytesPerRow: 0, space: space,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder16Little.rawValue)!
}

/// Непрозрачные картинки (иконка) сводятся к 8 битам без альфа-канала:
/// App Store не принимает иконки с прозрачностью.
func flatten(_ image: CGImage, opaque: Bool) -> CGImage {
    let info = opaque ? CGImageAlphaInfo.noneSkipLast.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue
    let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: info)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return ctx.makeImage()!
}

func save(_ ctx: CGContext, _ name: String) {
    let dest = CGImageDestinationCreateWithURL(out.appendingPathComponent(name) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, flatten(ctx.makeImage()!, opaque: name.hasPrefix("AppIcon")), nil)
    CGImageDestinationFinalize(dest)
}

func linear(_ ctx: CGContext, _ colors: [CGColor], from: CGPoint, to: CGPoint) {
    ctx.drawLinearGradient(CGGradient(colorsSpace: space, colors: colors as CFArray, locations: [0, 1])!,
                           start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

/// Цвета дуг кольца «Сегодня» (ProgressRing): иконка и приложение одного цвета.
/// Сверху вниз против часовой — углеводы, жиры, белки, как на кольце.
let palette: [[CGColor]] = [
    [rgb(0xB85CFF), rgb(0xA63BFF)],
    [rgb(0xFFA23D), rgb(0xFF8A1F)],
    [rgb(0x4C9BFF), rgb(0x2F7BFF)],
]
/// Доли дуг как у типичной сушки на 80 кг: углеводы 250 г, жиры 64 г, белки 160 г.
let grams: [CGFloat] = [250, 64, 160]
let weights = grams.map { $0 / grams.reduce(0, +) }
/// Разрыв повёрнут на 40° против часовой: знак читается кольцом, а не буквой.
let rotation: CGFloat = 40

let S: CGFloat = 1024
let iconCenter = CGPoint(x: S / 2, y: S / 2)

/// Середины трёх дуг. `outer` — внешний край знака, `width` — толщина дуги.
/// Зазор от толщины: скруглённые концы съедали бы фиксированный зазор.
func spines(width: CGFloat, outer: CGFloat) -> [CGPath] {
    let radius = outer - width / 2
    let gap = width * 1.25 / radius * 180 / .pi
    let opening = max(72, gap * 1.9)
    let top = 90 - rotation - opening / 2
    let available = 360 - opening - gap * 2
    var cursor = top
    return (0..<3).map { i in
        let end = cursor, start = end - available * weights[i]
        cursor = start - gap
        let arc = CGMutablePath()
        arc.addArc(center: iconCenter, radius: radius,
                   startAngle: (90 - start) * .pi / 180, endAngle: (90 - end) * .pi / 180, clockwise: true)
        return arc
    }
}

func outline(_ spine: CGPath, _ width: CGFloat) -> CGPath {
    spine.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 10)
}

/// Плоская «С»: у каждой дуги лёгкий градиент своей пары по диагонали, и всё.
func freshMark(_ ctx: CGContext, width: CGFloat, outer: CGFloat, grayscale: [CGFloat]? = nil) {
    for (index, spine) in spines(width: width, outer: outer).enumerated() {
        let shape = outline(spine, width)
        let colors = grayscale.map { [gray($0[index]), gray($0[index])] } ?? palette[index]
        ctx.saveGState()
        ctx.addPath(shape); ctx.clip()
        let bounds = shape.boundingBoxOfPath
        linear(ctx, colors, from: CGPoint(x: bounds.minX, y: bounds.maxY), to: CGPoint(x: bounds.maxX, y: bounds.minY))
        ctx.restoreGState()
    }
}

/// Подмешать белого к цвету — для едва заметного перехода внутри дуги.
func shade(_ color: CGColor, _ amount: CGFloat) -> CGColor {
    let c = color.components ?? [0, 0, 0, 1]
    func mix(_ v: CGFloat) -> CGFloat { v + (1 - v) * amount }
    return CGColor(colorSpace: space, components: [mix(c[0]), mix(c[1]), mix(c[2]), c.count > 3 ? c[3] : 1])!
}

/// Знак в стиле иконок Google (Gemini, Maps, Photos): плоско и чисто.
///
/// Их приёмы, снятые с самих иконок: чисто белое поле без градиента; ни тени,
/// ни блика — ни одного; каждая часть своего цвета, внутри почти ровного, с
/// едва заметным переходом вдоль формы; концы скруглены; знак крупный и
/// занимает большую часть поля. Объём там берётся не от света, а от плотной
/// формы и насыщенного цвета — стоит добавить блик, и иконка сразу читается
/// как глянец из 2010-го, а не как их.
func googleMark(_ ctx: CGContext, width: CGFloat, outer: CGFloat, grayscale: [CGFloat]? = nil) {
    for (index, spine) in spines(width: width, outer: outer).enumerated() {
        let shape = outline(spine, width)
        let bounds = shape.boundingBoxOfPath
        ctx.saveGState()
        ctx.addPath(shape); ctx.clip()
        if let grayscale {
            ctx.setFillColor(gray(grayscale[index]))
            ctx.fill(bounds)
        } else {
            // Переход внутри дуги едва заметный: у них цвет почти ровный, и
            // сильный градиент сразу выдаёт чужую руку.
            let pair = palette[index]
            linear(ctx, [shade(pair[0], 0.06), pair[1]],
                   from: CGPoint(x: bounds.minX, y: bounds.maxY), to: CGPoint(x: bounds.maxX, y: bounds.minY))
        }
        ctx.restoreGState()
    }
}

// MARK: - Иконка

/// Толщина и размер «С» на иконке: крупно, но с воздухом до краёв.
let iconWidth: CGFloat = 120
let iconOuter: CGFloat = 372

// Светлая: белое поле, чуть сереющее книзу.
do {
    let ctx = context(1024, 1024)
    ctx.setFillColor(gray(1)); ctx.fill(CGRect(x: 0, y: 0, width: S, height: S))
    googleMark(ctx, width: iconWidth, outer: iconOuter)
    save(ctx, "AppIcon-light.png")
}
// Тёмная: то же на почти чёрном поле — как тёмная тема приложения.
do {
    let ctx = context(1024, 1024)
    linear(ctx, [rgb(0x1C1C1F), rgb(0x0A0A0B)], from: CGPoint(x: 0, y: S), to: CGPoint(x: 0, y: 0))
    googleMark(ctx, width: iconWidth, outer: iconOuter)
    save(ctx, "AppIcon-dark.png")
}
// Tinted: оттенки серого на чёрном, цвет даёт система.
do {
    let ctx = context(1024, 1024)
    ctx.setFillColor(gray(0)); ctx.fill(CGRect(x: 0, y: 0, width: S, height: S))
    googleMark(ctx, width: iconWidth, outer: iconOuter, grayscale: [1, 0.85, 0.7])
    save(ctx, "AppIcon-tinted.png")
}

// MARK: - Лаунч-скрин

// Та же «С» размером с кольцо «Сегодня» (230 pt) на холсте 270 pt, но тоньше
// иконки: на весь экран толщина иконки тяжелела. Фон — LaunchBackground,
// заставка (SplashView) продолжает этот кадр тем же знаком. Картинка одна на
// обе темы: плоские дуги одинаково читаются на светлом и на чёрном.
let launchMarkWidth: CGFloat = 90

func launch(scale: CGFloat, name: String) {
    let side = 270 * scale
    let ctx = context(Int(side), Int(side))
    let factor = (230 * scale) / (2 * iconOuter)
    ctx.translateBy(x: side / 2, y: side / 2)
    ctx.scaleBy(x: factor, y: factor)
    ctx.translateBy(x: -iconCenter.x, y: -iconCenter.y)
    freshMark(ctx, width: launchMarkWidth, outer: iconOuter)
    save(ctx, name)
}
for (scale, suffix) in [(1.0, ""), (2.0, "@2x"), (3.0, "@3x")] {
    launch(scale: scale, name: "LaunchLogo\(suffix).png")
}

// MARK: - Иконка вкладки «Сегодня»

// Та же «С», одноцветным шаблоном — цвет выбранной и невыбранной вкладки даёт
// система. Вектором в PDF, 28×28 pt, как ячейка системного символа в таббаре.
// Тоньше иконки (около 3,7 pt): при толщине иконки дуги спорили весом с
// соседними символами.
do {
    let tabSide: CGFloat = 28
    let tabWidth: CGFloat = 105
    let factor = (tabSide / 2 - 1) / iconOuter
    var box = CGRect(x: 0, y: 0, width: tabSide, height: tabSide)
    let ctx = CGContext(out.appendingPathComponent("TodayTab.pdf") as CFURL, mediaBox: &box, nil)!
    ctx.beginPDFPage(nil)
    ctx.translateBy(x: tabSide / 2, y: tabSide / 2)
    ctx.scaleBy(x: factor, y: factor)
    ctx.translateBy(x: -iconCenter.x, y: -iconCenter.y)
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))
    for spine in spines(width: tabWidth, outer: iconOuter) {
        ctx.addPath(outline(spine, tabWidth))
        ctx.fillPath()
    }
    ctx.endPDFPage()
    ctx.closePDF()
}
