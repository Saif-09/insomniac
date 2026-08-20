//
//  ScreenshotGenerator.swift
//  insomniac
//
//  Generates the Mac App Store screenshots by rendering the app's *real* SwiftUI
//  views offscreen with `ImageRenderer`, then compositing them onto marketing
//  canvases at an App-Store-accepted size (2560×1600).
//
//  Why render rather than screen-capture:
//   • The panel is a MenuBarExtra window — it closes the moment focus moves, so
//     capturing it reliably means fighting the window server.
//   • A screen capture picks up whatever else is on the desktop. These images go
//     to Apple and then to the store; they should contain the app and nothing else.
//   • Rendering is deterministic and repeatable, so regenerating for the next
//     release is one command rather than a manual re-shoot.
//   • Because it renders the shipping views, the screenshots cannot drift away
//     from what the app actually looks like.
//
//  DEBUG-only: this file, and the `poseForScreenshot` hooks it relies on, are
//  compiled out of Release entirely. Run with:
//
//      INSOMNIAC_SCREENSHOTS=<output-dir> <debug build>/insomniac.app/Contents/MacOS/insomniac
//

#if DEBUG

import AppKit
import SwiftUI

@MainActor
enum ScreenshotGenerator {

    /// App Store macOS screenshots must be 1280×800, 1440×900, 2560×1600 or
    /// 2880×1800. 2560×1600 is the 16:10 retina size and the safe default.
    static let canvas = CGSize(width: 2560, height: 1600)

    /// Runs if `INSOMNIAC_SCREENSHOTS` is set, then terminates the app.
    static func runIfRequested() -> Bool {
        guard let dir = ProcessInfo.processInfo.environment["INSOMNIAC_SCREENSHOTS"] else {
            return false
        }
        // Insomniac is an .accessory app (no Dock icon), and an accessory app
        // can't become properly *active* — so AppKit keeps drawing controls in
        // their inactive appearance and the accent-coloured "on" switch renders
        // as a grey pill. Becoming a regular app for the duration of the render
        // is what makes the switch actually look on.
        NSApp.setActivationPolicy(.regular)

        let url = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        generate(into: url)
        return true
    }

    // MARK: - The shots

    private struct Shot {
        let file: String
        let headline: String
        let subline: String
        /// Pose the controller, then hand back the view to render.
        let build: (AppController) -> AnyView
    }

    private static func generate(into dir: URL) {
        let app = AppController.shared
        poseSystemSnapshot(app)
        // Most users have no external display, so the honest lid messaging (and
        // the caveat card) is what should appear in the store screenshots.
        app.display.poseForScreenshot(hasExternalDisplay: false)

        // Order and wording both matter here: these are metadata, and App Review
        // rejected the previous set under 4.3(a) as a duplicate of the many
        // keep-awake apps already on the store. Leading with "one switch keeps
        // it awake" is precisely what every one of those says. The differentiators
        // — the safety cutoffs, the advisory, the assertion inspector — now come
        // first, and the generic on/off switch comes last.
        //
        // "Mac" is gone from every headline as well: 5.2.5 flagged the subtitle
        // for trademark use, and screenshot text is metadata under the same rule.
        let shots: [Shot] = [
            Shot(
                file: "01-safety",
                headline: "It stops before things overheat.",
                subline: "Thermal and low-battery cutoffs end the session on their own. Nothing to babysit."
            ) { app in
                app.poseForScreenshot(active: true, duration: .oneHour, elapsed: 12 * 60)
                return AnyView(SettingsScreenshotWrapper().environment(app))
            },
            Shot(
                file: "02-advisory",
                headline: "It tells you how long is safe.",
                subline: "A live read of heat, power source and load — with a session length to match."
            ) { app in
                app.poseForScreenshot(active: true, duration: .twoHours, elapsed: 27 * 60 + 18)
                return AnyView(MenuContent().environment(app))
            },
            Shot(
                file: "03-system",
                headline: "See exactly what's blocking sleep.",
                subline: "Every process holding a power assertion right now, read straight from the system."
            ) { app in
                app.poseForScreenshot(active: true, duration: .twoHours, elapsed: 27 * 60 + 18)
                return AnyView(SystemTabScreenshotWrapper().environment(app))
            },
            Shot(
                file: "04-timer",
                headline: "A timer that always ends it.",
                subline: "Ten minutes to eight hours, or any length you pick. Normal sleep returns by itself."
            ) { app in
                app.poseForScreenshot(active: false, duration: .custom(seconds: 95 * 60), elapsed: 0)
                return AnyView(MenuContent().environment(app))
            },
        ]

        for shot in shots {
            let view = shot.build(app)
            guard let panel = render(view) else {
                FileHandle.standardError.write("failed to render \(shot.file)\n".data(using: .utf8)!)
                continue
            }
            let composed = compose(panel: panel, headline: shot.headline, subline: shot.subline)
            write(composed, to: dir.appendingPathComponent("\(shot.file).png"))
        }
        print("✓ wrote \(shots.count) screenshots to \(dir.path)")
    }

