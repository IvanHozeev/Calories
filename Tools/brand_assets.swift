import Foundation
import AppKit
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

// Знак Calories: «С» из трёх дуг — белки, жиры, углеводы. Незамкнутое кольцо макросов.
// Генерирует иконку (обычная, тёмная, tinted) и логотип лаунч-скрина (светлый и тёмный).
//
// Запуск из корня репозитория:
//   mkdir -p /tmp/brand && swift Tools/brand_assets.swift /tmp/brand
// Потом файлы разложить по Calories/Assets.xcassets/AppIcon.appiconset и LaunchLogo.imageset.

let out = URL(fileURLWithPath: CommandLine.arguments[1])
let space = CGColorSpace(name: CGColorSpace.displayP3)!

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [CGFloat((hex >> 16) & 0xFF) / 255,
                                            CGFloat((hex >> 8) & 0xFF) / 255, CGFloat(hex & 0xFF) / 255, a])!
}
func gray(_ v: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(colorSpace: space, components: [v, v, v, a])! }

/// Рисуем в 16 битах на канал: свечение и градиенты на тёмном графите в
/// 8 битах расходились ступенями-кольцами. Сохраняется уже в 8 бит — одним
/// переводом в конце ступеней почти не остаётся, в отличие от накопления на
/// каждом полупрозрачном слое.
func context(_ w: Int, _ h: Int, opaque: Bool) -> CGContext {
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

func linear(_ ctx: CGContext, _ colors: [CGColor], _ loc: [CGFloat], from: CGPoint, to: CGPoint) {
    ctx.drawLinearGradient(CGGradient(colorsSpace: space, colors: colors as CFArray, locations: loc)!,
                           start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}
func radial(_ ctx: CGContext, _ colors: [CGColor], center: CGPoint, radius: CGFloat) {
    ctx.drawRadialGradient(CGGradient(colorsSpace: space, colors: colors as CFArray, locations: [0, 1])!,
                           startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
}

func save(_ ctx: CGContext, _ name: String) {
    let dest = CGImageDestinationCreateWithURL(out.appendingPathComponent(name) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    let image = ctx.makeImage()!
    CGImageDestinationAddImage(dest, flatten(image, opaque: name.hasPrefix("AppIcon")), nil)
    CGImageDestinationFinalize(dest)
}

struct Part { let colors: [CGColor]; let glow: CGColor }
// Пары цветов близкие: цвет почти однотонный, объём даёт светотень, а не градиент.
let protein = Part(colors: [rgb(0x4C9BFF), rgb(0x2F7BFF)], glow: rgb(0x2F7BFF))
let fat = Part(colors: [rgb(0xFFA23D), rgb(0xFF8A1F)], glow: rgb(0xFF8A1F))
let carbs = Part(colors: [rgb(0xB85CFF), rgb(0xA63BFF)], glow: rgb(0xA63BFF))

/// Рисует «С» с центром и радиусом. Углы — от 12 часов по часовой.
/// Доли дуг как у кольца на «Сегодня» при типичной сушке на 80 кг:
/// углеводы 250 г, жиры 64 г, белки 160 г. Порядок тот же, что на кольце:
/// сверху вниз против часовой — углеводы, жиры, белки.
let grams: [CGFloat] = [250, 64, 160]
/// Поворот знака против часовой, в градусах.
/// 40° подобраны из 0/25/40/55: разрыв по диагонали вверх-вправо, знак ещё
/// читается кольцом, но уже не буквой. Переопределяется BRAND_ROTATION.
let rotation: CGFloat = CGFloat(Double(ProcessInfo.processInfo.environment["BRAND_ROTATION"] ?? "40") ?? 40)
let weights = grams.map { $0 / grams.reduce(0, +) }

func drawC(_ ctx: CGContext, center: CGPoint, radius: CGFloat, width: CGFloat,
           parts: [Part], glow: CGFloat, glowAlpha: CGFloat, grayscale: [CGFloat]? = nil, sheen: Bool = true,
           opening: CGFloat = 80, gap: CGFloat = 26, groove: Bool = false) {
    // Разрыв смотрит не прямо вправо, а повёрнут против часовой: так знак
    // читается скорее как полумесяц кольца, чем как буква «С».
    let top = 90 - rotation - opening / 2
    let bottom = 90 - rotation + opening / 2 - 360
    let available = top - bottom - gap * CGFloat(parts.count - 1)
    var cursor = top
    for (i, part) in parts.enumerated() {
        let share = available * weights[i]
        let end = cursor
        let start = end - share
        cursor = start - gap
        let a0 = (90 - start) * .pi / 180, a1 = (90 - end) * .pi / 180
        let arc = CGMutablePath()
        arc.addArc(center: center, radius: radius, startAngle: a0, endAngle: a1, clockwise: true)
        let path = arc.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 10)
        let colors = grayscale.map { [gray($0[i]), gray($0[i] * 0.8)] } ?? part.colors
        if groove {
            // Канавка, прорезанная в графите: шире дуги, тёмное дно, внутренняя
            // тень от верхней стенки, а свет ловит только нижняя кромка —
            // как у колец и полос в приложении.
            let cut = arc.copy(strokingWithWidth: width * 1.24, lineCap: .round, lineJoin: .round, miterLimit: 10)
            ctx.saveGState()
            ctx.translateBy(x: 0, y: -width * 0.035)
            ctx.addPath(cut); ctx.setFillColor(gray(1, 0.10)); ctx.fillPath()
            ctx.restoreGState()
            ctx.saveGState()
            ctx.addPath(cut); ctx.setFillColor(rgb(0x050506)); ctx.fillPath()
            ctx.restoreGState()
            ctx.saveGState()
            ctx.addPath(cut); ctx.clip()
            ctx.setShadow(offset: CGSize(width: 0, height: -width * 0.10), blur: width * 0.18, color: gray(0, 1))
            ctx.addRect(CGRect(x: -2000, y: -2000, width: 6000, height: 6000))
            ctx.addPath(cut)
            ctx.setFillColor(gray(0, 1))
            ctx.fillPath(using: .evenOdd)
            ctx.restoreGState()
        }
        if glow > 0 {
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: glow, color: part.glow.copy(alpha: glowAlpha)!)
            ctx.addPath(path); ctx.setFillColor(colors[0]); ctx.fillPath()
            ctx.restoreGState()
        }
        // Тень под дугой: она лежит над фоном, а не нарисована на нём.
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -width * 0.10), blur: width * 0.28, color: gray(0, sheen ? 0.45 : 0))
        ctx.addPath(path); ctx.setFillColor(colors[1]); ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addPath(path); ctx.clip()
        let p0 = CGPoint(x: center.x + cos(a0) * radius, y: center.y + sin(a0) * radius)
        let p1 = CGPoint(x: center.x + cos(a1) * radius, y: center.y + sin(a1) * radius)
        linear(ctx, colors, [0, 1], from: p0, to: p1)
        if sheen {
            // Выпуклость, как у значков Apple: дуга — трубка. Поперёк неё свет
            // гаснет к краям, сверху кольцо освещено, снизу в тени, а по
            // внешнему краю идёт тонкий блик.
            let inner = radius - width / 2, outer = radius + width / 2
            // Поперёк дуги: края чуть темнее середины — округлость без блика-полосы.
            ctx.drawRadialGradient(
                CGGradient(colorsSpace: space,
                           colors: [gray(0, 0.14), gray(1, 0.06), gray(1, 0.06), gray(0, 0.16)] as CFArray,
                           locations: [0, 0.35, 0.6, 1])!,
                startCenter: center, startRadius: inner, endCenter: center, endRadius: outer, options: [])
            // Сверху свет, снизу мягкая тень — как у значков Apple.
            // Блик слабый: сильный белил цвет, и дуги становились пастельными.
            linear(ctx, [gray(1, 0.16), gray(1, 0.0), gray(0, 0.0), gray(0, 0.14)], [0, 0.5, 0.62, 1],
                   from: CGPoint(x: 0, y: center.y + radius + width), to: CGPoint(x: 0, y: center.y - radius - width))
        }
        ctx.restoreGState()
    }
}

