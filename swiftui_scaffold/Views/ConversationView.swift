//
//  ConversationView.swift
//  Cloud to Ground AI
//
//  The actual conversation pane: a scrollable message list plus a
//  message-composition area at the bottom. Each assistant message
//  shows its attribution chip (which AI produced it) per L2-AI-006.
//

import SwiftUI

struct ConversationView: View {
    @EnvironmentObject var modeManager: ModeManager
    @EnvironmentObject var conversationStore: ConversationStore

    @State private var draft: String = ""
    @State private var sending = false

    // Mock AI backends. In a real build these would be injected.
    private let cloudAI: CloudAI = MockCloudAI()
    private let localAI: LocalAI = MockLocalAI()

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if let thread = conversationStore.activeThread {
                        ForEach(thread.messages) { msg in
                            MessageRow(message: msg)
                        }
                    } else {
                        Text("Start a new conversation.")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .frame(maxHeight: .infinity)

            Divider()

            HStack {
                TextField("Type a message", text: $draft, axis: .vertical)
                    .lineLimit(1...6)
                    .textFieldStyle(.roundedBorder)
                    .disabled(sending)
                    .onSubmit { Task { await send() } }
                Button {
                    Task { await send() }
                } label: {
                    Image(systemName: sending ? "ellipsis" : "arrow.up.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.borderless)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
            }
            .padding(12)
        }
    }

    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        sending = true
        defer { sending = false }
        draft = ""

        let userMsg = Message(role: .user, content: text)
        conversationStore.appendToActive(userMsg)

        let history = conversationStore.activeThread?.messages ?? []
        do {
            let response: (content: String, attribution: Message.Attribution)
            switch modeManager.currentMode {
            case .cloud:
                let r = try await cloudAI.send(text, history: history)
                response = (r.content, r.attribution)
            case .hybrid:
                let r = try await cloudAI.send(text, history: history)
                response = (r.content, r.attribution)
            case .ground:
                let r = try await localAI.send(text, history: history)
                response = (r.content, r.attribution)
            }
            conversationStore.appendToActive(Message(
                role: .assistant,
                content: response.content,
                attribution: response.attribution
            ))
        } catch {
            conversationStore.appendToActive(Message(
                role: .system,
                content: "Error: \(error.localizedDescription)"
            ))
        }
    }
}

private struct MessageRow: View {
    let message: Message

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(roleLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                if let attr = message.attribution {
                    AttributionChip(attribution: attr)
                }
                Spacer()
                Text(message.timestamp, style: .time)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            Text(message.content)
                .textSelection(.enabled)
                .font(.system(size: 13))
        }
        .padding(8)
        .background(message.role == .user ? Color.gray.opacity(0.08) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var roleLabel: String {
        switch message.role {
        case .user:      return "You"
        case .assistant: return "Assistant"
        case .system:    return "System"
        }
    }
}

private struct AttributionChip: View {
    let attribution: Message.Attribution

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: attribution.primary.backend == .cloud ? "cloud.fill" : "leaf.fill")
                .font(.system(size: 9))
            Text(attribution.primary.model)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
            if !attribution.delegates.isEmpty {
                Text("+\(attribution.delegates.count)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.secondary.opacity(0.1), in: Capsule())
    }
}
