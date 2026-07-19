//
//  SetupWizardWindowController.swift
//  Cloud to Ground AI — v0.2 Setup Wizard
//
//  Same pattern as StatusPanelWindowController + GroundChatWindowController:
//  owns the NSWindow lifetime so menu-item clicks don't open duplicate
//  windows, and so the controller (state machine + async tasks) survives
//  window closes when the user reopens.
//

import AppKit
import SwiftUI

@MainActor
final class SetupWizardWindowController {
    static let shared = SetupWizardWindowController()

    private var window: NSWindow?
    private let controller = SetupController()

    private init() {}

    func showWindow() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        let view = SetupWizardView(controller: controller)
        let hostingController = NSHostingController(rootView: view)

        let win = NSWindow(contentViewController: hostingController)
        win.title = "Cloud to Ground AI — Setup"
        win.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        win.setContentSize(NSSize(width: 820, height: 600))
        win.center()
        win.isReleasedWhenClosed = false
        win.delegate = SetupWizardWindowDelegateProxy.shared

        window = win
        win.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    fileprivate func windowDidClose() {
        window = nil
        // Controller persists — its log + state survive so reopening
        // shows the user where they left off.
    }
}

@MainActor
final class SetupWizardWindowDelegateProxy: NSObject, NSWindowDelegate {
    static let shared = SetupWizardWindowDelegateProxy()
    func windowWillClose(_ notification: Notification) {
        SetupWizardWindowController.shared.windowDidClose()
    }
}
