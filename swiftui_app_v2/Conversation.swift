//
//  Conversation.swift
//  Cloud to Ground AI — v0.2
//
//  In-memory conversation state for the Ground chat. Persistence is a v1.1
//  feature — for v1.0 the conversation is session-scoped (lost when the
//  user closes the window).
//
//  Implements state side of L2-GUI-011 (Ground chat window).
//

import Combine
import Foundation

@MainActor
final class Conversation: ObservableObject {
    @Published var messages: [Message] = []
    @Published var isWaitingForResponse: Bool = false
    @Published var lastError: String? = nil

    func append(_ m: Message) {
        messages.append(m)
    }

    func reset() {
        messages.removeAll()
        lastError = nil
    }

    /// History formatted for the Ollama /api/chat endpoint.
    var ollamaHistory: [[String: String]] {
        messages
            .filter { $0.role != .system }
            .map { [
                "role": $0.role.rawValue,
                "content": $0.content,
            ] }
    }
}
