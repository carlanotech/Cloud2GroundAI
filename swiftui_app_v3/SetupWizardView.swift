//
//  SetupWizardView.swift
//  Cloud to Ground AI — v0.2 Setup Wizard
//
//  6-step wizard window. Left rail = step list with checkmarks. Main
//  pane = current step's content (description, install button, skip,
//  next). Bottom = scrollable log of all output across the session.
//
//  Implements L2-GUI-008-style first-run flow.
//

import Combine
import SwiftUI

struct SetupWizardView: View {
    @ObservedObject var controller: SetupController

    var body: some View {
        HStack(spacing: 0) {
            stepRail
                .frame(width: 220)
                .background(Color.secondary.opacity(0.05))

            Divider()

            VStack(spacing: 0) {
                stepHeader
                    .padding()
                Divider()

                stepBody
                    .padding(.horizontal)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                Divider()
                logPane
                    .frame(height: 160)

                Divider()
                footer
                    .padding(.horizontal)
                    .padding(.vertical, 10)
            }
        }
        .frame(minWidth: 760, minHeight: 560)
        .task {
            await controller.goToFirstUnfinishedStep()
        }
    }

    // ─── Step rail ───────────────────────────────────────────────────────

    private var stepRail: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Setup")
                .font(.title3.weight(.semibold))
                .padding(.horizontal)
                .padding(.top, 14)
                .padding(.bottom, 8)

            ForEach(SetupController.Step.allCases) { step in
                stepRailRow(for: step)
            }

