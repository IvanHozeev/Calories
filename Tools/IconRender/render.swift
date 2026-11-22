// render.swift <html> <mode> <out.png>
// Loads the page in an offscreen WKWebView at 1024×1024 and writes a 1024-pixel PNG.
import AppKit
import WebKit

let args = CommandLine.arguments
let page = URL(fileURLWithPath: args[1])
let mode = args[2]
let out = URL(fileURLWithPath: args[3])

final class Renderer: NSObject, WKNavigationDelegate {
    let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 1024, height: 1024))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1024, height: 1024),
                          styleMask: [.borderless], backing: .buffered, defer: false)

    func start() {
        window.contentView = web
        // A page with no background of its own comes out transparent.
        web.setValue(false, forKey: "drawsBackground")
        web.navigationDelegate = self
        var parts = URLComponents(url: page, resolvingAgainstBaseURL: false)!
        parts.fragment = mode
        web.loadFileURL(parts.url!, allowingReadAccessTo: page.deletingLastPathComponent())
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Give the blurs a moment to settle before the picture is taken.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let config = WKSnapshotConfiguration()
            config.rect = NSRect(x: 0, y: 0, width: 1024, height: 1024)
            config.snapshotWidth = 1024
            webView.takeSnapshot(with: config) { image, error in
                guard let image, let tiff = image.tiffRepresentation,
                      let rep = NSBitmapImageRep(data: tiff) else {
                    print("snapshot failed: \(String(describing: error))"); exit(1)
                }
                let resized = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
                                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                               isPlanar: false, colorSpaceName: .deviceRGB,
                                               bytesPerRow: 0, bitsPerPixel: 0)!
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: resized)
                rep.draw(in: NSRect(x: 0, y: 0, width: 1024, height: 1024))
                NSGraphicsContext.restoreGraphicsState()
                try! resized.representation(using: .png, properties: [:])!.write(to: out)
                print("wrote \(out.path)")
                exit(0)
            }
        }
    }
}

let app = NSApplication.shared
let renderer = Renderer()
renderer.start()
app.run()
