// make_dmg_background.swift — renders the DMG install-window background.
// Usage: swift Scripts/make_dmg_background.swift <output.png>
//
// Light, Apple-installer-style canvas: title, a drag arrow between where Finder
// places the app icon and the Applications folder, and a short reassurance line.
// Icons themselves are placed by Finder (see package.sh).
//
// This used to carry a large amber "REQUIRED · ONE-TIME SETUP" card with an
// `xattr -dr com.apple.quarantine` command, because the app wasn't notarized and
// Gatekeeper blocked the first launch. The app is notarized now, so that step is
// gone — asking people to paste a quarantine-stripping command into Terminal is
// exactly the habit a security-conscious user should refuse, and it isn't needed
// any more.

import AppKit

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dmg-background.png"
let W: CGFloat = 700, H: CGFloat = 470

let accent = NSColor(srgbRed: 0.231, green: 0.510, blue: 0.965, alpha: 1)
let ink    = NSColor(srgbRed: 0.114, green: 0.118, blue: 0.129, alpha: 1)
let muted  = NSColor(srgbRed: 0.420, green: 0.439, blue: 0.478, alpha: 1)
let faint  = NSColor(srgbRed: 0.604, green: 0.620, blue: 0.655, alpha: 1)
let green  = NSColor(srgbRed: 0.129, green: 0.588, blue: 0.322, alpha: 1)

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

/// A green check inside a filled circle, drawn from a top-down center y.
func checkBadge(cxCenter: CGFloat, cyTop: CGFloat, size sz: CGFloat) {
    let cy = H - cyTop, r = sz / 2
    ctx.setFillColor(green.withAlphaComponent(0.14).cgColor)
    ctx.fillEllipse(in: CGRect(x: cxCenter - r, y: cy - r, width: sz, height: sz))
    ctx.setStrokeColor(green.cgColor)
    ctx.setLineWidth(sz * 0.13); ctx.setLineCap(.round); ctx.setLineJoin(.round)
    ctx.beginPath()
    ctx.move(to: CGPoint(x: cxCenter - r * 0.42, y: cy + r * 0.03))
    ctx.addLine(to: CGPoint(x: cxCenter - r * 0.10, y: cy - r * 0.32))
    ctx.addLine(to: CGPoint(x: cxCenter + r * 0.45, y: cy + r * 0.34))
    ctx.strokePath()
}

// ── Header ──────────────────────────────────────────────
text("Install Insomniac", size: 27, weight: .bold, color: ink, yTop: 40, centerX: W/2)
text("Drag the app onto the Applications folder", size: 13.5, color: muted, yTop: 76, centerX: W/2)

// ── Drag arrow (between Finder's app icon @245 and Applications @455) ──
// Both icons sit at y-down 155; the arrow spans the gap between them.
let ay: CGFloat = H - 155
ctx.setStrokeColor(accent.cgColor)
ctx.setLineWidth(4); ctx.setLineCap(.round); ctx.setLineJoin(.round)
ctx.move(to: CGPoint(x: 320, y: ay)); ctx.addLine(to: CGPoint(x: 380, y: ay)); ctx.strokePath()
ctx.move(to: CGPoint(x: 366, y: ay + 13))
ctx.addLine(to: CGPoint(x: 384, y: ay))
ctx.addLine(to: CGPoint(x: 366, y: ay - 13)); ctx.strokePath()

// ── Reassurance card ────────────────────────────────────
let card = CGRect(x: 96, y: 74, width: W - 192, height: 104) // y-up 74..178
ctx.setShadow(offset: CGSize(width: 0, height: -3), blur: 14,
              color: NSColor(srgbRed: 0.10, green: 0.30, blue: 0.18, alpha: 0.12).cgColor)
ctx.setFillColor(NSColor(srgbRed: 0.957, green: 0.988, blue: 0.965, alpha: 1).cgColor)
ctx.addPath(roundRect(card, radius: 16)); ctx.fillPath()
ctx.setShadow(offset: .zero, blur: 0, color: nil)
ctx.setStrokeColor(green.withAlphaComponent(0.35).cgColor)
ctx.setLineWidth(1.5); ctx.addPath(roundRect(card, radius: 16)); ctx.strokePath()

checkBadge(cxCenter: 134, cyTop: 322, size: 26)
text("Notarized by Apple", size: 14.5, weight: .semibold, color: ink, yTop: 314, x: 158)
text("No Terminal step, no security warning — just open it after installing.",
     size: 12, color: muted, yTop: 337, x: 158)
text("Insomniac lives in the menu bar, not the Dock.",
     size: 11, color: faint, yTop: 358, x: 158)

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("failed to render PNG\n".data(using: .utf8)!)
    exit(1)
}
try! png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
