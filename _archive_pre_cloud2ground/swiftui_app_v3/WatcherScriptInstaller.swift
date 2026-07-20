//
//  WatcherScriptInstaller.swift
//  Cloud to Ground AI — v0.2 Setup Wizard support
//
//  Copies start_local_ai.sh from the app bundle to the canonical install
//  location: ~/Library/Application Support/claude_bridge/start_local_ai.sh
//
//  Why this location (not ~/Documents):
//    macOS TCC blocks launchd-spawned bash from writing to ~/Documents
//    unless the script was previously run interactively from a TCC-granted
//    parent. Putting the script in ~/Library/Application Support sidesteps
//    that entirely — Application Support is launchd-friendly. The IPC
//    folder (~/Documents/claude_bridge/_bridge/) is a separate concern
//    handled by the script itself using python3, which retains TCC grants
//    from its own interactive usage.
//
//  Also ensures the IPC folder exists so the watcher's first iteration
//  doesn't fail on a missing directory.
//

import Foundation

enum WatcherScriptInstaller {

    static let scriptFilename = "start_local_ai.sh"

    /// Canonical install location.
    static var installedScriptURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/claude_bridge/\(scriptFilename)")
    }

    /// IPC folder Cowork mounts. Created if missing.
    static var bridgeFolderURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Documents/claude_bridge/_bridge")
    }

    /// Copy the script from the bundle to the install location.
    /// Idempotent — overwrites the existing script (so re-running the
    /// wizard upgrades you to the version shipped with this build).
    static func install() throws {
        let fm = FileManager.default
        let source = try locateBundledScript()

        // Ensure the parent directory exists.
        let parent = installedScriptURL.deletingLastPathComponent()
        if !fm.fileExists(atPath: parent.path) {
            try fm.createDirectory(at: parent,
                                   withIntermediateDirectories: true)
        }

        // Remove existing copy so the copy doesn't fail.
        if fm.fileExists(atPath: installedScriptURL.path) {
            try fm.removeItem(at: installedScriptURL)
        }

        try fm.copyItem(at: source, to: installedScriptURL)

        // Make it executable. copyItem doesn't preserve x-bit reliably
        // across volumes, and the bundled copy may not have it set.
        try fm.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: installedScriptURL.path
        )

        // Ensure the IPC bridge folder exists, with right permissions.
        if !fm.fileExists(atPath: bridgeFolderURL.path) {
            try fm.createDirectory(at: bridgeFolderURL,
                                   withIntermediateDirectories: true)
        }
    }

    /// Is the script in place at the canonical location?
    static func isInstalled() -> Bool {
        FileManager.default.fileExists(atPath: installedScriptURL.path)
    }

    /// Does the bridge folder exist?
    static func isBridgeFolderReady() -> Bool {
        FileManager.default.fileExists(atPath: bridgeFolderURL.path)
    }

    // ─── Internals ───────────────────────────────────────────────────────

    private static func locateBundledScript() throws -> URL {
        // Production: app bundle Resources.
        if let url = Bundle.main.url(forResource: "start_local_ai",
                                     withExtension: "sh") {
            return url
        }
        // Dev fallback: walk up from the source tree to find the canonical
        // start_local_ai.sh in the project root. This lets the wizard work
        // during Xcode-run debug sessions before we add the script to the
        // Copy Bundle Resources phase.
        let here = URL(fileURLWithPath: #file).deletingLastPathComponent()
        // swiftui_app_v3/ → Cloud to Ground AI/start_local_ai.sh
        let projectRoot = here.deletingLastPathComponent()
        let candidate = projectRoot.appending(path: "start_local_ai.sh")
        if FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }
        throw InstallError.bundledScriptNotFound
    }

    enum InstallError: LocalizedError {
        case bundledScriptNotFound

        var errorDescription: String? {
            switch self {
            case .bundledScriptNotFound:
                return "start_local_ai.sh not found in app bundle or dev tree."
            }
        }
    }
}
