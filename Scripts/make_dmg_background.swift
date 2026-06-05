// make_dmg_background.swift — renders the DMG install-window background.
// Usage: swift Scripts/make_dmg_background.swift <output.png>
// Light, Apple-installer-style canvas: title, a drag arrow between where Finder
// places the app icon and the Applications folder, and a one-time setup card
// with the quarantine-clearing command. Icons themselves are placed by Finder.

import AppKit

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dmg-background.png"
let W: CGFloat = 700, H: CGFloat = 470

let accent = NSColor(srgbRed: 0.231, green: 0.510, blue: 0.965, alpha: 1)
let ink    = NSColor(srgbRed: 0.114, green: 0.118, blue: 0.129, alpha: 1)
let muted  = NSColor(srgbRed: 0.420, green: 0.439, blue: 0.478, alpha: 1)
let faint  = NSColor(srgbRed: 0.604, green: 0.620, blue: 0.655, alpha: 1)

let image = NSImage(size: NSSize(width: W, height: H))
image.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

// Background gradient (y-up: 0 = bottom).
let top = NSColor(srgbRed: 0.984, green: 0.986, blue: 0.992, alpha: 1).cgColor
let bot = NSColor(srgbRed: 0.918, green: 0.927, blue: 0.941, alpha: 1).cgColor
let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                      colors: [bot, top] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(grad, start: .zero, end: CGPoint(x: 0, y: H), options: [])

// Text helper. `yTop` is distance from the TOP of the canvas.
func text(_ s: String, size: CGFloat, weight: NSFont.Weight = .regular,
          color: NSColor, yTop: CGFloat, centerX: CGFloat? = nil, x: CGFloat = 0,
          mono: Bool = false) {
    let font = mono ? (NSFont(name: "Menlo", size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular))
                    : NSFont.systemFont(ofSize: size, weight: weight)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let str = NSAttributedString(string: s, attributes: attrs)
    let sz = str.size()
    let drawX = centerX != nil ? centerX! - sz.width / 2 : x
    str.draw(at: CGPoint(x: drawX, y: H - yTop - sz.height))
}

func roundRect(_ r: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

// ── Header ──────────────────────────────────────────────
text("Install Insomniac", size: 27, weight: .bold, color: ink, yTop: 34, centerX: W/2)
text("Drag the app onto the Applications folder", size: 13.5, color: muted, yTop: 70, centerX: W/2)

// ── Drag arrow (between Finder's app icon @205 and Applications @495) ──
// Icon centers are y-down 185 → y-up 285. Draw the arrow at that height.
let ay: CGFloat = H - 185
ctx.setStrokeColor(accent.cgColor)
ctx.setLineWidth(4); ctx.setLineCap(.round); ctx.setLineJoin(.round)
ctx.move(to: CGPoint(x: 298, y: ay)); ctx.addLine(to: CGPoint(x: 398, y: ay)); ctx.strokePath()
ctx.move(to: CGPoint(x: 384, y: ay + 13))
ctx.addLine(to: CGPoint(x: 402, y: ay))
ctx.addLine(to: CGPoint(x: 384, y: ay - 13)); ctx.strokePath()

// ── One-time setup card ─────────────────────────────────
let card = CGRect(x: 44, y: 40, width: W - 88, height: 168) // y-up 40..208
ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 16,
              color: NSColor.black.withAlphaComponent(0.10).cgColor)
ctx.setFillColor(NSColor.white.cgColor)
ctx.addPath(roundRect(card, radius: 16)); ctx.fillPath()
ctx.setShadow(offset: .zero, blur: 0, color: nil)
ctx.setStrokeColor(NSColor(srgbRed: 0.886, green: 0.898, blue: 0.918, alpha: 1).cgColor)
ctx.setLineWidth(1); ctx.addPath(roundRect(card, radius: 16)); ctx.strokePath()

// Card content (y-down coordinates).
text("One-time setup — do this BEFORE you open the app", size: 13.5, weight: .semibold,
     color: ink, yTop: 278, x: 68)

// Command pill (dark).
let pill = CGRect(x: 68, y: H - 350, width: W - 136, height: 40) // y-down 310..350
ctx.setFillColor(NSColor(srgbRed: 0.118, green: 0.122, blue: 0.137, alpha: 1).cgColor)
ctx.addPath(roundRect(pill, radius: 9)); ctx.fillPath()
text("xattr -dr com.apple.quarantine /Applications/insomniac.app", size: 12.5,
     color: NSColor(srgbRed: 0.902, green: 0.910, blue: 0.937, alpha: 1), yTop: 322, x: 84, mono: true)

text("Open Terminal (⌘Space → “Terminal”), paste the line, press Return — then open Insomniac.",
     size: 11.5, color: muted, yTop: 366, x: 68)
text("It's code-signed and safe — this only clears Apple's “unverified” block for un-notarized apps.",
     size: 11, color: faint, yTop: 386, x: 68)

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("failed to render PNG\n".data(using: .utf8)!)
    exit(1)
}
try! png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
