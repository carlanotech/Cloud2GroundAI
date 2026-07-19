//
//  StatusPanelWindowController.swift
//  Cloud to Ground AI — v0.2
//
//  Owns the lifecycle of the Status Panel window so the menu bar app can
//  open / focus it from anywhere without duplicating windows.
//
//  Implements: window-management side of L2-GUI-010 (status panel).
//

import AppKit
import SwiftUI

@MainActor
final class StatusPanelWindowController {
    static let shared = StatusPanelWindowController()

    // Strong reference — the window must stay alive after we create it.
    private var window: NSWindow?

    private init() {}

    /// Open the panel (or bring it to front if already open).
    func showPanel() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        let view = StatusPanelView(status: BridgeStatus.shared)
        let hostingController = NSHostingController(rootView: view)

        let win = NSWindow(contentViewController: hostingController)
        win.title = "Cloud to Ground AI — Status"
        win.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        win.setContentSize(NSSize(width: 420, height: 460))
        win.center()
        win.isReleasedWhenClosed = false   // we manage lifetime
        win.delegate = WindowDelegateProxy.shared

        window = win

        win.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    /// Called by the delegate when the user closes the window. We keep the
    /// BridgeStatus object alive (so refreshes / state are remembered) and
    /// just drop the window reference.
    fileprivate func windowDidClose() {
        window = nil
    }
}

/// Thin delegate proxy so we can clear the window reference on close.
@MainActor
final class WindowDelegateProxy: NSObject, NSWindowDelegate {
    static let shared = WindowDelegateProxy()
    func windowWillClose(_ notification: Notification) {
        StatusPanelWindowController.shared.windowDidClose()
    }
}
