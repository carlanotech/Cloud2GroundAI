//
//  LaunchAgentInstaller.swift
//  Cloud to Ground AI — v0.2 Setup Wizard support
//
//  Installs and uninstalls the bridge watcher as a per-user LaunchAgent
//  so it auto-starts at login and survives crashes via KeepAlive.
//
//  Implements L2-OPS-011 (watcher persistence as LaunchAgent).
//
//  The plist template lives at com.cloudtoground.watcher.plist.template
//  in the app bundle. We substitute __HOME__ tokens with the real home
//  directory at install time and write to ~/Library/LaunchAgents/.
//
//  Why launchctl bootstrap (vs. load):
//    - `launchctl load` is deprecated since macOS 10.10. Bootstrap is the
//      supported modern verb.
//    - `bootstrap gui/<uid>` targets the user's GUI session, which is
//      what we want for a desktop app — the daemon session can't reach
//      ~/Documents under TCC.
//

import AppKit
import Foundation

enum LaunchAgentInstaller {

    static let label = "com.cloudtoground.watcher"
    static let plistFilename = "\(label).plist"

    /// Where the installed plist lives.
    static var installedPlistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/LaunchAgents/\(plistFilename)")
    }

    /// Where the user's logs go (so the wizard can show them on failure).
    static var logDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Logs/CloudToGroundAI")
    }

    // ─── Install ─────────────────────────────────────────────────────────

    /// Render the template, write it to ~/Library/LaunchAgents/, and load
    /// it with launchctl bootstrap. Idempotent — re-running it does the
    /// equivalent of an in-place reload (bootout + bootstrap).
    static func install() async throws {
        let template = try loadTemplate()
        let rendered = renderTemplate(template)

        try writeLogDirectoryIfNeeded()
        try rendered.write(to: installedPlistURL, atomically: true, encoding: .utf8)

        // If it's already loaded, unload first so the new plist takes effect.
        if try await isLoaded() {
            _ = try? await runLaunchctl(args: ["bootout", guiTarget()])
        }

        let bootstrap = try await runLaunchctl(args: [
            "bootstrap", guiTarget(), installedPlistURL.path
        ])
        guard bootstrap.exitCode == 0 else {
            throw InstallError.bootstrapFailed(
                exitCode: bootstrap.exitCode,
                stderr: bootstrap.stderr
            )
        }
    }

    // ─── Uninstall ───────────────────────────────────────────────────────

    /// Stop and remove the LaunchAgent. Safe to call when nothing is
    /// installed.
    static func uninstall() async throws {
        if try await isLoaded() {
            _ = try? await runLaunchctl(args: ["bootout", guiTarget()])
        }
        let fm = FileManager.default
        if fm.fileExists(atPath: installedPlistURL.path) {
            try fm.removeItem(at: installedPlistURL)
        }
    }

    // ─── State queries ───────────────────────────────────────────────────

    /// Is our LaunchAgent currently loaded?
    static func isLoaded() async throws -> Bool {
        let result = try await runLaunchctl(args: ["print", "\(guiTarget())/\(label)"])
        // exit 0 = loaded; exit 113 = not loaded.
        return result.exitCode == 0
    }

    /// Is the plist file present on disk (regardless of load state)?
    static func isInstalled() -> Bool {
        FileManager.default.fileExists(atPath: installedPlistURL.path)
    }

    // ─── Internals ───────────────────────────────────────────────────────

    private static func loadTemplate() throws -> String {
        // First try the app bundle (production location).
        if let bundleURL = Bundle.main.url(
            forResource: "com.cloudtoground.watcher.plist",
            withExtension: "template"
        ), let s = try? String(contentsOf: bundleURL, encoding: .utf8) {
            return s
        }
        // Dev fallback: look next to the source tree. This lets the wizard
        // work during Xcode-run debug sessions before we add the template
        // to Copy Bundle Resources.
        let devCandidates: [URL] = [
            URL(fileURLWithPath: #file)
                .deletingLastPathComponent()
                .appending(path: "com.cloudtoground.watcher.plist.template"),
        ]
        for url in devCandidates {
            if let s = try? String(contentsOf: url, encoding: .utf8) {
                return s
            }
        }
        throw InstallError.templateNotFound
    }

    private static func renderTemplate(_ template: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return template.replacingOccurrences(of: "__HOME__", with: home)
    }

    private static func writeLogDirectoryIfNeeded() throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: logDirectoryURL.path) {
            try fm.createDirectory(at: logDirectoryURL,
                                   withIntermediateDirectories: true)
        }
    }

    /// `gui/<uid>` is the launchctl domain selector for the user's GUI
    /// session. NSUserName / getuid() returns the right value because the
    /// app runs as the user.
    private static func guiTarget() -> String {
        "gui/\(getuid())"
    }

    private struct LaunchctlResult {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    private static func runLaunchctl(args: [String]) async throws -> LaunchctlResult {
        try await Task.detached(priority: .utility) {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            task.arguments = args
            let out = Pipe(); let err = Pipe()
            task.standardOutput = out
            task.standardError = err
            try task.run()
            task.waitUntilExit()
            return LaunchctlResult(
                exitCode: task.terminationStatus,
                stdout: String(data: out.fileHandleForReading.readDataToEndOfFile(),
                               encoding: .utf8) ?? "",
                stderr: String(data: err.fileHandleForReading.readDataToEndOfFile(),
                               encoding: .utf8) ?? ""
            )
        }.value
    }

    // ─── Errors ──────────────────────────────────────────────────────────

    enum InstallError: LocalizedError {
        case templateNotFound
        case bootstrapFailed(exitCode: Int32, stderr: String)

        var errorDescription: String? {
            switch self {
            case .templateNotFound:
                return "LaunchAgent template not found in app bundle."
            case .bootstrapFailed(let code, let stderr):
                return "launchctl bootstrap failed (exit \(code)): \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
            }
        }
    }
}