let parts = [carbs, fat, protein]

let S: CGFloat = 1024
let iconCenter = CGPoint(x: S / 2, y: S / 2)
/// Толщина «С» на иконке: 160 из 118/140/160/180. Тоньше знак выглядел
/// второстепенным, толще короткая жировая дуга превращалась в пятно.
/// Переопределяется ICON_WIDTH для подбора.
let iconWidth: CGFloat = CGFloat(Double(ProcessInfo.processInfo.environment["ICON_WIDTH"] ?? "160") ?? 160)
/// Внешний край знака: крупно по полю иконки, чтобы толстая «С» не сжималась внутрь.
let iconOuter = CGFloat(Double(ProcessInfo.processInfo.environment["ICON_OUTER"] ?? "385") ?? 385)
let iconRadius: CGFloat = iconOuter - iconWidth * 0.565

// MARK: - Иконка: «С», прорезанная в чёрном стекле
//
// Реалистично и серьёзно, но живым цветом. Стекло с зерном и косым отблеском,
// один свет сверху-слева и виньетка. «С» прорезана тонко: у прорези тёмная
// фаска сверху и светлая кромка снизу, внутри — утопленная эмаль, на которую
// край бросает тень, с мягким бликом и лёгким свечением.

/// Цвета эмали — живые, но не неон: неон на стекле выглядел игрушечно.
let enamel: [[CGColor]] = [
    [rgb(0xD67EFF), rgb(0xA93BF2)],
    [rgb(0xFFBC42), rgb(0xFF8214)],
    [rgb(0x5EB8FF), rgb(0x1C76FF)],
]

