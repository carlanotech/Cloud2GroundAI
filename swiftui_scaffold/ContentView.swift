//
//  ContentView.swift
//  Cloud to Ground AI
//
//  Main window layout: persistent status bar at top (mode indicator,
//  network status), conversation pane below, mode toggle at bottom.
//
//  Implements:
//    L2-GUI-002 (persistent mode indicator),
//    L2-GUI-004 (network status display),
//    L2-GUI-001 (no external runtime dependencies — uses SF Symbols + system fonts).
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var modeManager: ModeManager
    @EnvironmentObject var networkMonitor: NetworkMonitor
    @EnvironmentObject var conversationStore: ConversationStore

    @State private var showOnboarding = true   // Will be persisted to UserDefaults in real impl
    @State private var pendingDegradationNotice: DegradationNotice?

    var body: some View {
        VStack(spacing: 0) {
            // Top status bar — always visible (L2-GUI-002, L2-GUI-004)
            StatusBar()
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(NSColor.windowBackgroundColor))
                .overlay(Divider(), alignment: .bottom)

            // Optional in-flow degradation notice (L2-GUI-003)
            if let notice = pendingDegradationNotice {
                DegradationNoticeView(notice: notice) {
                    pendingDegradationNotice = nil
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Conversation pane
            ConversationView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Bottom mode toggle
            ModeToggle()
                .padding()
                .overlay(Divider(), alignment: .top)
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView(isPresented: $showOnboarding)
        }
        .onChange(of: modeManager.lastTransition) { _, transition in
            if let t = transition, t.isDowngrade {
                withAnimation { pendingDegradationNotice = DegradationNotice(from: t) }
            }
        }
    }
}

private struct StatusBar: View {
    var body: some View {
        HStack(spacing: 16) {
            ModeIndicator()
            NetworkStatusChip()
            Spacer()
            Text("Cloud to Ground AI")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(ModeManager())
        .environmentObject(NetworkMonitor())
        .environmentObject(ConversationStore())
}
