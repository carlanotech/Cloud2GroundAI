//
//  OllamaInstaller.swift
//  Cloud to Ground AI — v0.2 Setup Wizard support
//
//  Detects and installs Ollama, pulls the chosen Granite model.
//
//  Strategy:
//    1. Check BridgeProbe.findOllamaBinary() — if present, skip install.
//    2. If absent: prefer Homebrew install (`brew install ollama`). If
//       Homebrew isn't installed either, surface a link to ollama.com/download
//       rather than trying to install Homebrew ourselves (Homebrew install
//       wants sudo on first run, which we can't drive from inside the app).
//    3. Once Ollama is present, run `ollama pull <model>` and stream
//       progress lines back to the caller.
//
//  This file does the work; the wizard UI shells out via async sequences.
//

import Foundation

enum OllamaInstaller {

    enum InstallPath {
        case alreadyInstalled(binaryPath: String)
        case homebrewAvailable
        case needsManualInstall  // user must download from ollama.com
    }

    /// Detect what's available without touching anything.
    static func detect() -> InstallPath {
        if let bin = findOllamaBinary() {
            return .alreadyInstalled(binaryPath: bin)
        }
        if findHomebrewBinary() != nil {
            return .homebrewAvailable
        }
        return .needsManualInstall
    }

    /// Run `brew install ollama`. Streams brew's output line-by-line.
    /// Throws if brew isn't installed or the install fails.
    static func installViaHomebrew(progress: @escaping @Sendable (String) -> Void)
    async throws {
        guard let brewPath = findHomebrewBinary() else {
            throw InstallError.homebrewNotAvailable
        }
        try await runStreaming(
            executable: brewPath,
            args: ["install", "ollama"],
            progress: progress
        )
    }

    /// Pull a model via `ollama pull <name>`. Streams Ollama's progress.
    /// Common model names:
    ///   - "granite4.1:8b" (default, 5.4 GB)
    ///   - "granite4.1:30b" (larger tier, ~17 GB)
    ///   - "granite-code:8b" (legacy)
    static func pullModel(_ modelName: String,
                          progress: @escaping @Sendable (String) -> Void)
    async throws {
        guard let ollamaBin = findOllamaBinary() else {
            throw InstallError.ollamaNotAvailable
        }
        try await runStreaming(
            executable: ollamaBin,
            args: ["pull", modelName],
            progress: progress
        )
    }

    /// Start `ollama serve` if it isn't already running. Returns quickly —
    /// the server keeps running in the background.
    /// (The watcher LaunchAgent also does this; this is for the case where
    /// the wizard needs Ollama running for the smoke test before the
    /// LaunchAgent is registered.)
    static func ensureServeRunning() async throws {
        let probe = await BridgeProbe.probeOllama()
        if case .running = probe {
            return  // already up
        }
        guard let ollamaBin = findOllamaBinary() else {
            throw InstallError.ollamaNotAvailable
        }

        // Spawn detached so the process outlives the launch call.
        let task = Process()
        task.executableURL = URL(fileURLWithPath: ollamaBin)
        task.arguments = ["serve"]
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        try task.run()
        // Don't wait — let it keep running. Caller polls BridgeProbe.

        // Wait up to 5s for the API to become reachable so the smoke test
        // doesn't race against startup.
        for _ in 0..<10 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if case .running = await BridgeProbe.probeOllama() { return }
        }
        throw InstallError.serveDidNotStart
    }

    // ─── Internals ───────────────────────────────────────────────────────

    /// Same probe as BridgeProbe.findOllamaBinary — duplicated here to keep
    /// installer independent of probe internals (probe is private).
    private static func findOllamaBinary() -> String? {
        let fm = FileManager.default
        let homePath = fm.homeDirectoryForCurrentUser.path
        let candidates: [String] = [
            "/opt/homebrew/bin/ollama",
            "/usr/local/bin/ollama",
            "/Applications/Ollama.app/Contents/Resources/ollama",
            "\(homePath)/.ollama/bin/ollama",
            "/usr/bin/ollama",
        ]
        return candidates.first(where: { fm.isExecutableFile(atPath: $0) })
    }

    private static func findHomebrewBinary() -> String? {
        let fm = FileManager.default
        let candidates = [
            "/opt/homebrew/bin/brew",   // Apple Silicon
            "/usr/local/bin/brew",      // Intel
        ]
        return candidates.first(where: { fm.isExecutableFile(atPath: $0) })
    }

    /// Spawn a process, stream stdout/stderr lines to `progress`, throw on
    /// nonzero exit. Used for `brew install` and `ollama pull` which both
    /// emit progress on stdout (or sometimes stderr).
    private static func runStreaming(
        executable: String,
        args: [String],
        progress: @escaping @Sendable (String) -> Void
    ) async throws {
        try await Task.detached(priority: .utility) {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: executable)
            task.arguments = args
            let out = Pipe()
            let err = Pipe()
            task.standardOutput = out
            task.standardError = err

            // Inherit the parent env with PATH augmented for tool discovery.
            var env = ProcessInfo.processInfo.environment
            let extra = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
            env["PATH"] = (env["PATH"].map { "\(extra):\($0)" }) ?? extra
            task.environment = env

            // Line-buffered streaming for both pipes.
            let stream = { (handle: FileHandle) in
                handle.readabilityHandler = { fh in
                    let data = fh.availableData
                    guard !data.isEmpty,
                          let s = String(data: data, encoding: .utf8) else { return }
                    for line in s.split(separator: "\n", omittingEmptySubsequences: false) {
                        let trimmed = String(line)
                        if !trimmed.isEmpty { progress(trimmed) }
                    }
                }
            }
            stream(out.fileHandleForReading)
            stream(err.fileHandleForReading)

            try task.run()
            task.waitUntilExit()

            out.fileHandleForReading.readabilityHandler = nil
            err.fileHandleForReading.readabilityHandler = nil

            if task.terminationStatus != 0 {
                throw InstallError.commandFailed(
                    cmd: "\(executable) \(args.joined(separator: " "))",
                    exitCode: task.terminationStatus
                )
            }
        }.value
    }

    enum InstallError: LocalizedError {
        case homebrewNotAvailable
        case ollamaNotAvailable
        case serveDidNotStart
        case commandFailed(cmd: String, exitCode: Int32)

        var errorDescription: String? {
            switch self {
            case .homebrewNotAvailable:
                return "Homebrew is not installed. Install it from brew.sh, then re-run setup."
            case .ollamaNotAvailable:
                return "Ollama binary not found after install. Check the install log."
            case .serveDidNotStart:
                return "Started `ollama serve` but the API did not become reachable within 5s."
            case .commandFailed(let cmd, let code):
                return "Command failed (exit \(code)): \(cmd)"
            }
        }
    }
}
