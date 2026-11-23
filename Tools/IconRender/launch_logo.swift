// launch_logo.swift <mark.png> <markdark.png> <out-dir>
//
// Лаунч-картинка: одно резиновое кольцо знака, без слова. Название приложения на запуске
// не пишется; внизу экрана стоит подпись «from Vanya Hozeyev» (`footer.swift`). Пишет
// LaunchLogo*.png для светлой темы и LaunchLogoDark*.png для тёмной, по три плотности.
//
// Картинка квадратная, кольцо в ней по центру: на экране она встаёт в центр, и кольцо
// оказывается ровно посередине.
//
// Запуск из корня репозитория:
//   swiftc -O Tools/IconRender/launch_logo.swift -o /tmp/launch-logo
//   /tmp/launch-logo /tmp/1-mark.png /tmp/1-markdark.png Calories/Assets.xcassets/LaunchLogo.imageset
//
// Числа — те же, что в `BrandLockup` и `RubberSign.ringShare`: заставка продолжает эту
// картинку, и разойтись им нельзя.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
let markLight = URL(fileURLWithPath: args[1])
let markDark = URL(fileURLWithPath: args[2])
let out = URL(fileURLWithPath: args[3])

let space = CGColorSpace(name: CGColorSpace.displayP3)!

/// Кольцо знака занимает столько от ширины картинки знака (внешний радиус 380 из 512).
/// Тот же множитель — `RubberSign.ringShare` в приложении.
let ringShare: CGFloat = 0.7431
/// Кольцо — 96 пунктов от края до края, как было у плоского знака.
let markSize: CGFloat = 96

func image(_ url: URL) -> CGImage {
    CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(url as CFURL, nil)!, 0, nil)!
}

func launch(mark: URL, scale: CGFloat, name: String) {
    // Картинка знака шире самого кольца: вокруг него поле под объём и тень.
    let side = markSize / ringShare
    let px = Int((side * scale).rounded(.up))
    let ctx = CGContext(data: nil, width: px, height: px,
                        bitsPerComponent: 16, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder16Little.rawValue)!
    ctx.draw(image(mark), in: CGRect(x: 0, y: 0, width: px, height: px))

    let dest = CGImageDestinationCreateWithURL(out.appendingPathComponent(name) as CFURL,
                                               UTType.png.identifier as CFString, 1, nil)!
    let flat = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                         space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    flat.draw(ctx.makeImage()!, in: CGRect(x: 0, y: 0, width: px, height: px))
    CGImageDestinationAddImage(dest, flat.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
    print("wrote \(name) \(px)x\(px)")
}

for (scale, suffix) in [(1.0, ""), (2.0, "@2x"), (3.0, "@3x")] {
    launch(mark: markLight, scale: scale, name: "LaunchLogo\(suffix).png")
    launch(mark: markDark, scale: scale, name: "LaunchLogoDark\(suffix).png")
}
