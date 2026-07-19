//
//  BridgeProbe.swift
//  Cloud to Ground AI — v0.2
//
//  Real probes that populate BridgeStatus. Each function is async,
//  side-effect-free except for its return value, and best-effort: if a
//  probe can't reach its target it returns .unknown rather than throwing.
//
//  Implements probes for: L2-GUI-010 status panel data, L2-OPS-011
//  watcher-as-LaunchAgent presence check.
//
//  Notes on macOS sandbox: Process.run() and URLSession work without
//  entitlements when App Sandbox is OFF (which is the default for a
//  Personal-Team development build). When we eventually decide ACT-005's
//  distribution path (Mac App Store would require sandbox + helper-tool
//  pattern; notarized DMG can stay unsandboxed), these probes may need
//  to be re-architected.
//

import Combine
import Foundation

enum BridgeProbe {

    // ─── Public entry point used by BridgeStatus.refresh() ──────────────

    /// Run all probes concurrently. Returns the populated BridgeStatus
    /// fields as a tuple; caller publishes them to the @Published vars.
    static func probeAll() async -> ProbeResults {
        async let ollama = probeOllama()
        async let watcher = probeWatcher()
        async let model = probeModel()
        async let skill = probeSkill()
        return await ProbeResults(
            ollama: ollama,
            watcher: watcher,
            model: model,
            skill: skill
        )
    }

    struct ProbeResults {
        let ollama: BridgeStatus.OllamaState
        let watcher: BridgeStatus.WatcherState
        let model: BridgeStatus.ModelInfo?
        let skill: BridgeStatus.SkillInfo?
    }

    // ─── Individual probes ──────────────────────────────────────────────

    /// Ollama: ping localhost:11434/api/tags. If 200, running.
    /// Fallback to `which ollama` for installed-not-running.
    static func probeOllama() async -> BridgeStatus.OllamaState {
        // Try the API first — most informative.
        if let tagsURL = URL(string: "http://localhost:11434/api/tags") {
            var req = URLRequest(url: tagsURL)
            req.timeoutInterval = 2
            do {
                let (_, response) = try await URLSession.shared.data(for: req)
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    // Get version separately
                    let version = (try? await runShellOutput(
                        "/usr/bin/env",
                        ["ollama", "--version"]
                    ).output.trimmingCharacters(in: .whitespacesAndNewlines))
                        ?? "unknown"
                    let cleanVersion = version
                        .replacingOccurrences(of: "ollama version is ", with: "")
                        .replacingOccurrences(of: "ollama version ", with: "")
                    return .running(version: cleanVersion)
                }
            } catch {
                // API not reachable — fall through to which-ollama check.
            }
        }

        // Is ollama installed?
        let which = try? await runShellOutput("/usr/bin/which", ["ollama"])
        if let w = which, w.exitCode == 0, !w.output.isEmpty {
            return .installedNotRunning
        }
        return .notInstalled
    }

    /// Watcher: pgrep for start_local_ai.sh.
    static func probeWatcher() async -> BridgeStatus.WatcherState {
        do {
            let result = try await runShellOutput(
                "/usr/bin/pgrep",
                ["-f", "start_local_ai.sh"]
            )
            let trimmed = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            if result.exitCode == 0, let pid = Int32(trimmed.split(separator: "\n").first ?? "") {
                return .running(pid: pid)
            }
            return .stopped
        } catch {
            return .unknown
        }
    }

    /// Model: `ollama list` first line that matches `granite4.1*`.
    static func probeModel() async -> BridgeStatus.ModelInfo? {
        guard let result = try? await runShellOutput(
            "/usr/bin/env",
            ["ollama", "list"]
        ), result.exitCode == 0 else {
            return nil
        }

        // ollama list format:
        //   NAME             ID            SIZE     MODIFIED
        //   granite4.1:8b    abc123def     5.3 GB   3 days ago
        // Find the first line whose first column starts with granite4.1.
        for line in result.output.split(separator: "\n") {
            let cols = line.split(separator: " ", omittingEmptySubsequences: true)
            guard let nameStr = cols.first.map(String.init),
                  nameStr.lowercased().hasPrefix("granite4.1")
            else { continue }

            // SIZE column is at index 2 (1-indexed: ID at 1, SIZE at 2)
            let sizeMB: Int
            if cols.count >= 4 {
                let sizeStr = String(cols[2])
                let unit = String(cols[3])
                sizeMB = parseSizeMB(sizeStr: sizeStr, unit: unit)
            } else {
                sizeMB = 0
            }

            return BridgeStatus.ModelInfo(name: nameStr, sizeMB: sizeMB, lastUsed: nil)
        }
        return nil
    }

    /// Skill: look for the ollama-delegate skill in known Cowork skill
    /// directories. Returns nil if not found. (Cowork's exact skill dir
    /// path is still being confirmed; we check several candidates.)
    static func probeSkill() async -> BridgeStatus.SkillInfo? {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser

        let candidates: [URL] = [
            // Cowork-app skill directories — best guess, refine when known
            home.appending(path: "Library/Application Support/Cowork/skills/ollama-delegate"),
            home.appending(path: "Library/Application Support/Claude/skills/ollama-delegate"),
            home.appending(path: ".claude/skills/ollama-delegate"),
            home.appending(path: ".cowork/skills/ollama-delegate"),
        ]

        for url in candidates {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue
            else { continue }

            // Read VERSION file if present; otherwise return a generic marker
            let versionFile = url.appending(path: "VERSION")
            let version = (try? String(contentsOf: versionFile, encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"

            // Use the directory's modification date as installedAt
            let attrs = try? fm.attributesOfItem(atPath: url.path)
            let installedAt = (attrs?[.modificationDate] as? Date) ?? .now

            return BridgeStatus.SkillInfo(
                version: version,
                installedAt: installedAt,
                lastUpdateCheck: nil
            )
        }
        return nil
    }

    // ─── Helpers ────────────────────────────────────────────────────────

    private struct ShellResult {
        let exitCode: Int32
        let output: String
    }

    /// Run a command and return its stdout + exit code. Times out at 5s.
    private static func runShellOutput(_ path: String,
                                       _ args: [String]) async throws -> ShellResult {
        try await Task.detached(priority: .utility) {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: path)
            task.arguments = args
            let stdout = Pipe()
            let stderr = Pipe()
            task.standardOutput = stdout
            task.standardError = stderr

            // Make sure /usr/local/bin (Homebrew on Intel) and
            // /opt/homebrew/bin (Apple Silicon) are in PATH so things
            // like `ollama` are found even if the app's environment is sparse.
            var env = ProcessInfo.processInfo.environment
            let extraPaths = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
            env["PATH"] = (env["PATH"].map { "\(extraPaths):\($0)" }) ?? extraPaths
            task.environment = env

            try task.run()
            task.waitUntilExit()

            let outData = stdout.fileHandleForReading.readDataToEndOfFile()
            let outStr = String(data: outData, encoding: .utf8) ?? ""
            return ShellResult(exitCode: task.terminationStatus, output: outStr)
        }.value
    }

    /// "5.3 GB" → 5300; "850 MB" → 850.
    private static func parseSizeMB(sizeStr: String, unit: String) -> Int {
        let n = Double(sizeStr) ?? 0
        let factor: Double
        switch unit.uppercased() {
        case "GB": factor = 1024
        case "MB": factor = 1
        case "KB": factor = 1.0 / 1024
        case "TB": factor = 1024 * 1024
        default:   factor = 1
        }
        return Int(n * factor)
    }
}
