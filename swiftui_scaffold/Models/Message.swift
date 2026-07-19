//
//  Message.swift
//  Cloud to Ground AI
//
//  A single message in a conversation thread, carrying the role (user or
//  assistant), the content, and — if assistant — full per-response
//  attribution: which AI(s) produced it.
//
//  Implements the data side of L2-AI-006 (per-response attribution).
//

import Foundation

struct Message: Identifiable, Codable, Equatable {
    let id: UUID
    let role: Role
    let content: String
    let timestamp: Date

    /// Non-nil for assistant messages only. Records which AI(s) produced
    /// the response. In Hybrid mode this can list both the cloud
    /// orchestrator and the local delegate(s).
    let attribution: Attribution?

    enum Role: String, Codable {
        case user
        case assistant
        case system
    }

    /// Per-response attribution. A response from a single backend is the
    /// common case; Hybrid mode may produce a response with both a cloud
    /// orchestrator and one or more local delegations recorded.
    struct Attribution: Codable, Equatable {
        let primary: AIIdentity
        let delegates: [AIIdentity]   // Empty unless Hybrid orchestration delegated subtasks

        struct AIIdentity: Codable, Equatable {
            let backend: Backend
            let model: String     // e.g. "claude-sonnet-4-6", "granite-code:8b"
            let modelVersion: String?

            enum Backend: String, Codable {
                case cloud
                case local
            }
        }
    }

    init(role: Role, content: String, attribution: Attribution? = nil, timestamp: Date = .now) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.attribution = attribution
        self.timestamp = timestamp
    }
}
