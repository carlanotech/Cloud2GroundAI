//
//  ModeManager.swift
//  Cloud to Ground AI
//
//  Owns the operating-mode state machine. Single source of truth for
//  which mode is active. Coordinates with NetworkMonitor for safe-direction
//  automatic transitions (online -> Ground only).
//
//  Implements:
//    L2-MOD-001 (Ground mode capability — state side),
//    L2-MOD-002 (atomic, user-visible transitions; fresh thread on change).
//
//  Note: this class does NOT own the conversation store. When a mode
//  change happens it publishes a transition; the ConversationStore
//  observes that and starts a new thread.
//

import Combine
import SwiftUI

@MainActor
final class ModeManager: ObservableObject {
    @Published private(set) var currentMode: OperatingMode = .hybrid
    @Published private(set) var lastTransition: ModeTransition?

    private var networkCancellable: AnyCancellable?

    /// Toggle the mode in response to direct user action. Always wins
    /// over automatic transitions.
    func userSelect(_ newMode: OperatingMode) {
        guard newMode != currentMode else { return }
        applyTransition(to: newMode, source: .user)
    }

    /// Wire in the network monitor for safe-direction automatic
    /// transitions. Only online -> Ground fires automatically. Coming
    /// back online never auto-upgrades because changing the answering
    /// AI silently would violate PRD-003.
    func attach(networkMonitor: NetworkMonitor) {
        networkCancellable = networkMonitor.$status
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                guard let self else { return }
                if status == .offline && self.currentMode != .ground {
                    self.applyTransition(to: .ground, source: .networkDrop)
                }
            }
    }

    private func applyTransition(to newMode: OperatingMode, source: ModeTransition.Source) {
        let from = currentMode
        currentMode = newMode
        lastTransition = ModeTransition(
            from: from,
            to: newMode,
            source: source,
            at: .now
        )
    }
}

struct ModeTransition: Equatable {
    let from: OperatingMode
    let to: OperatingMode
    let source: Source
    let at: Date

    enum Source: String, Equatable {
        case user
        case networkDrop
    }

    var isDowngrade: Bool {
        to.capabilityRank < from.capabilityRank
    }
}
