// Renders the line at the foot of the launch screen, the way the apps of a company carry
// its name: a small "from" over the author, in SF Rounded, the name filled with the three
// colours of the ring of the icon (lilac → coral → aqua). A storyboard cannot ask for the rounded
// design or a gradient, so the line is a picture.
//
//   swiftc -o /tmp/footer Tools/IconRender/footer.swift && /tmp/footer <out.png>
//
// Prints the size in points; the picture is drawn at 3x.

import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "LaunchFooter.png"
let scale: CGFloat = 3
let pad: CGFloat = 4

func rounded(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size * scale, weight: weight)
    guard let d = base.fontDescriptor.withDesign(.rounded) else { return base }
    return NSFont(descriptor: d, size: size * scale) ?? base
}
func color(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: 1)
}

let from = NSAttributedString(string: "from", attributes: [
    .font: rounded(14, .medium), .foregroundColor: NSColor(cgColor: color(0x8D91A3))!, .kern: 0.3 * scale,
])
let name = NSAttributedString(string: "Vanya Hozeyev", attributes: [
    .font: rounded(21, .bold), .foregroundColor: NSColor.black, .kern: 0.3 * scale,
])
let gap: CGFloat = 1 * scale
let width = Int(ceil(max(from.size().width, name.size().width) + 2 * pad * scale))
let height = Int(ceil(from.size().height + gap + name.size().height + 2 * pad * scale))

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
// The name first, alone, so the gradient can be poured into exactly its letters.
name.draw(at: CGPoint(x: (CGFloat(width) - name.size().width) / 2, y: pad * scale))
NSGraphicsContext.restoreGraphicsState()

let gradient = CGGradient(colorsSpace: space,
                          colors: [color(0xB26DFF), color(0xFF7F42), color(0x06BCDC)] as CFArray,
                          locations: [0, 0.5, 1])!
ctx.setBlendMode(.sourceAtop)
let nameLeft = (CGFloat(width) - name.size().width) / 2
ctx.drawLinearGradient(gradient, start: CGPoint(x: nameLeft, y: 0),
                       end: CGPoint(x: nameLeft + name.size().width, y: 0), options: [])
ctx.setBlendMode(.normal)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
from.draw(at: CGPoint(x: (CGFloat(width) - from.size().width) / 2,
                      y: pad * scale + name.size().height + gap))
NSGraphicsContext.restoreGraphicsState()

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("points: \(Double(width) / Double(scale)) x \(Double(height) / Double(scale))  (px \(width) x \(height))")
