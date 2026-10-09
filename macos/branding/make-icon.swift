// Renders the Homekey app icon. Run: swift macos/branding/make-icon.swift <out.png>
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

// macOS icon grid: 824pt rounded square centred in 1024, corner ~185.
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
ctx.addPath(tilePath)
ctx.setFillColor(NSColor.black.cgColor)
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(tilePath)
ctx.clip()
let bg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                    colors: [NSColor(red: 0.20, green: 0.22, blue: 0.62, alpha: 1).cgColor,
                             NSColor(red: 0.07, green: 0.07, blue: 0.22, alpha: 1).cgColor] as CFArray,
                    locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: 924), end: CGPoint(x: 0, y: 100), options: [])
ctx.restoreGState()

// Keycap: a darker base with a lighter, inset top.
let capBase = CGRect(x: 262, y: 236, width: 500, height: 520)
let capTop = CGRect(x: 302, y: 316, width: 420, height: 400)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 30, color: NSColor.black.withAlphaComponent(0.45).cgColor)
ctx.addPath(CGPath(roundedRect: capBase, cornerWidth: 90, cornerHeight: 90, transform: nil))
ctx.setFillColor(NSColor(white: 0.80, alpha: 1).cgColor)
ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(CGPath(roundedRect: capTop, cornerWidth: 70, cornerHeight: 70, transform: nil))
ctx.clip()
let capGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                             colors: [NSColor.white.cgColor, NSColor(white: 0.90, alpha: 1).cgColor] as CFArray,
                             locations: [0, 1])!
ctx.drawLinearGradient(capGradient, start: CGPoint(x: 0, y: 716), end: CGPoint(x: 0, y: 316), options: [])
ctx.restoreGState()

// The "H" on the key.
let letter = NSAttributedString(string: "H", attributes: [
    .font: NSFont.systemFont(ofSize: 300, weight: .heavy),
    .foregroundColor: NSColor(red: 0.12, green: 0.13, blue: 0.40, alpha: 1),
])
let letterSize = letter.size()
letter.draw(at: CGPoint(x: capTop.midX - letterSize.width / 2, y: capTop.midY - letterSize.height / 2 + 6))

// A hint label tag, like the yellow labels Homekey draws on screen.
let tag = CGRect(x: 600, y: 610, width: 250, height: 150)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 18, color: NSColor.black.withAlphaComponent(0.4).cgColor)
ctx.addPath(CGPath(roundedRect: tag, cornerWidth: 38, cornerHeight: 38, transform: nil))
ctx.setFillColor(NSColor(red: 1.0, green: 0.83, blue: 0.23, alpha: 1).cgColor)
ctx.fillPath()
ctx.restoreGState()
let tagText = NSAttributedString(string: "AS", attributes: [
    .font: NSFont.systemFont(ofSize: 96, weight: .black),
    .foregroundColor: NSColor(white: 0.08, alpha: 1),
])
let tagSize = tagText.size()
tagText.draw(at: CGPoint(x: tag.midX - tagSize.width / 2, y: tag.midY - tagSize.height / 2))

image.unlockFocus()
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
