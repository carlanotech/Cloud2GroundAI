//
//  GroundChatView.swift
//  Cloud to Ground AI — v0.2
//
//  The Ground-mode chat window. Talks only to the locally-installed
//  Granite model via LocalOllamaClient. When Ollama is down, the view
//  shows a "Ollama not running" banner with a hint.
//
//  Implements L2-GUI-011 (Ground chat window) + the user-visible side of
//  L2-AI-001 (5-turn coherent conversation).
//

import Combine
import SwiftUI

struct GroundChatView: View {
    @ObservedObject var conversation: Conversation
    @ObservedObject var status: BridgeStatus
    @State private var draft: String = ""
    @FocusState private var composerFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if case .running = status.ollamaRunning {
                EmptyView()
            } else {
                ollamaWarningBanner
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if conversation.messages.isEmpty {
                            emptyState
                        }
                        ForEach(conversation.messages) { msg in
                            MessageRow(message: msg)
                                .id(msg.id)
                        }
                        if conversation.isWaitingForResponse {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("Granite is thinking…")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.leading, 8)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                }
                .onChange(of: conversation.messages.count) { _, _ in
                    if let last = conversation.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            if let err = conversation.lastError {
                errorBanner(err)
            }

            Divider()

            composer
        }
        .frame(minWidth: 480, minHeight: 540)
        .navigationTitle("Ground Chat — granite4.1")
    }

    // ─── Subviews ───────────────────────────────────────────────────────

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ground mode")
                .font(.headline)
            Text("You're talking to the locally-installed Granite model on your own Mac. No data leaves this machine in this conversation.")
                .foregroundStyle(.secondary)
                .font(.callout)
            Text("Best for short questions, code tasks, and quick reasoning. Granite is competent but not as capable as Claude — keep that in mind for complex or factual work.")
                .foregroundStyle(.secondary)
                .font(.callout)
        }
        .padding()
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    private var ollamaWarningBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Ollama is not running")
                    .font(.callout).fontWeight(.medium)
                Text("Start Ollama (or run `ollama serve` in Terminal) to use Ground mode.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(8)
        .background(Color.orange.opacity(0.10))
        .overlay(Divider(), alignment: .bottom)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
            Text(message).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Dismiss") { conversation.lastError = nil }
                .buttonStyle(.borderless)
                .font(.caption)
        }
        .padding(8)
        .background(Color.red.opacity(0.08))
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Message Granite",
                      text: $draft,
                      axis: .vertical)
                .lineLimit(1...6)
                .textFieldStyle(.roundedBorder)
                .focused($composerFocused)
                .onSubmit { Task { await send() } }
                .disabled(conversation.isWaitingForResponse)
            Button {
                Task { await send() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.borderless)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      || conversation.isWaitingForResponse)
        }
        .padding(12)
        .onAppear { composerFocused = true }
    }

    // ─── Actions ────────────────────────────────────────────────────────

    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !conversation.isWaitingForResponse else { return }
        draft = ""

        let userMessage = Message(role: .user, content: text)
        conversation.append(userMessage)

        conversation.isWaitingForResponse = true
        defer { conversation.isWaitingForResponse = false }

        // Pick the model from BridgeStatus if known, else fall back to a default.
        let modelName: String
        if let m = status.modelLoaded {
            modelName = m.name
        } else {
            modelName = "granite4.1:8b"
        }

        do {
            let reply = try await LocalOllamaClient.chat(
                model: modelName,
                history: conversation.ollamaHistory
            )
            conversation.append(Message(role: .assistant, content: reply))
        } catch {
            conversation.lastError = error.localizedDescription
        }
    }
}

// ─── Message row ────────────────────────────────────────────────────────

private struct MessageRow: View {
    let message: Message

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(roleLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(message.content)
                .textSelection(.enabled)
                .font(.system(size: 13))
        }
        .padding(10)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 6))
    }

    private var roleLabel: String {
        switch message.role {
        case .user:      return "You"
        case .assistant: return "Granite"
        case .system:    return "System"
        }
    }

    private var rowBackground: Color {
        switch message.role {
        case .user:      return .secondary.opacity(0.08)
        case .assistant: return .clear
        case .system:    return .orange.opacity(0.08)
        }
    }
}
