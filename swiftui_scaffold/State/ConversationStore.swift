//
//  ConversationStore.swift
//  Cloud to Ground AI
//
//  Holds the set of threads and the active thread. Enforces the
//  L2-MOD-002 invariant by starting a new thread on every mode change.
//
//  Implements the storage side of L2-AI-006 (attribution per response is
//  stored on the Message, which lives in the active thread).
//

import Combine
import SwiftUI

@MainActor
final class ConversationStore: ObservableObject {
    @Published private(set) var threads: [ConversationThread] = []
    @Published private(set) var activeThreadID: UUID?

    init() {
        // Start a fresh thread in the default mode.
        startNewThread(mode: .hybrid)
    }

    var activeThread: ConversationThread? {
        guard let id = activeThreadID else { return nil }
        return threads.first(where: { $0.id == id })
    }

    func startNewThread(mode: OperatingMode, title: String? = nil) {
        let t = ConversationThread(mode: mode, title: title)
        threads.append(t)
        activeThreadID = t.id
    }

    /// Append a message to the active thread. Refuses if the message's
    /// AI backend disagrees with the thread's mode (per the L2-MOD-002
    /// invariant: a thread is bound to a single AI for its lifetime).
    func appendToActive(_ message: Message) {
        guard var thread = activeThread else { return }
        if let attribution = message.attribution {
            let primaryBackend = attribution.primary.backend
            if !attribution.matches(mode: thread.mode) {
                // Caller asked us to attach a response from the wrong
                // backend for this thread — that violates L2-MOD-002.
                // Start a new thread to preserve the invariant.
                startNewThread(mode: backendToMode(primaryBackend))
                appendToActive(message)
                return
            }
        }
        thread.messages.append(message)
        if let idx = threads.firstIndex(where: { $0.id == thread.id }) {
            threads[idx] = thread
        }
    }

    private func backendToMode(_ backend: Message.Attribution.AIIdentity.Backend) -> OperatingMode {
        switch backend {
        case .cloud: return .cloud
        case .local: return .ground
        }
    }
}

extension Message.Attribution {
    /// Whether this attribution is acceptable for a thread bound to
    /// `mode`. In Cloud/Ground modes, the primary backend must match
    /// the mode's backend. In Hybrid, cloud is primary and locals
    /// can appear as delegates.
    func matches(mode: OperatingMode) -> Bool {
        switch mode {
        case .cloud:
            return primary.backend == .cloud && delegates.isEmpty
        case .hybrid:
            return primary.backend == .cloud   // delegates are fine
        case .ground:
            return primary.backend == .local && delegates.isEmpty
        }
    }
}
