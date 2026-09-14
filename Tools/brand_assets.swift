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

func context(_ w: Int, _ h: Int, opaque: Bool) -> CGContext {
    let info = opaque ? CGImageAlphaInfo.noneSkipLast.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue
    return CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: info)!
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
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
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
// На иконке цвета ярче и светлее, чем в приложении: фон там сам фиолетово-синий,
// и дуги родных оттенков тонули в нём. Белок уходит к голубому, углеводы к
// розово-сиреневому, жир к солнечному — каждая дуга отделяется от фона.
let iconParts = [
    Part(colors: [rgb(0xD94DFF), rgb(0xB322FF)], glow: rgb(0xC43BFF)),
    Part(colors: [rgb(0xFFB300), rgb(0xFF7A00)], glow: rgb(0xFF9500)),
    Part(colors: [rgb(0x1FC8FF), rgb(0x0A84FF)], glow: rgb(0x14A8FF)),
]
let S: CGFloat = 1024
let iconCenter = CGPoint(x: S / 2, y: S / 2)

// Графит — тот же материал, что карточки приложения: знак прорезан в
// поверхности канавками, а заливка в них светится. Фон не декоративный
// градиент, а поверхность, из которой сделан интерфейс.
func graphite(_ ctx: CGContext, dark: Bool) {
    linear(ctx, dark ? [rgb(0x0B0B0D), rgb(0x1C1C20)] : [rgb(0x141417), rgb(0x2E2E34)], [0, 1],
           from: CGPoint(x: 0, y: 0), to: CGPoint(x: 0, y: S))
    // Мягкий свет сверху, как на матовом металле.
    radial(ctx, [gray(1, dark ? 0.05 : 0.08), gray(1, 0)], center: CGPoint(x: S * 0.5, y: S * 0.95), radius: S * 0.85)
}

do {
    let ctx = context(1024, 1024, opaque: true)
    graphite(ctx, dark: false)
    drawC(ctx, center: iconCenter, radius: 300, width: 118, parts: iconParts, glow: 22, glowAlpha: 0.8,
          sheen: false, groove: true)
    save(ctx, "AppIcon-light.png")
}
// Тёмная: тот же графит, чуть глубже, свечение сильнее.
do {
    let ctx = context(1024, 1024, opaque: true)
    graphite(ctx, dark: true)
    drawC(ctx, center: iconCenter, radius: 300, width: 118, parts: iconParts, glow: 34, glowAlpha: 0.9,
          sheen: false, groove: true)
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
// на «Сегодня» (230 pt, дуга 18 pt), прорезанная в графите, как на иконке.
// Фон — сплошной графит из LaunchBackground (градиент лаунч-скрин не умеет). Следом её сменяет такая же анимированная (SplashView).
// 270×270 pt: знак 230 pt в поперечнике, остальное — поле под свечение.
func launch(scale: CGFloat, dark: Bool, name: String) {
    let side = 270 * scale
    let ctx = context(Int(side), Int(side), opaque: false)
    let diameter = 230 * scale
    let width = 18 * scale
    drawC(ctx, center: CGPoint(x: side / 2, y: side / 2), radius: (diameter - width) / 2, width: width,
          parts: parts, glow: width * 0.6, glowAlpha: 0.35, sheen: false, opening: 60, gap: 16, groove: true)
    save(ctx, name)
}
for (scale, suffix) in [(1.0, ""), (2.0, "@2x"), (3.0, "@3x")] {
    launch(scale: scale, dark: false, name: "LaunchLogo\(suffix).png")
    launch(scale: scale, dark: true, name: "LaunchLogo-dark\(suffix).png")
}
