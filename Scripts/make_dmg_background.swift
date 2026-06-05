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
          mono: Bool = false, kern: CGFloat = 0) {
    let font = mono ? (NSFont(name: "Menlo", size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular))
                    : NSFont.systemFont(ofSize: size, weight: weight)
    var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    if kern != 0 { attrs[.kern] = kern }
    let str = NSAttributedString(string: s, attributes: attrs)
    let sz = str.size()
    let drawX = centerX != nil ? centerX! - sz.width / 2 : x
    str.draw(at: CGPoint(x: drawX, y: H - yTop - sz.height))
}

func roundRect(_ r: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

// Amber caution triangle with a white "!" — drawn from a top-down center y.
func caution(cxCenter: CGFloat, cyTop: CGFloat, size sz: CGFloat) {
    let cy = H - cyTop, r = sz / 2
    ctx.setFillColor(NSColor(srgbRed: 0.965, green: 0.776, blue: 0.141, alpha: 1).cgColor)
    ctx.beginPath()
    ctx.move(to: CGPoint(x: cxCenter, y: cy + r))
    ctx.addLine(to: CGPoint(x: cxCenter + r, y: cy - r * 0.82))
    ctx.addLine(to: CGPoint(x: cxCenter - r, y: cy - r * 0.82))
    ctx.closePath(); ctx.fillPath()
    ctx.setStrokeColor(NSColor.white.cgColor); ctx.setLineWidth(sz * 0.11); ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: cxCenter, y: cy + r * 0.28))
    ctx.addLine(to: CGPoint(x: cxCenter, y: cy - r * 0.12)); ctx.strokePath()
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillEllipse(in: CGRect(x: cxCenter - sz * 0.055, y: cy - r * 0.42, width: sz * 0.11, height: sz * 0.11))
}

// ── Header ──────────────────────────────────────────────
text("Install Insomniac", size: 27, weight: .bold, color: ink, yTop: 34, centerX: W/2)
text("Drag the app onto the Applications folder", size: 13.5, color: muted, yTop: 70, centerX: W/2)

// ── Drag arrow (between Finder's app icon @175 and Applications @415) ──
// Three icons sit at y-down 155: app(175) → Applications(415), plus the
// "Copy command" text file at 600. Draw the arrow over the drag pair.
let ay: CGFloat = H - 155
ctx.setStrokeColor(accent.cgColor)
ctx.setLineWidth(4); ctx.setLineCap(.round); ctx.setLineJoin(.round)
ctx.move(to: CGPoint(x: 250, y: ay)); ctx.addLine(to: CGPoint(x: 340, y: ay)); ctx.strokePath()
ctx.move(to: CGPoint(x: 326, y: ay + 13))
ctx.addLine(to: CGPoint(x: 344, y: ay))
ctx.addLine(to: CGPoint(x: 326, y: ay - 13)); ctx.strokePath()

// Small caption above the "Copy command" file (icon center @600).
text("need to copy it?", size: 11, color: faint, yTop: 92, centerX: 600)

// ── Important one-time-setup notice (amber, attention-grabbing) ──────────
let card = CGRect(x: 44, y: 32, width: W - 88, height: 190) // y-up 32..222
ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 18,
              color: NSColor(srgbRed: 0.80, green: 0.58, blue: 0.0, alpha: 0.20).cgColor)
ctx.setFillColor(NSColor(srgbRed: 1.0, green: 0.973, blue: 0.910, alpha: 1).cgColor)
ctx.addPath(roundRect(card, radius: 16)); ctx.fillPath()
ctx.setShadow(offset: .zero, blur: 0, color: nil)
ctx.setStrokeColor(NSColor(srgbRed: 0.913, green: 0.706, blue: 0.110, alpha: 1).cgColor)
ctx.setLineWidth(1.5); ctx.addPath(roundRect(card, radius: 16)); ctx.strokePath()

// "REQUIRED" badge: caution triangle + tracked uppercase amber label.
let amberDark = NSColor(srgbRed: 0.494, green: 0.369, blue: 0.012, alpha: 1)
caution(cxCenter: 80, cyTop: 271, size: 21)
text("REQUIRED · ONE-TIME SETUP", size: 11.5, weight: .heavy, color: amberDark,
     yTop: 264, x: 98, kern: 0.7)

text("Open “Copy command” to copy it — or type this in Terminal:", size: 14, weight: .semibold,
     color: ink, yTop: 290, x: 68)

// Command pill (dark).
let pill = CGRect(x: 68, y: H - 362, width: W - 136, height: 40) // y-down 322..362
ctx.setFillColor(NSColor(srgbRed: 0.118, green: 0.122, blue: 0.137, alpha: 1).cgColor)
ctx.addPath(roundRect(pill, radius: 9)); ctx.fillPath()
text("xattr -dr com.apple.quarantine /Applications/insomniac.app", size: 12.5,
     color: NSColor(srgbRed: 0.902, green: 0.910, blue: 0.937, alpha: 1), yTop: 334, x: 84, mono: true)

text("Open Terminal (⌘Space → “Terminal”), paste, press Return — then open Insomniac.",
     size: 11.5, color: muted, yTop: 376, x: 68)
text("It's code-signed and safe — this only clears Apple's “unverified” block for un-notarized apps.",
     size: 10.5, color: faint, yTop: 395, x: 68)

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("failed to render PNG\n".data(using: .utf8)!)
    exit(1)
}
try! png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
