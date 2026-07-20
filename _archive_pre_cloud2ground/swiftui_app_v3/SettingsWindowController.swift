//
//  SettingsWindowController.swift
//  Cloud to Ground AI — v0.2 Step 5
//
//  Owns the Settings window lifetime so menu-item clicks don't open
//  duplicate windows. Same pattern as StatusPanelWindowController,
//  GroundChatWindowController, and SetupWizardWindowController.
//
//  The SettingsView's two ObservableObjects (Preferences.shared,
//  SkillUpdateManager.shared) are global singletons, so the window can
//  open and close freely without losing settings or update state.
//

import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    private init() {}

    func showWindow() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        let view = SettingsView(
            prefs: Preferences.shared,
            updates: SkillUpdateManager.shared
        )
        let hostingController = NSHostingController(rootView: view)

        let win = NSWindow(contentViewController: hostingController)
        win.title = "Cloud to Ground AI — Settings"
        win.styleMask = [.titled, .closable, .miniaturizable]
        win.setContentSize(NSSize(width: 560, height: 460))
        win.center()
        win.isReleasedWhenClosed = false
        win.delegate = SettingsWindowDelegateProxy.shared

        window = win
        win.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    fileprivate func windowDidClose() {
        window = nil
    }
}

@MainActor
final class SettingsWindowDelegateProxy: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowDelegateProxy()
    func windowWillClose(_ notification: Notification) {
        SettingsWindowController.shared.windowDidClose()
    }
}
