//
//  ConversationThread.swift
//  Cloud to Ground AI
//
//  A conversation thread. Per L2-MOD-002, every thread is bound to a
//  single operating mode for its lifetime; a mode change starts a new
//  thread. This type encodes that invariant by making `mode` a let.
//
//  Named ConversationThread (not Thread) to avoid clashing with
//  Foundation.Thread.
//

import Foundation

struct ConversationThread: Identifiable, Codable, Equatable {
    let id: UUID
    let mode: OperatingMode            // Immutable — enforces L2-MOD-002
    let createdAt: Date
    var messages: [Message]
    var title: String?

    init(mode: OperatingMode, title: String? = nil) {
        self.id = UUID()
        self.mode = mode
        self.createdAt = .now
        self.messages = []
        self.title = title
    }
}
