//
//  Message.swift
//  Cloud to Ground AI — v0.2
//
//  A single message in a Ground-chat conversation. No mode attribution
//  needed here — by definition a Ground chat message is from either the
//  user or the locally-installed Granite model.
//
//  Implements data side of L2-GUI-011 (Ground chat window).
//

import Foundation

struct Message: Identifiable, Equatable, Codable {
    let id: UUID
    let role: Role
    var content: String         // var because streaming responses grow
    let timestamp: Date

    enum Role: String, Codable, Equatable {
        case user
        case assistant
        case system   // for status messages: "Ollama not running", errors
    }

    init(role: Role, content: String, timestamp: Date = .now) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}
