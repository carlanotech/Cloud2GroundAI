//
//  LocalAI.swift
//  Cloud to Ground AI
//
//  Protocol for the local AI backend (Ollama on localhost). The mock
//  implementation lets the rest of the app run; replace with a real
//  Ollama HTTP client before shipping.
//
//  Implements the interface side of:
//    L2-AI-001 (local conversational capability),
//    L2-AI-002 (context window adequacy),
//    L2-AI-004 (output usability for delegated tasks),
//    L2-AI-006 (attribution — local responses carry their identity),
//    L2-AI-007 (memory footprint of the resident model).
//

import Foundation

protocol LocalAI {
    var identity: Message.Attribution.AIIdentity { get }

    /// Whether the model is loaded and able to respond. UI should hide
    /// Ground/Hybrid as options when this is false (L2-OPS-001 — local
    /// model must be available before first Ground session).
    var isReady: Bool { get }

    func send(_ message: String, history: [Message]) async throws -> Response

    struct Response {
        let content: String
        let attribution: Message.Attribution
    }
}

final class MockLocalAI: LocalAI {
    let identity = Message.Attribution.AIIdentity(
        backend: .local,
        model: "granite-code-mock",
        modelVersion: "8b-0.1"
    )

    let isReady = true

    func send(_ message: String, history: [Message]) async throws -> Response {
        try await Task.sleep(for: .milliseconds(150))
        return Response(
            content: "[mock local response] re: \(message)",
            attribution: Message.Attribution(primary: identity, delegates: [])
        )
    }
}
