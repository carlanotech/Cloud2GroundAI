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

import AppKit
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

    /// Files the model offered in this message, if any. Only assistant
    /// messages are scanned; parsing is cheap and pure.
    private var offeredFiles: [ParsedFile] {
        guard message.role == .assistant else { return [] }
        return FileBlockParser.parse(message.content)
    }

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

            if !offeredFiles.isEmpty {
                FileSaveCards(files: offeredFiles)
                    .padding(.top, 4)
            }
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

// ─── Save-file cards (v1.7 Ground-chat output folder) ────────────────────

/// Shown under an assistant message that contains <<<FILE:>>> blocks.
/// Confirm-each: every Save is an explicit user click. "Save all" is a
/// single explicit action over the batch (auto-save stays deferred). All
/// writes go through GroundFileWriter, which enforces confinement,
/// no-overwrite, and size/count caps.
private struct FileSaveCards: View {
    let files: [ParsedFile]
    @ObservedObject private var prefs = Preferences.shared

    /// Per-file outcome text + whether it's an error (drives color).
    @State private var status: [UUID: (text: String, isError: Bool)] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "tray.and.arrow.down")
                    .foregroundStyle(.blue)
                Text(files.count == 1
                     ? "Granite offered 1 file"
                     : "Granite offered \(files.count) files")
                    .font(.caption.weight(.semibold))
                Spacer()
                if files.count > 1 {
                    Button("Save all…") { saveAll() }
                        .font(.caption)
                        .buttonStyle(.borderless)
                }
            }

            ForEach(files) { file in
                HStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(file.filename)
                            .font(.caption.monospaced())
                        if let s = status[file.id] {
                            Text(s.text)
                                .font(.caption2)
                                .foregroundStyle(s.isError ? .red : .green)
                        } else {
                            Text(byteLabel(file.contents))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button(isSaved(file) ? "Saved" : "Save…") { save(file) }
                        .font(.caption)
                        .buttonStyle(.borderless)
                        .disabled(isSaved(file))
                }
                .padding(6)
                .background(Color.secondary.opacity(0.06),
                            in: RoundedRectangle(cornerRadius: 5))
            }
        }
        .padding(8)
        .background(Color.blue.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }

    // ─── Actions ─────────────────────────────────────────────────────────

    private func isSaved(_ file: ParsedFile) -> Bool {
        if let s = status[file.id], !s.isError { return true }
        return false
    }

    private func save(_ file: ParsedFile) {
        guard let folder = ensureFolder() else { return }
        writeOne(file, to: folder)
    }

    private func saveAll() {
        guard let folder = ensureFolder() else { return }
        // Enforce the per-batch cap; skip already-saved files.
        for file in files.prefix(GroundFileWriter.maxFilesPerSave) where !isSaved(file) {
            writeOne(file, to: folder)
        }
    }

    private func writeOne(_ file: ParsedFile, to folder: URL) {
        do {
            let r = try GroundFileWriter.write(file, toFolder: folder)
            status[file.id] = r.renamed
                ? (text: "Saved as \(r.finalURL.lastPathComponent)", isError: false)
                : (text: "Saved to \(folder.lastPathComponent)/", isError: false)
        } catch {
            status[file.id] = (text: error.localizedDescription, isError: true)
        }
    }

    /// Return the chosen folder, prompting an NSOpenPanel the first time.
    private func ensureFolder() -> URL? {
        if let existing = prefs.groundOutputFolder,
           FileManager.default.fileExists(atPath: existing.path) {
            return existing
        }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose Output Folder"
        panel.message = "Pick a folder where Ground-chat files will be saved."
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        prefs.groundOutputFolder = url
        return url
    }

    private func byteLabel(_ s: String) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(s.utf8.count), countStyle: .file)
    }
}
