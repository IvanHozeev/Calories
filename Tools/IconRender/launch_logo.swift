// launch_logo.swift <mark.png> <markdark.png> <out-dir>
//
// Лаунч-картинка с резиновым знаком: знак и слово «Calories» под ним, тем же размером
// и тем же шрифтом, что у заставки (`BrandLockup` в Shared). Пишет LaunchLogo*.png для
// светлой темы и LaunchLogoDark*.png для тёмной, по три плотности.
//
// Запуск из корня репозитория:
//   swiftc -O Tools/IconRender/launch_logo.swift -o /tmp/launch-logo
//   /tmp/launch-logo /tmp/1-mark.png /tmp/1-markdark.png Calories/Assets.xcassets/LaunchLogo.imageset
//
// Числа — те же, что в `Tools/brand_assets.swift` и `BrandLockup`: заставка продолжает эту
// картинку, и разойтись им нельзя.
import Foundation
import AppKit
import CoreGraphics
import ImageIO
import CoreText
import UniformTypeIdentifiers

let args = CommandLine.arguments
let markLight = URL(fileURLWithPath: args[1])
let markDark = URL(fileURLWithPath: args[2])
let out = URL(fileURLWithPath: args[3])

let space = CGColorSpace(name: CGColorSpace.displayP3)!

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [CGFloat((hex >> 16) & 0xFF) / 255,
                                            CGFloat((hex >> 8) & 0xFF) / 255, CGFloat(hex & 0xFF) / 255, a])!
}

/// Кольцо знака занимает столько от ширины картинки знака (внешний радиус 380 из 512).
/// Тот же множитель — `RubberSign.ringShare` в приложении.
let ringShare: CGFloat = 0.7431
/// Кольцо — 96 пунктов от края до края, как было у плоского знака.
let markSize: CGFloat = 96
let titleSize: CGFloat = 28
let gap: CGFloat = markSize * 4 / 22

func image(_ url: URL) -> CGImage {
    CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(url as CFURL, nil)!, 0, nil)!
}

func launch(mark: URL, scale: CGFloat, name: String) {
    let plain = NSFont.systemFont(ofSize: titleSize, weight: .semibold)
    let font = (plain.fontDescriptor.withDesign(.rounded)
                .flatMap { NSFont(descriptor: $0, size: titleSize) } ?? plain) as CTFont
    let line = CTLineCreateWithAttributedString(NSAttributedString(
        string: "Calories", attributes: [.font: font, .foregroundColor: rgb(0x8E8E93)]))
    let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)

    let width = max(bounds.width + 32, markSize + 32)
    let height = markSize + gap + bounds.height
    let ctx = CGContext(data: nil, width: Int((width * scale).rounded(.up)), height: Int((height * scale).rounded(.up)),
                        bitsPerComponent: 16, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder16Little.rawValue)!
    ctx.scaleBy(x: scale, y: scale)

    // Картинка знака шире самого кольца: вокруг него поле под объём и тень. Кольцо стоит там
    // же, где стояло плоское: по центру квадрата в `markSize`.
    let side = markSize / ringShare
    let centre = CGPoint(x: width / 2, y: height - markSize / 2)
    ctx.draw(image(mark), in: CGRect(x: centre.x - side / 2, y: centre.y - side / 2, width: side, height: side))

    ctx.textPosition = CGPoint(x: (width - bounds.width) / 2 - bounds.origin.x,
                               y: height - markSize - gap - bounds.height - bounds.origin.y)
    CTLineDraw(line, ctx)

    let dest = CGImageDestinationCreateWithURL(out.appendingPathComponent(name) as CFURL,
                                               UTType.png.identifier as CFString, 1, nil)!
    let flat = CGContext(data: nil, width: ctx.width, height: ctx.height, bitsPerComponent: 8, bytesPerRow: 0,
                         space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    flat.draw(ctx.makeImage()!, in: CGRect(x: 0, y: 0, width: ctx.width, height: ctx.height))
    CGImageDestinationAddImage(dest, flat.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
    print("wrote \(name) \(ctx.width)x\(ctx.height)")
}

for (scale, suffix) in [(1.0, ""), (2.0, "@2x"), (3.0, "@3x")] {
    launch(mark: markLight, scale: scale, name: "LaunchLogo\(suffix).png")
    launch(mark: markDark, scale: scale, name: "LaunchLogoDark\(suffix).png")
}