/// Середины трёх дуг «С» с долями как у кольца.
func iconSpines() -> [CGPath] {
    // Зазор от толщины: скруглённые концы толстой дуги съедали фиксированный
    // зазор, и дуги слипались. Нужна ширина прорези плюс четверть толщины воздуха.
    let gap = (iconWidth * 1.13 + iconWidth * 0.12) / iconRadius * 180 / .pi
    let opening = max(72, gap * 1.9)
    let top = 90 - rotation - opening / 2
    let bottom = 90 - rotation + opening / 2 - 360
    let available = top - bottom - gap * 2
    var cursor = top
    return (0..<3).map { i in
        let end = cursor, start = end - available * weights[i]
        cursor = start - gap
        let arc = CGMutablePath()
        arc.addArc(center: iconCenter, radius: iconRadius,
                   startAngle: (90 - start) * .pi / 180, endAngle: (90 - end) * .pi / 180, clockwise: true)
        return arc
    }
}

func outline(_ spine: CGPath, _ width: CGFloat) -> CGPath {
    spine.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 10)
}

/// Тень внутрь фигуры: от края вглубь, со смещением.
func innerShadow(_ ctx: CGContext, _ path: CGPath, dy: CGFloat, blur: CGFloat, alpha: CGFloat) {
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    ctx.setShadow(offset: CGSize(width: 0, height: dy), blur: blur, color: gray(0, alpha))
    ctx.addRect(CGRect(x: -4000, y: -4000, width: 9000, height: 9000))
    ctx.addPath(path)
    ctx.setFillColor(gray(0, 1))
    ctx.fillPath(using: .evenOdd)
    ctx.restoreGState()
}

