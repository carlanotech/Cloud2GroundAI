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

    /// Standing instruction that lets Ground mode offer saveable files.
    /// Terse on purpose — granite follows short directives more reliably
    /// than verbose ones (see skill/models/granite4.1.md). The app's
    /// FileBlockParser looks for exactly these markers.
    static let fileFormatSystemPrompt = """
    When you produce a COMPLETE file the user would save to disk (a script, \
    module, config, or document), wrap only that file's contents between two \
    markers, each on its own line:
    <<<FILE: filename.ext>>>
    ...file contents...
    <<<END>>>
    One block per file, always with a real filename. For explanations, inline \
    snippets, or partial edits, answer normally with no markers.
    """

    /// History formatted for the Ollama /api/chat endpoint. A system message
    /// carrying the file-block instruction is prepended on every request so
    /// the Save-file cards can work; user-authored system messages (none
    /// today) are still excluded from the mapped turns.
    var ollamaHistory: [[String: String]] {
        var out: [[String: String]] = [[
            "role": "system",
            "content": Self.fileFormatSystemPrompt,
        ]]
        out.append(contentsOf: messages
            .filter { $0.role != .system }
            .map { [
                "role": $0.role.rawValue,
                "content": $0.content,
            ] })
        return out
    }
}
