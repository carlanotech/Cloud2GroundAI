//
//  C2GApp.swift
//  Cloud to Ground AI
//
//  App entry point. Wires the global state objects (ModeManager,
//  NetworkMonitor, ConversationStore) into the SwiftUI environment.
//
//  Implements: app skeleton for L2-MOD-001 (Ground mode capability) and
//  L2-GUI-001 (offline-capable UI — no external runtime dependencies).
//

import SwiftUI

@main
struct C2GApp: App {
    @StateObject private var modeManager = ModeManager()
    @StateObject private var networkMonitor = NetworkMonitor()
    @StateObject private var conversationStore = ConversationStore()

    var body: some Scene {
        WindowGroup("Cloud to Ground AI") {
            ContentView()
                .environmentObject(modeManager)
                .environmentObject(networkMonitor)
                .environmentObject(conversationStore)
                .frame(minWidth: 720, minHeight: 480)
                .onAppear {
                    // Wire the network monitor into the mode manager so a
                    // network drop can force the safe-direction transition
                    // (online -> Ground). The reverse never auto-fires.
                    modeManager.attach(networkMonitor: networkMonitor)
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Conversation") {
                    conversationStore.startNewThread(mode: modeManager.currentMode)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(modeManager)
        }
    }
}
