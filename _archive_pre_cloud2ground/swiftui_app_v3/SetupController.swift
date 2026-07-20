//
//  SetupController.swift
//  Cloud to Ground AI — v0.2 Setup Wizard
//
//  State machine + async install orchestration for the 6-step wizard.
//  The view (SetupWizardView) is purely presentational and binds to this
//  ObservableObject.
//
//  Implements L2-OPS-009 (skill auto-install) + L2-OPS-011 (LaunchAgent
//  registration). Implicitly also L2-AI-001 via the smoke test gate.
//
//  Step ordering rationale:
//    1. Ollama present — every later step needs it for runtime work.
//    2. Model pulled — heavy network step, do it before any local setup
//       so users can walk away during the download.
//    3. Skill copied to ~/.claude/skills/ — Cowork needs this to delegate.
//    4. Watcher script copied to ~/Library/Application Support/ — needed
//       before LaunchAgent registration so launchctl has a target.
//    5. LaunchAgent registered — finally hands the watcher off to launchd.
//    6. Smoke test — proves the whole stack works end-to-end.
//

import Combine
import Foundation

@MainActor
final class SetupController: ObservableObject {

    enum Step: Int, CaseIterable, Identifiable {
        case ollama
        case model
        case skill
        case watcherScript
        case launchAgent
        case smokeTest

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .ollama:        return "Install Ollama"
            case .model:         return "Pull \(SetupController.defaultModel)"
            case .skill:         return "Install delegate skill"
            case .watcherScript: return "Install watcher script"
            case .launchAgent:   return "Register background service"
            case .smokeTest:     return "Test the bridge"
            }
        }

        var indexLabel: String { "Step \(rawValue + 1) of \(Step.allCases.count)" }
    }

    enum StepState: Equatable {
        case pending      // not yet visited
        case checking     // running detection right now
        case alreadyDone  // detected as already in good shape
        case running      // user clicked Install, in progress
        case completed    // we ran the install and it succeeded
        case failed(String)
        case skipped
    }

    static let defaultModel = "granite4.1:8b"

    @Published var currentStep: Step = .ollama
    @Published var states: [Step: StepState] = Dictionary(
        uniqueKeysWithValues: Step.allCases.map { ($0, .pending) }
    )
    @Published var log: [LogLine] = []
    @Published var modelToInstall: String = SetupController.defaultModel

    /// The smoke-test transcript, populated when step 6 runs.
    @Published var smokeTestTranscript: String = ""
    @Published var smokeTestPassed: Bool = false

    /// Are we currently doing something async (used to disable Back/Next)?
    @Published var busy: Bool = false

    struct LogLine: Identifiable, Equatable {
        let id = UUID()
        let timestamp: Date
        let text: String
        let level: Level
        enum Level { case info, success, warn, error }
    }

    // ─── Navigation ──────────────────────────────────────────────────────

    func goToFirstUnfinishedStep() async {
        for step in Step.allCases {
            await detect(step: step)
            let s = states[step] ?? .pending
            if !(s == .alreadyDone || s == .completed) {
                currentStep = step
                return
            }
        }
        currentStep = .smokeTest
    }

    func next() {
        let all = Step.allCases
        guard let idx = all.firstIndex(of: currentStep), idx + 1 < all.count
        else { return }
        currentStep = all[idx + 1]
        Task { await detect(step: currentStep) }
    }

    func back() {
        let all = Step.allCases
        guard let idx = all.firstIndex(of: currentStep), idx > 0 else { return }
        currentStep = all[idx - 1]
    }

    func canAdvance() -> Bool {
        switch states[currentStep] ?? .pending {
        case .alreadyDone, .completed, .skipped: return true
        default: return false
        }
    }

    // ─── Detection ───────────────────────────────────────────────────────

    /// Probe whether a step is already satisfied. Idempotent — safe to call
    /// repeatedly. Updates `states[step]`.
    func detect(step: Step) async {
        states[step] = .checking
        switch step {
        case .ollama:
            switch OllamaInstaller.detect() {
            case .alreadyInstalled(let path):
                appendLog("Ollama detected at \(path)", level: .success)
                states[step] = .alreadyDone
            case .homebrewAvailable:
                appendLog("Homebrew available; Ollama not yet installed.",
                          level: .info)
                states[step] = .pending
            case .needsManualInstall:
                appendLog("Neither Ollama nor Homebrew detected.", level: .warn)
                states[step] = .pending
            }

        case .model:
            // Detect via BridgeProbe.probeModel() — returns the granite4.1
            // entry from `ollama list` if present.
            if let info = await BridgeProbe.probeModel(),
               info.name.lowercased().hasPrefix("granite4.1") {
                appendLog("Model \(info.name) is installed (\(info.sizeMB) MB).",
                          level: .success)
                states[step] = .alreadyDone
            } else {
                appendLog("\(modelToInstall) not yet pulled.", level: .info)
                states[step] = .pending
            }

        case .skill:
            if SkillInstaller.isInstalled(),
               let v = SkillInstaller.readInstalledVersion() {
                appendLog("Skill installed (version \(v)).", level: .success)
                states[step] = .alreadyDone
            } else {
                states[step] = .pending
            }

        case .watcherScript:
            if WatcherScriptInstaller.isInstalled() {
                appendLog("Watcher script installed at \(WatcherScriptInstaller.installedScriptURL.path).",
                          level: .success)
                states[step] = .alreadyDone
            } else {
                states[step] = .pending
            }

        case .launchAgent:
            if LaunchAgentInstaller.isInstalled() {
                do {
                    let loaded = try await LaunchAgentInstaller.isLoaded()
                    appendLog("LaunchAgent plist present; loaded=\(loaded).",
                              level: loaded ? .success : .warn)
                    states[step] = loaded ? .alreadyDone : .pending
                } catch {
                    states[step] = .pending
                }
            } else {
                states[step] = .pending
            }

        case .smokeTest:
            // Can only detect "we've never run" — don't auto-run.
            if smokeTestPassed {
                states[step] = .completed
            } else {
                states[step] = .pending
            }
        }
    }

    // ─── Actions ─────────────────────────────────────────────────────────

    func runCurrentStep() async {
        await runStep(currentStep)
    }

    func runStep(_ step: Step) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        states[step] = .running

        do {
            switch step {
            case .ollama:
                try await OllamaInstaller.installViaHomebrew { [weak self] line in
                    Task { @MainActor in
                        self?.appendLog(line, level: .info)
                    }
                }
            case .model:
                try await OllamaInstaller.ensureServeRunning()
                try await OllamaInstaller.pullModel(modelToInstall) { [weak self] line in
                    Task { @MainActor in
                        self?.appendLog(line, level: .info)
                    }
                }
            case .skill:
                let summary = try SkillInstaller.install()
                let prev = summary.previousVersion ?? "none"
                appendLog("Skill installed: \(prev) → \(summary.installedVersion) (\(summary.filesCopied) files).",
                          level: .success)
            case .watcherScript:
                try WatcherScriptInstaller.install()
                appendLog("Watcher script written to \(WatcherScriptInstaller.installedScriptURL.path).",
                          level: .success)
            case .launchAgent:
                try await LaunchAgentInstaller.install()
                appendLog("LaunchAgent registered as \(LaunchAgentInstaller.label).",
                          level: .success)
            case .smokeTest:
                // Make sure Ollama is up first; the LaunchAgent should be
                // running the watcher by now.
                try await OllamaInstaller.ensureServeRunning()
                let result = await BridgeSmokeTest.run()
                smokeTestTranscript = result.transcript
                smokeTestPassed = result.passed
                appendLog(result.detail,
                          level: result.passed ? .success : .error)
                if result.passed {
                    states[step] = .completed
                } else {
                    states[step] = .failed(result.detail)
                }
                return
            }
            states[step] = .completed
        } catch {
            appendLog("Failed: \(error.localizedDescription)", level: .error)
            states[step] = .failed(error.localizedDescription)
        }
    }

    func skipCurrentStep() {
        states[currentStep] = .skipped
        appendLog("\(currentStep.title) — skipped.", level: .warn)
    }

    // ─── Log helpers ─────────────────────────────────────────────────────

    private func appendLog(_ text: String, level: LogLine.Level) {
        log.append(LogLine(timestamp: Date(), text: text, level: level))
        // Cap log size to keep memory + UI happy.
        if log.count > 500 {
            log.removeFirst(log.count - 500)
        }
    }
}
