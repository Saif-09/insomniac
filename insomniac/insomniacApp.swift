//
//  insomniacApp.swift
//  insomniac
//
//  Keep the Mac awake with the lid closed — safely.
//

import SwiftUI

@main
struct insomniacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// The single source of truth for the whole app. Created once, lives for
    /// the process lifetime, and is injected into the menu UI.
    @State private var app = AppController.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environment(app)
        } label: {
            // The label is the menu-bar icon. It reflects on/off state and
            // tints when thermal risk is elevated (FR-3, FR-20).
            Image(systemName: app.menuBarSymbolName)
                .symbolRenderingMode(.hierarchical)
        }
        .menuBarExtraStyle(.window)
    }
}
