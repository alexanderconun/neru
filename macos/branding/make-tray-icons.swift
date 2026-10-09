// Renders the Homekey menu bar glyphs: a keycap with an H, black on transparent.
// macOS draws them as template images, so only the alpha channel matters.
// Run from the repo root:
//   swift macos/branding/make-tray-icons.swift /tmp/active.png /tmp/paused.png
//   just generate-tray-icons /tmp/active.png /tmp/paused.png
import AppKit

/// Draws at the menu bar's 44px (22pt @2x) with every edge on a whole pixel;
/// rendering larger lets the recipe's `sips -z 44 44` resample blur the edges.
func render(letterAlpha: CGFloat, to path: String) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 44, pixelsHigh: 44,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: 44, height: 44)
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Keycap outline: thin top and sides, a thicker bottom lip.
    let cap = NSBezierPath(roundedRect: NSRect(x: 5, y: 5, width: 34, height: 34), xRadius: 8, yRadius: 8)
    cap.append(NSBezierPath(roundedRect: NSRect(x: 8, y: 11, width: 28, height: 25), xRadius: 5, yRadius: 5))
    cap.windingRule = .evenOdd
    NSColor.black.setFill()
    cap.fill()

    // The H as three bars rather than a font glyph, so it stays crisp at 22pt.
    let letter = NSBezierPath()
    for bar in [NSRect(x: 16, y: 17, width: 3, height: 13),
                NSRect(x: 25, y: 17, width: 3, height: 13),
                NSRect(x: 19, y: 22, width: 6, height: 3)] {
        letter.append(NSBezierPath(rect: bar))
    }
    NSColor.black.withAlphaComponent(letterAlpha).setFill()
    letter.fill()

    NSGraphicsContext.current = nil
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

render(letterAlpha: 1, to: CommandLine.arguments[1])
// Paused: the same key with the H faded, readable as "off" at a glance.
render(letterAlpha: 0.35, to: CommandLine.arguments[2])
