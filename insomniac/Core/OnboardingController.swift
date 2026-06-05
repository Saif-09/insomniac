//
//  OnboardingController.swift
//  insomniac
//
//  Drives the first-launch experience for a Dock-less menu-bar app:
//   1. A centered welcome window (feature intro).
//   2. A borderless "I live up here" arrow panel anchored just below the menu
//      bar at the top-right, pointing at the real Insomniac icon.
//
//  The app stays an `.accessory` (no Dock icon) the whole time — accessory apps
//  can still show and focus normal windows, so we just activate and order the
//  window front. We deliberately do NOT toggle the activation policy: doing so
//  destabilises the MenuBarExtra status item and can terminate the app when the
//  welcome window closes.
//

import AppKit
import SwiftUI

@MainActor
final class OnboardingController: NSObject, NSWindowDelegate {
    static let shared = OnboardingController()

    private var welcomeWindow: NSWindow?
    private var pointerPanel: NSPanel?
    private var dismissPointerWork: DispatchWorkItem?
    /// Guards `endOnboarding` so the close-button path and the "Get Started"
    /// path don't both run it.
    private var didEnd = false

    /// How long the arrow lingers after onboarding ends before fading out.
    private let pointerLinger: TimeInterval = 7

    /// Show the walkthrough if the user hasn't completed it yet. Safe to call
    /// at every launch — it no-ops once onboarding is done.
    func presentIfNeeded(prefs: Preferences) {
        guard !prefs.hasCompletedOnboarding else { return }
        presentWelcome()
    }

    /// Force the walkthrough open regardless of the saved flag (e.g. a future
    /// "Show welcome…" menu item).
    func presentWelcome() {
        if let welcomeWindow {
            NSApp.activate(ignoringOtherApps: true)
            welcomeWindow.makeKeyAndOrderFront(nil)
            return
        }

        didEnd = false

        let view = OnboardingView(
            onRevealPointer: { [weak self] in self?.showPointer() },
            onFinish: { [weak self] in self?.endOnboarding() }
        )

        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .fullSizeContentView, .closable]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.title = "Welcome to Insomniac"
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.delegate = self
        window.center()
        window.isReleasedWhenClosed = false

        welcomeWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - Finish

    /// Single exit point for onboarding, whether the user clicked "Get Started"
    /// or closed the window with the red dot. Marks it complete, makes sure the
    /// arrow has been shown, and schedules it to fade out.
    private func endOnboarding() {
        guard !didEnd else { return }
        didEnd = true

        AppController.shared.prefs.hasCompletedOnboarding = true

        if let w = welcomeWindow {
            w.delegate = nil          // avoid re-entering via windowWillClose
            w.close()
            welcomeWindow = nil
        }

        // Make sure the arrow is up (it may already be from "Show me where"),
        // then leave it briefly so the eye lands on the real icon.
        showPointer()
        schedulePointerDismiss(after: pointerLinger)
    }

    // MARK: - Live arrow panel

    private func showPointer() {
        if pointerPanel == nil {
            let h = NSHostingController(rootView: MenuBarPointer())
            // CRITICAL: we size the panel ourselves in positionPointer(). Leaving
            // the default `.preferredContentSize` makes the hosting controller
            // ALSO drive the window size via Auto Layout constraints — and on a
            // borderless panel that fights our manual frame in an infinite layout
            // loop that overflows the stack and crashes the app. Disable it.
            h.sizingOptions = []
            let p = NSPanel(contentViewController: h)
            p.styleMask = [.borderless, .nonactivatingPanel]
            p.isFloatingPanel = true
            p.level = .statusBar
            p.backgroundColor = .clear
            p.isOpaque = false
            p.hasShadow = false
            p.hidesOnDeactivate = false
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            p.ignoresMouseEvents = true
            pointerPanel = p
        }

        positionPointer()
        pointerPanel?.alphaValue = 1
        pointerPanel?.orderFrontRegardless()

        // The menu bar can reflow right around when we measure (an icon appears,
        // recording starts, the welcome window closes), leaving us pointing at
        // the icon's old spot. Re-measure a couple of times so the bubble snaps
        // onto the icon's real position.
        for delay in [0.25, 0.7] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, let panel = self.pointerPanel, panel.alphaValue > 0 else { return }
                    self.positionPointer()
                }
            }
        }
    }

    /// Recompute the panel frame from the icon's *current* position. Safe to call
    /// repeatedly — it re-reads the icon location every time.
    private func positionPointer() {
        guard let panel = pointerPanel,
              let hosting = panel.contentViewController as? NSHostingController<MenuBarPointer>,
              let screen = welcomeWindow?.screen ?? NSScreen.main ?? NSScreen.screens.first
        else { return }

        let visible = screen.visibleFrame
        let iconCenterX = menuBarIconCenterX(on: screen) ?? (visible.maxX - 30)

        // Measure the bubble at its natural size (uses .fixedSize, deterministic).
        hosting.view.layoutSubtreeIfNeeded()
        let fitting = hosting.view.fittingSize
        let size = NSSize(width: max(fitting.width, 240), height: max(fitting.height, 86))

        // Ideal panel x centers the bubble under the icon, then clamp so the
        // bubble stays fully on screen (the icon can sit anywhere in the bar).
        let idealX = iconCenterX - size.width / 2
        let minX = visible.minX + 4
        let maxX = visible.maxX - size.width - 4
        let x = min(max(idealX, minX), maxX)

        // The arrow tip slides to keep pointing at the icon even after clamping.
        let bubbleCenterX = x + size.width / 2
        let arrowOffsetX = max(-size.width / 2 + 24, min(iconCenterX - bubbleCenterX, size.width / 2 - 24))
        hosting.rootView = MenuBarPointer(arrowOffsetX: arrowOffsetX)
        hosting.view.frame = NSRect(origin: .zero, size: size)
        panel.setContentSize(size)

        // visibleFrame already excludes the menu bar, so its top edge is right
        // under the bar — line the arrow tip up flush against it.
        let y = visible.maxY - size.height + MenuBarPointer.vInset
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }

    /// Best-effort: locate the horizontal center of our MenuBarExtra icon by
    /// finding the status-bar window AppKit creates for it. Returns nil if it
    /// can't be found (caller falls back to the right edge).
    private func menuBarIconCenterX(on screen: NSScreen) -> CGFloat? {
        for window in NSApp.windows {
            let cls = NSStringFromClass(type(of: window))
            guard cls.contains("StatusBar") || cls.contains("MenuBarExtra") else { continue }
            let f = window.frame
            // Sanity: it should sit in the menu-bar strip of this screen.
            guard f.minY >= screen.frame.maxY - 40, f.width > 0, f.width < 200 else { continue }
            return f.midX
        }
        return nil
    }

    private func schedulePointerDismiss(after seconds: TimeInterval) {
        dismissPointerWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.dismissPointer() }
        dismissPointerWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func dismissPointer() {
        guard let panel = pointerPanel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.4
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.pointerPanel?.orderOut(nil)
            self?.pointerPanel = nil
        })
    }

    // MARK: - NSWindowDelegate

    /// If the user closes the welcome window with the red dot instead of
    /// "Get Started", run the same exit path so the arrow still appears and
    /// then dismisses.
    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === welcomeWindow else { return }
        endOnboarding()
    }
}
