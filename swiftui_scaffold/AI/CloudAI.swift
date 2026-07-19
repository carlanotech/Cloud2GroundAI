//
//  CloudAI.swift
//  Cloud to Ground AI
//
//  Protocol for the cloud AI backend (Anthropic API). Wrapped so the
//  rest of the app talks to a protocol, not to URLSession directly —
//  see Architecture Sketch §7 for why.
//
//  Implements the interface side of L2-AI-005 (Hybrid stream) and
//  L2-AI-006 (attribution — cloud responses carry their identity).
//

import Foundation

protocol CloudAI {
    var identity: Message.Attribution.AIIdentity { get }

    /// Send a message and the prior conversation history. The cloud
    /// model may, in Hybrid orchestration, decide to call out to a
    /// `LocalAI` via the orchestrator wiring. Delegations are recorded
    /// on the returned Attribution.
    func send(_ message: String, history: [Message]) async throws -> Response

    struct Response {
        let content: String
        let attribution: Message.Attribution
    }
}

/// Mock implementation. Lets the rest of the app compile and run
/// without an API key or a network. Replace with a real Anthropic
/// API client before shipping.
final class MockCloudAI: CloudAI {
    let identity = Message.Attribution.AIIdentity(
        backend: .cloud,
        model: "claude-mock",
        modelVersion: "0.1"
    )

    func send(_ message: String, history: [Message]) async throws -> Response {
        try await Task.sleep(for: .milliseconds(300))
        return Response(
            content: "[mock cloud response] You said: \(message)",
            attribution: Message.Attribution(primary: identity, delegates: [])
        )
    }
}