/// Зерно стекла. Фиксированный генератор — иначе каждый прогон давал бы другую иконку.
func grain(strength: CGFloat) -> CGImage {
    let n = Int(S)
    var seed: UInt64 = 0x9E3779B97F4A7C15
    var px = [UInt8](repeating: 0, count: n * n * 4)
    for k in stride(from: 0, to: px.count, by: 4) {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        let g = UInt8(truncatingIfNeeded: seed >> 56)
        px[k] = g; px[k + 1] = g; px[k + 2] = g; px[k + 3] = UInt8(strength * 255)
    }
    return CGImage(width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: n * 4,
                   space: CGColorSpaceCreateDeviceRGB(),
                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                   provider: CGDataProvider(data: CFDataCreate(nil, px, px.count))!,
                   decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
}

func blackGlass(_ ctx: CGContext) {
    linear(ctx, [rgb(0x1A1A1E), rgb(0x050506)], [0, 1], from: CGPoint(x: 0, y: S), to: CGPoint(x: 0, y: 0))
    ctx.saveGState()
    ctx.setBlendMode(.softLight)
    ctx.draw(grain(strength: 0.06), in: CGRect(x: 0, y: 0, width: S, height: S))
    ctx.restoreGState()
    radial(ctx, [gray(1, 0.10), gray(1, 0)], center: CGPoint(x: S * 0.3, y: S), radius: S * 0.9)
    ctx.drawRadialGradient(CGGradient(colorsSpace: space, colors: [gray(0, 0), gray(0, 0.45)] as CFArray, locations: [0.55, 1])!,
                           startCenter: iconCenter, startRadius: 0, endCenter: iconCenter, endRadius: S * 0.75,
                           options: [.drawsAfterEndLocation])
}

func engravedMark(_ ctx: CGContext, glow: CGFloat) {
    let spines = iconSpines()
    let cutScale: CGFloat = 1.13
    let lip = iconWidth * (cutScale - 1) * 0.35
    for spine in spines {
        let cut = outline(spine, iconWidth * cutScale)
        ctx.saveGState(); ctx.translateBy(x: 0, y: -lip)
        ctx.addPath(cut); ctx.setFillColor(gray(1, 0.16)); ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState(); ctx.translateBy(x: 0, y: lip * 0.8)
        ctx.addPath(cut); ctx.setFillColor(gray(0, 0.5)); ctx.fillPath()
        ctx.restoreGState()
        ctx.addPath(cut); ctx.setFillColor(rgb(0x050506)); ctx.fillPath()
        innerShadow(ctx, cut, dy: -iconWidth * 0.06, blur: iconWidth * 0.10, alpha: 1)
    }
    for (index, spine) in spines.enumerated() {
        let colors = enamel[index]
        let fill = outline(spine, iconWidth)
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: glow, color: colors[1].copy(alpha: 0.55)!)
        ctx.addPath(fill); ctx.setFillColor(colors[1]); ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState(); ctx.addPath(fill); ctx.clip()
        linear(ctx, colors, [0, 1], from: CGPoint(x: 0, y: iconCenter.y + iconRadius + iconWidth),
               to: CGPoint(x: 0, y: iconCenter.y - iconRadius - iconWidth))
        ctx.restoreGState()
        innerShadow(ctx, fill, dy: -iconWidth * 0.06, blur: iconWidth * 0.09, alpha: 0.5)
        ctx.saveGState(); ctx.addPath(fill); ctx.clip()
        linear(ctx, [gray(1, 0.16), gray(1, 0)], [0, 1], from: CGPoint(x: 0, y: iconCenter.y + iconRadius + iconWidth),
               to: CGPoint(x: 0, y: iconCenter.y))
        ctx.restoreGState()
    }
}

do {
    let ctx = context(1024, 1024, opaque: true)
    blackGlass(ctx)
    engravedMark(ctx, glow: 34)
    save(ctx, "AppIcon-light.png")
}
// Тёмная: то же стекло, эмаль светится чуть сильнее.
do {
    let ctx = context(1024, 1024, opaque: true)
    blackGlass(ctx)
    engravedMark(ctx, glow: 46)
    save(ctx, "AppIcon-dark.png")
}
// Tinted: оттенки серого на чёрном, цвет даёт система.
do {
    let ctx = context(1024, 1024, opaque: true)
    ctx.setFillColor(gray(0)); ctx.fill(CGRect(x: 0, y: 0, width: S, height: S))
    drawC(ctx, center: iconCenter, radius: 300, width: 118, parts: parts, glow: 0, glowAlpha: 0,
          grayscale: [1, 0.9, 0.8], sheen: false)
    save(ctx, "AppIcon-tinted.png")
}

// Лаунч-скрин: одна «С», без названия, того же размера и толщины, что кольцо
// на «Сегодня» (230 pt, дуга 18 pt), прорезанная в чёрном стекле эмалью иконки.
// Фон — сплошное чёрное стекло из LaunchBackground (градиент лаунч-скрин не умеет). Следом её сменяет такая же анимированная (SplashView).
// 270×270 pt: знак 230 pt в поперечнике, остальное — поле под свечение.
func launch(scale: CGFloat, dark: Bool, name: String) {
    let side = 270 * scale
    let ctx = context(Int(side), Int(side), opaque: false)
    let diameter = 230 * scale
    let width = 18 * scale
    drawC(ctx, center: CGPoint(x: side / 2, y: side / 2), radius: (diameter - width) / 2, width: width,
          parts: enamel.map { Part(colors: $0, glow: $0[1]) }, glow: width * 0.6, glowAlpha: 0.4,
          sheen: false, opening: 60, gap: 16, groove: true)
    save(ctx, name)
}
for (scale, suffix) in [(1.0, ""), (2.0, "@2x"), (3.0, "@3x")] {
    launch(scale: scale, dark: false, name: "LaunchLogo\(suffix).png")
    launch(scale: scale, dark: true, name: "LaunchLogo-dark\(suffix).png")
}