    /// A believable "what's keeping your Mac awake" list. Real names, because
    /// these are the apps people actually find there — and it's the same shape
    /// `IOPMCopyAssertionsByProcess` returns.
    private static func poseSystemSnapshot(_ app: AppController) {
        app.systemPower.poseForScreenshot(
            PowerSnapshot(
                sleepDisabled: true,
                idleSleepMinutes: 0,
                displaySleepMinutes: 10,
                preventers: [
                    SleepPreventer(pid: 501, process: "Insomniac", kind: .idleSystem,
                                   reason: "Insomniac is keeping this Mac awake", isSelf: true),
                    SleepPreventer(pid: 640, process: "Music", kind: .idleSystem,
                                   reason: "Playing audio", isSelf: false),
                    SleepPreventer(pid: 883, process: "Xcode", kind: .system,
                                   reason: "Building", isSelf: false),
                    SleepPreventer(pid: 355, process: "Safari", kind: .display,
                                   reason: "Playing video", isSelf: false),
                ],
                capturedAt: Date()
            )
        )
    }

    // MARK: - Rendering

    /// Render a SwiftUI view by hosting it in a real (briefly on-screen) window
    /// and capturing that window.
    ///
    /// `ImageRenderer` is the obvious tool here and it does not work for this
    /// UI: on macOS, `Toggle(.switch)`, `Picker(.segmented)`, `Picker(.menu)`
    /// and bordered `Button`s are AppKit-backed, and ImageRenderer draws every
    /// one of them as a yellow "unsupported" placeholder. Since the switch *is*
    /// the product, that's fatal. Hosting in an `NSWindow` and capturing gets
    /// real AppKit control rendering — genuinely what the user sees.
    ///
    /// The window is positioned off to the side and closed immediately; it
    /// flashes on screen for a fraction of a second per shot.
    private static func render(_ view: some View) -> NSImage? {
        let hosting = NSHostingView(
            rootView: AnyView(
                view
                    .frame(width: 340)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .environment(\.colorScheme, .dark)
                    // Launching the binary straight from a shell never gets the
                    // process activation rights, so NSApp.isActive stays false
                    // and AppKit draws every control inactive — the accent "on"
                    // switch comes out a dead grey. Setting the control-active
                    // state explicitly is what actually fixes it, and it's
                    // deterministic rather than racing the window server.
                    .environment(\.controlActiveState, .key)
            )
        )
        hosting.frame = NSRect(x: 0, y: 0, width: 340, height: hosting.fittingSize.height)

        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        window.appearance = NSAppearance(named: .darkAqua)
        window.level = .normal
        window.setFrameOrigin(NSPoint(x: 40, y: 40))

        // Must be key AND the app active: AppKit renders controls in their
        // inactive appearance otherwise, which turns the accent-coloured "on"
        // switch — the single most important pixel in these screenshots — into
        // a dead grey pill.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        // Spin until the app is genuinely active and the window key, rather than
        // guessing at a sleep duration — control appearance depends on both.
        let deadline = Date().addingTimeInterval(3.0)
        while Date() < deadline, !(NSApp.isActive && window.isKeyWindow) {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
        FileHandle.standardError.write(
            "  [render] appActive=\(NSApp.isActive) windowKey=\(window.isKeyWindow)\n".data(using: .utf8)!)

        window.displayIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))

        defer { window.orderOut(nil); window.close() }