            Spacer()
        }
    }

    private func stepRailRow(for step: SetupController.Step) -> some View {
        let state = controller.states[step] ?? .pending
        let isCurrent = step == controller.currentStep

        return HStack(spacing: 8) {
            stateBadge(state)
                .frame(width: 16)
            Text(step.title)
                .font(.callout)
                .fontWeight(isCurrent ? .semibold : .regular)
                .foregroundStyle(isCurrent ? Color.primary : Color.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal)
        .background(isCurrent
                    ? Color.accentColor.opacity(0.12)
                    : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            controller.currentStep = step
            Task { await controller.detect(step: step) }
        }
    }

    @ViewBuilder
    private func stateBadge(_ state: SetupController.StepState) -> some View {
        switch state {
        case .pending:
            Image(systemName: "circle")
                .foregroundStyle(.tertiary)
        case .checking:
            ProgressView().controlSize(.mini)
        case .alreadyDone, .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .running:
            ProgressView().controlSize(.mini)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        case .skipped:
            Image(systemName: "minus.circle")
                .foregroundStyle(.orange)
        }
    }

    // ─── Step header ─────────────────────────────────────────────────────

    private var stepHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(controller.currentStep.indexLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(controller.currentStep.title)
                .font(.title2.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // ─── Step body ───────────────────────────────────────────────────────

    @ViewBuilder
    private var stepBody: some View {
        switch controller.currentStep {
        case .ollama:        ollamaStepBody
        case .model:         modelStepBody
        case .skill:         skillStepBody
        case .watcherScript: watcherStepBody
        case .launchAgent:   launchAgentStepBody
        case .smokeTest:     smokeTestStepBody
        }
    }

    private var ollamaStepBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Cloud to Ground AI needs Ollama installed to host the local Granite model. The simplest install path is via Homebrew (`brew install ollama`).")
                .foregroundStyle(.secondary)
            switch controller.states[.ollama] ?? .pending {
            case .alreadyDone:
                Label("Ollama is already installed.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .failed(let msg):
                Label(msg, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            default:
                EmptyView()
            }
            Spacer().frame(height: 6)
            HStack {
                Button("Install via Homebrew") {
                    Task { await controller.runCurrentStep() }
                }
                .disabled(controller.busy)
                Link("Or download from ollama.com",
                     destination: URL(string: "https://ollama.com/download")!)
                    .font(.callout)
            }
        }
    }

    private var modelStepBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pulling \(controller.modelToInstall). This is a one-time download of about 5–17 GB depending on tier. You can leave this running and come back.")
                .foregroundStyle(.secondary)
            Picker("Model tier", selection: $controller.modelToInstall) {
                Text("granite4.1:8b  (5.4 GB, balanced)").tag("granite4.1:8b")
                Text("granite4.1:30b  (~17 GB, higher quality)").tag("granite4.1:30b")
            }
            .pickerStyle(.radioGroup)
            .disabled(controller.busy)

            Button("Pull \(controller.modelToInstall)") {
                Task { await controller.runCurrentStep() }
            }
            .disabled(controller.busy)
        }
    }

    private var skillStepBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Installs the ollama-delegate skill into ~/.claude/skills/ so Cowork can find and invoke it. Safe to re-run — overwrites any previous version with the one shipped in this build.")
                .foregroundStyle(.secondary)
            Button("Install skill") {
                Task { await controller.runCurrentStep() }
            }
            .disabled(controller.busy)
        }
    }

    private var watcherStepBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Copies start_local_ai.sh to ~/Library/Application Support/claude_bridge/ — a launchd-friendly location that sidesteps the TCC restrictions on ~/Documents. The IPC bridge folder under ~/Documents/claude_bridge/_bridge is also created.")
                .foregroundStyle(.secondary)
            Button("Install watcher script") {
                Task { await controller.runCurrentStep() }
            }
            .disabled(controller.busy)
        }
    }

    private var launchAgentStepBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Registers the watcher as a per-user LaunchAgent so it auto-starts at login and restarts on crash. Writes \(LaunchAgentInstaller.installedPlistURL.path).")
                .foregroundStyle(.secondary)
            HStack {
                Button("Register LaunchAgent") {
                    Task { await controller.runCurrentStep() }
                }
                .disabled(controller.busy)
                Button("Uninstall") {
                    Task {
                        do { try await LaunchAgentInstaller.uninstall() }
                        catch { /* logged by next refresh */ }
                        await controller.detect(step: .launchAgent)
                    }
                }
                .disabled(controller.busy)
            }
        }
    }

    private var smokeTestStepBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Writes a real request to the bridge and waits for the watcher to answer. This is the only step that proves the whole stack — Cowork → skill → bridge → watcher → Ollama → response — is wired correctly.")
                .foregroundStyle(.secondary)
            Button("Run smoke test") {
                Task { await controller.runCurrentStep() }
            }
            .disabled(controller.busy)

            if !controller.smokeTestTranscript.isEmpty {
                Text("Transcript")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
                ScrollView {
                    Text(controller.smokeTestTranscript)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 120)
                .background(Color.secondary.opacity(0.06),
                            in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    // ─── Log pane ────────────────────────────────────────────────────────

    private var logPane: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(controller.log) { line in
                        HStack(spacing: 6) {
                            Text(line.timestamp, style: .time)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.tertiary)
                            Text(line.text)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(color(for: line.level))
                                .textSelection(.enabled)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal)
                        .id(line.id)
                    }
                }
                .padding(.vertical, 6)
            }
            .onChange(of: controller.log.count) { _, _ in
                if let last = controller.log.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private func color(for level: SetupController.LogLine.Level) -> Color {
        switch level {
        case .info:    return .primary
        case .success: return .green
        case .warn:    return .orange
        case .error:   return .red
        }
    }

    // ─── Footer ──────────────────────────────────────────────────────────

    private var footer: some View {
        HStack {
            Button("Back") {
                controller.back()
            }
            .disabled(controller.busy || controller.currentStep == .ollama)

            Spacer()

            Button("Skip") {
                controller.skipCurrentStep()
            }
            .disabled(controller.busy)

            Button(controller.currentStep == .smokeTest ? "Finish" : "Next") {
                if controller.currentStep == .smokeTest {
                    NSApp.keyWindow?.close()
                } else {
                    controller.next()
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!controller.canAdvance() || controller.busy)
        }
    }
}
