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
        async let savings = probeSavings()
        return await ProbeResults(
            ollama: ollama,
            watcher: watcher,
            model: model,
            skill: skill,
            savings: savings
        )
    }

    struct ProbeResults {
        let ollama: BridgeStatus.OllamaState
        let watcher: BridgeStatus.WatcherState
        let model: BridgeStatus.ModelInfo?
        let skill: BridgeStatus.SkillInfo?
        let savings: BridgeStatus.SavingsSummary?
    }

    // ─── Individual probes ──────────────────────────────────────────────

    /// Ollama: ping 127.0.0.1:11434/api/tags. If 200, running.
    /// Fallback to absolute-path search for installed-not-running.
    ///
    /// IMPORTANT — two macOS pitfalls this implementation guards against:
    ///
    /// 1. App Transport Security blocks HTTP to localhost unless Info.plist
    ///    sets NSAppTransportSecurity > NSAllowsLocalNetworking = true.
    ///    Without that key, URLSession silently throws and we'd fall
    ///    through to "Not installed" even though Ollama is running. We use
    ///    127.0.0.1 (not "localhost") because some ATS rule paths also
    ///    treat hostnames differently from IPs.
    ///
    /// 2. The app's process PATH does not include /opt/homebrew/bin until
    ///    we add it manually (done in runShellOutput). But if Ollama was
    ///    installed via the GUI .app (not Homebrew), the binary is at
    ///    /Applications/Ollama.app/Contents/Resources/ollama — which is in
    ///    no $PATH at all. We probe absolute candidate paths directly so
    ///    we don't rely on `which` for the GUI-app install case.
    static func probeOllama() async -> BridgeStatus.OllamaState {
        // Try the API first — most informative outcome (.running with version).
        if let tagsURL = URL(string: "http://127.0.0.1:11434/api/tags") {
            var req = URLRequest(url: tagsURL)
            req.timeoutInterval = 2
            do {
                let (_, response) = try await URLSession.shared.data(for: req)
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    let version = await readOllamaVersion()
                    return .running(version: version)
                }
            } catch {
                // API not reachable — fall through to installed-path search.
            }
        }

        // Is ollama installed anywhere we know to look?
        if findOllamaBinary() != nil {
            return .installedNotRunning
        }
        return .notInstalled
    }

    /// Scan a list of known absolute locations for the ollama binary.
    /// Returns the first one that exists and is executable.
    ///
    /// Order matters: Homebrew (most common dev install) → GUI .app bundle
    /// (most common end-user install) → manual installs in user-home.
    private static func findOllamaBinary() -> String? {
        let fm = FileManager.default
        let homePath = fm.homeDirectoryForCurrentUser.path
        let candidates: [String] = [
            "/opt/homebrew/bin/ollama",                              // Apple Silicon Homebrew
            "/usr/local/bin/ollama",                                 // Intel Homebrew
            "/Applications/Ollama.app/Contents/Resources/ollama",    // GUI .app install
            "\(homePath)/.ollama/bin/ollama",                        // Manual install
            "/usr/bin/ollama",                                       // System (unusual)
        ]
        for path in candidates {
            if fm.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    /// Read Ollama's version. Prefers the binary we found via
    /// findOllamaBinary() — running `<absolutePath> --version` works even
    /// when the app's PATH doesn't include the binary's directory.
    private static func readOllamaVersion() async -> String {
        guard let binPath = findOllamaBinary() else { return "unknown" }
        guard let result = try? await runShellOutput(binPath, ["--version"]),
              result.exitCode == 0 else { return "unknown" }
        let raw = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        // Output formats observed:
        //   "ollama version is 0.24.0"
        //   "ollama version 0.24.0"
        return raw
            .replacingOccurrences(of: "ollama version is ", with: "")
            .replacingOccurrences(of: "ollama version ", with: "")
    }

    /// Watcher: pgrep for start_local_ai.sh. Tries a couple of common
    /// invocation patterns since users may launch the watcher via
    /// `bash start_local_ai.sh`, `./start_local_ai.sh`, or via nohup.
    ///
    /// Note: this requires App Sandbox OFF so that pgrep can enumerate
    /// processes the user owns. With sandbox on, pgrep runs but sees
    /// nothing outside the app's container. Entitlements file disables
    /// sandbox for v0.2; see ACT-007 for the distribution-channel decision
    /// that may force sandbox back on later.
    static func probeWatcher() async -> BridgeStatus.WatcherState {
        // Try the most common pattern first.
        let patterns = ["start_local_ai.sh", "start_local_ai"]
        for pat in patterns {
            do {
                let result = try await runShellOutput("/usr/bin/pgrep",
                                                      ["-f", pat])
                let trimmed = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
                if result.exitCode == 0,
                   let firstLine = trimmed.split(separator: "\n").first,
                   let pid = Int32(firstLine) {
                    return .running(pid: pid)
                }
            } catch {
                // Process spawn failed (likely sandbox) — return unknown so
                // the UI distinguishes "sandbox/permission issue" from
                // "watcher confirmed not running".
                return .unknown
            }
        }
        return .stopped
    }

    /// Model: `ollama list` first line that matches `granite4.1*`.
    /// Uses the absolute path from findOllamaBinary() so it works
    /// regardless of the app's PATH (including for GUI .app installs).
    static func probeModel() async -> BridgeStatus.ModelInfo? {
        guard let binPath = findOllamaBinary() else { return nil }
        guard let result = try? await runShellOutput(binPath, ["list"]),
              result.exitCode == 0 else {
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

            // Two version-reading strategies, in order of preference:
            //   1. SKILL.md YAML frontmatter `version:` field (canonical —
            //      travels with the skill in source control)
            //   2. VERSION file at the skill root (convenience, no parsing)
            // Falls through to "unknown" if neither is readable.
            let version = readSkillVersionFromFrontmatter(skillDir: url)
                ?? readSkillVersionFromVersionFile(skillDir: url)
                ?? "unknown"

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

    /// Parse `version:` from SKILL.md YAML frontmatter (between the two
    /// `---` markers at the top of the file). No real YAML parser — looks
    /// for a `version:` line and returns the trimmed value.
    private static func readSkillVersionFromFrontmatter(skillDir: URL) -> String? {
        let skillFile = skillDir.appending(path: "SKILL.md")
        guard let contents = try? String(contentsOf: skillFile, encoding: .utf8)
        else { return nil }

        let lines = contents.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else {
            return nil  // No frontmatter block.
        }

        // Walk until we hit the closing `---`, looking for `version:`.
        for line in lines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" { return nil }  // End of frontmatter, no version field.
            if trimmed.lowercased().hasPrefix("version:") {
                let value = trimmed.dropFirst("version:".count)
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                return value.isEmpty ? nil : value
            }
        }
        return nil
    }

    /// Read a plain-text VERSION file at the skill root.
    private static func readSkillVersionFromVersionFile(skillDir: URL) -> String? {
        let versionFile = skillDir.appending(path: "VERSION")
        let raw = (try? String(contentsOf: versionFile, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (raw?.isEmpty == false) ? raw : nil
    }

    /// Savings: sum on-device token counts from the watcher's append-only
    /// ledger at ~/Documents/claude_bridge/_bridge/ledger.jsonl. Each line
    /// is one completed delegation: { ts, output_tokens, ... }. Returns nil
    /// if the ledger doesn't exist yet (fresh install / no delegations), so
    /// the panel shows "—" rather than a misleading zero.
    ///
    /// Best-effort and cheap: a few hundred short JSON lines parse in well
    /// under the refresh budget. Malformed lines are skipped, not fatal.
    static func probeSavings() async -> BridgeStatus.SavingsSummary? {
        let fm = FileManager.default
        let ledger = fm.homeDirectoryForCurrentUser
            .appending(path: "Documents/claude_bridge/_bridge/ledger.jsonl")

        guard let data = try? Data(contentsOf: ledger),
              let text = String(data: data, encoding: .utf8),
              !text.isEmpty
        else { return nil }

        let cal = Calendar.current
        let now = Date()
        let startOfToday = cal.startOfDay(for: now)
        let sevenDaysAgo = now.addingTimeInterval(-7 * 24 * 3600)

        var todayTokens = 0, weekTokens = 0, totalTokens = 0
        var todayCount = 0, weekCount = 0
        var lastTs: TimeInterval = 0

        for line in text.split(separator: "\n") {
            guard let lineData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let ts = (obj["ts"] as? NSNumber)?.doubleValue
            else { continue }

            let out = (obj["output_tokens"] as? NSNumber)?.intValue ?? 0
            totalTokens += out
            if ts > lastTs { lastTs = ts }

            let when = Date(timeIntervalSince1970: ts)
            if when >= sevenDaysAgo { weekTokens += out; weekCount += 1 }
            if when >= startOfToday { todayTokens += out; todayCount += 1 }
        }

        return BridgeStatus.SavingsSummary(
            todayTokens: todayTokens,
            weekTokens: weekTokens,
            totalTokens: totalTokens,
            todayCount: todayCount,
            weekCount: weekCount,
            lastDelegation: lastTs > 0 ? Date(timeIntervalSince1970: lastTs) : nil
        )
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