        // `cacheDisplay` draws the AppKit view hierarchy straight into a
        // bitmap. The obvious alternative, CGWindowListCreateImage, wants
        // Screen Recording permission that this Debug binary doesn't have and
        // simply hangs waiting for it. This needs no permission at all, and
        // still renders genuine AppKit controls (unlike ImageRenderer).
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            return nil
        }
        rep.size = hosting.bounds.size
        hosting.cacheDisplay(in: hosting.bounds, to: rep)

        let image = NSImage(size: hosting.bounds.size)
        image.addRepresentation(rep)
        return image
    }

    // MARK: - Compositing

    /// Composites into an explicitly-sized bitmap rather than `NSImage.lockFocus`.
    /// lockFocus inherits the display's backing scale, so on a retina Mac it
    /// silently produced 5120×3200 files — not one of the sizes App Store
    /// Connect accepts. Driving an `NSBitmapImageRep` pins the pixel dimensions.
    private static func compose(panel: NSImage, headline: String, subline: String) -> NSBitmapImageRep {
        let W = canvas.width, H = canvas.height
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(W), pixelsHigh: Int(H),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { fatalError("could not allocate the screenshot bitmap") }
        rep.size = canvas

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let gc = NSGraphicsContext(bitmapImageRep: rep) else { return rep }
        NSGraphicsContext.current = gc
        let ctx = gc.cgContext

        // Background: the landing page's deep navy with a blue bloom behind the
        // panel, so the set reads as one family with the website.
        ctx.setFillColor(NSColor(srgbRed: 0.027, green: 0.031, blue: 0.043, alpha: 1).cgColor)
        ctx.fill(CGRect(origin: .zero, size: canvas))
        if let bloom = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                NSColor(srgbRed: 0.231, green: 0.510, blue: 0.965, alpha: 0.32).cgColor,
                NSColor(srgbRed: 0.231, green: 0.510, blue: 0.965, alpha: 0.0).cgColor,
            ] as CFArray,
            locations: [0, 1]
        ) {
            ctx.drawRadialGradient(
                bloom,
                startCenter: CGPoint(x: W / 2, y: H * 0.42), startRadius: 0,
                endCenter: CGPoint(x: W / 2, y: H * 0.42), endRadius: W * 0.52,
                options: []
            )
        }

        // Headline + subline, top-aligned.
        draw(headline, size: 78, weight: .bold,
             color: NSColor(srgbRed: 0.957, green: 0.965, blue: 0.984, alpha: 1),
             yTop: 118, maxWidth: W - 320)
        draw(subline, size: 34, weight: .regular,
             color: NSColor(srgbRed: 0.545, green: 0.576, blue: 0.655, alpha: 1),
             yTop: 224, maxWidth: W - 560)

        // The panel, centred below, with a soft drop shadow and rounded corners.
        let panelWidth: CGFloat = 1020
        let scale = panelWidth / panel.size.width
        let panelHeight = panel.size.height * scale
        let maxHeight = H - 430
        let finalScale = panelHeight > maxHeight ? (maxHeight / panel.size.height) : scale
        let w = panel.size.width * finalScale, h = panel.size.height * finalScale
        let rect = CGRect(x: (W - w) / 2, y: (H - h) / 2 - 92, width: w, height: h)

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -26), blur: 74,
                      color: NSColor(white: 0, alpha: 0.62).cgColor)
        let clip = CGPath(roundedRect: rect, cornerWidth: 26, cornerHeight: 26, transform: nil)
        ctx.addPath(clip)
        ctx.setFillColor(NSColor(srgbRed: 0.12, green: 0.12, blue: 0.13, alpha: 1).cgColor)
        ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(clip)
        ctx.clip()
        panel.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        ctx.restoreGState()

        // Hairline edge so the panel separates from the background.
        ctx.addPath(clip)
        ctx.setStrokeColor(NSColor(white: 1, alpha: 0.10).cgColor)
        ctx.setLineWidth(2)
        ctx.strokePath()

        return rep
    }

    /// Centred, wrapping text measured from the top of the canvas.
    private static func draw(_ text: String, size: CGFloat, weight: NSFont.Weight,
                             color: NSColor, yTop: CGFloat, maxWidth: CGFloat) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineSpacing = size * 0.16
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
            .paragraphStyle: style,
            .kern: -size * 0.018,
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let bounds = str.boundingRect(
            with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        str.draw(with: CGRect(x: (canvas.width - maxWidth) / 2,
                              y: canvas.height - yTop - bounds.height,
                              width: maxWidth, height: bounds.height),
                 options: [.usesLineFragmentOrigin, .usesFontLeading])
    }

    private static func write(_ rep: NSBitmapImageRep, to url: URL) {
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
    }
}

// MARK: - Framing wrappers
//
// The System tab and the Settings section are normally nested inside
// MenuContent's chrome. These give them the same padded, fixed-width frame so
// every screenshot in the set has identical panel geometry.

private struct SystemTabScreenshotWrapper: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SystemTab()
        }
        .padding(16)
    }
}

private struct SettingsScreenshotWrapper: View {
    @Environment(AppController.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CaveatCard(text: app.closedLidWarning
                ?? "Insomniac keeps this Mac awake with the lid open, and can turn the screen off when you close it.")
            SettingsSection(initiallyExpanded: true)
        }
        .padding(16)
    }
}

#endif
