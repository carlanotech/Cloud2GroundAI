//
//  GroundChatWindowController.swift
//  Cloud to Ground AI — v0.2
//
//  Owns the Ground chat window so multiple menu-item clicks don't open
//  duplicate windows. Same pattern as StatusPanelWindowController.
//

import AppKit
import SwiftUI

@MainActor
final class GroundChatWindowController {
    static let shared = GroundChatWindowController()

    private var window: NSWindow?
    private let conversation = Conversation()

    private init() {}

    func showWindow() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        let view = GroundChatView(
            conversation: conversation,
            status: BridgeStatus.shared
        )
        let hostingController = NSHostingController(rootView: view)

        let win = NSWindow(contentViewController: hostingController)
        win.title = "Cloud to Ground AI — Ground Chat"
        win.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        win.setContentSize(NSSize(width: 540, height: 600))
        win.center()
        win.isReleasedWhenClosed = false
        win.delegate = GroundChatWindowDelegateProxy.shared

        window = win

        win.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    fileprivate func windowDidClose() {
        window = nil
        // Don't reset the conversation on close — user expects it to be
        // there when they reopen. Reset is explicit via menu (future).
    }
}

@MainActor
final class GroundChatWindowDelegateProxy: NSObject, NSWindowDelegate {
    static let shared = GroundChatWindowDelegateProxy()
    func windowWillClose(_ notification: Notification) {
        GroundChatWindowController.shared.windowDidClose()
    }
}
