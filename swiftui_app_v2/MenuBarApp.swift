//
//  MenuBarApp.swift
//  Cloud to Ground AI — v0.2 (architecture-corrected)
//
//  Top-level menu bar app. No dock icon (LSUIElement = true in Info.plist).
//  The status item is the user's primary surface; status panel, Ground chat,
//  and settings open as windows from the menu.
//
//  Implements:
//    L2-GUI-009 (menu bar status indicator).
//
//  Initial draft of the AppDelegate class structure was delegated to
//  granite4.1:8b on 2026-06-28 via the C2G bridge. Bugs caught and patched
//  here: missing imports, missing @NSApplicationDelegateAdaptor in the
//  @main struct, weak-vs-strong NSStatusItem lifetime mistake (NSStatusItem
//  must be strongly held), invalid top-level instantiation line, and
//  explicit menu-item targets needed for selector dispatch.
//  Outcome: patched. See granite4.1.md tuning file for the lifetime-of-AppKit-
//  objects pattern entry derived from this delegation.
//

import AppKit
import SwiftUI

@main
struct C2GApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Settings scene with EmptyView so SwiftUI does not open a default
        // window at launch. The real settings UI opens via the menu.
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    // STRONG reference — NSStatusBar does not retain the status item, the
    // owning object must. If this were `weak`, the item would deallocate
    // immediately after creation and the icon would never appear.
    var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item

        if let button = item.button {
            button.image = NSImage(systemSymbolName: "leaf.fill",
                                   accessibilityDescription: "Cloud to Ground AI")
            button.image?.isTemplate = true   // auto-themes light/dark
            button.toolTip = "Cloud to Ground AI — bridge active"
        }

        item.menu = buildMenu()

        // Start background services
        NetworkMonitor.shared.start()

        // First probe so the menu icon and status reflect reality from launch
        Task {
            await BridgeStatus.shared.refresh()
        }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu(title: "Cloud to Ground AI")

        // Each NSMenuItem needs an explicit `target` because items attached
        // to an NSStatusItem do not naturally find AppDelegate via the
        // responder chain.
        let statusPanelItem = NSMenuItem(
            title: "Open Status Panel",
            action: #selector(openStatusPanel),
            keyEquivalent: "")
        statusPanelItem.target = self
        menu.addItem(statusPanelItem)

        let groundChatItem = NSMenuItem(
            title: "Open Ground Chat",
            action: #selector(openGroundChat),
            keyEquivalent: "")
        groundChatItem.target = self
        menu.addItem(groundChatItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Cloud to Ground AI",
            action: #selector(quit),
            keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    @objc func openStatusPanel() {
        StatusPanelWindowController.shared.showPanel()
    }

    @objc func openGroundChat() {
        GroundChatWindowController.shared.showWindow()
    }

    @objc func openSettings() {
        // TODO step 5: open the Settings window (L2-GUI-008 privacy panel)
        print("[C2G] openSettings (not yet implemented)")
    }

    @objc func quit() {
        NSApplication.shared.terminate(self)
    }
}
