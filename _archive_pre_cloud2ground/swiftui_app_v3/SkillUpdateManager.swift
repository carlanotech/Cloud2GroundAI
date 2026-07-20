//
//  SkillUpdateManager.swift
//  Cloud to Ground AI — v0.2 Step 5
//
//  Implements L2-OPS-010 (skill auto-update channel). Checks a hosted
//  manifest for a newer skill version, downloads the payload, and (with
//  user consent) installs it via SkillInstaller. Respects the user's
//  channel preference (stable / beta / disabled) and a per-version skip.
//
//  Update flow:
//    1. Fetch manifest JSON from the channel URL.
//    2. Compare manifest.version to SkillInstaller.readInstalledVersion().
//    3. If newer AND not in skippedSkillVersion: surface an
//       UpdateAvailability and let the UI prompt.
//    4. UI calls applyUpdate(): downloads the payload zip, extracts to a
//       staging directory, validates, swaps into ~/.claude/skills/ via
//       SkillInstaller-style atomic replacement.
//
//  v0.2 simplifications (called out for the v1.0 rollback work):
//    - No code signing yet. Signing is TBD per L2-OPS-010's tbd list.
//      Track in ACT-008-style action when published endpoint is decided.
//    - No rollback yet. v0.2 keeps the previous version directory under
//      ~/.claude/skills/ollama-delegate.bak so a manual rollback is
//      possible (`mv ollama-delegate.bak ollama-delegate`), but no UI
//      surface. v1.0 needs a "Roll back" button.
//    - The "endpoint" is currently a placeholder URL; the wizard owner
//      will swap it for the real one once decided.
//
//  Semver compare: only major.minor.patch (no pre-release tags). v0.2
//  level of correctness is fine for the v0.2 skill itself (no pre-releases
//  yet).
//

import Combine
import Foundation

@MainActor
final class SkillUpdateManager: ObservableObject {
    static let shared = SkillUpdateManager()

    // ─── Endpoints (placeholders) ────────────────────────────────────────

    /// Per-channel manifest URLs. v0.2 placeholders — replace with real
    /// Carlano-hosted URLs when the endpoint design lands (L2-OPS-010 TBD).
    private static let manifestURLs: [Preferences.SkillUpdateChannel: URL] = [
        .stable: URL(string: "https://carlano.example.com/c2g/skill/stable/manifest.json")!,
        .beta:   URL(string: "https://carlano.example.com/c2g/skill/beta/manifest.json")!,
    ]

    // ─── Public state ────────────────────────────────────────────────────

    enum UpdateAvailability: Equatable {
        case unknown
        case upToDate(installed: String)
        case updateAvailable(installed: String, latest: String, manifest: SkillManifest)
        case error(String)
    }

    @Published var availability: UpdateAvailability = .unknown
    @Published var isChecking: Bool = false
    @Published var isApplying: Bool = false
    @Published var applyLog: [String] = []

    private init() {}

    // ─── Manifest model ──────────────────────────────────────────────────

    struct SkillManifest: Codable, Equatable {
        let version: String        // semver "0.3.0"
        let payloadURL: String     // direct download URL for the skill zip
        let payloadSHA256: String?  // optional integrity hash (v0.2: optional)
        let releasedAt: String?    // ISO-8601 timestamp
        let releaseNotes: String?  // short markdown blurb
    }

    // ─── Check (callable on a schedule or manually) ─────────────────────

    /// Run a check if the channel allows it and it's been ≥24h since last
    /// check (per L2-OPS-010). Use force=true from the "Check now" button.
    func checkIfDue(prefs: Preferences = .shared, force: Bool = false) async {
        guard prefs.skillUpdateChannel != .disabled else {
            availability = .unknown
            return
        }
        if !force, let last = prefs.lastSkillUpdateCheck,
           Date().timeIntervalSince(last) < 24 * 60 * 60 {
            return  // not yet due
        }
        await check(channel: prefs.skillUpdateChannel)
        prefs.lastSkillUpdateCheck = Date()
    }

    func check(channel: Preferences.SkillUpdateChannel) async {
        guard let url = Self.manifestURLs[channel] else {
            availability = .error("No manifest URL for channel \(channel.rawValue)")
            return
        }
        isChecking = true
        defer { isChecking = false }

        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 10
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200
            else {
                availability = .error("Manifest fetch failed (HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1))")
                return
            }
            let manifest = try JSONDecoder().decode(SkillManifest.self, from: data)
            evaluate(manifest: manifest)
        } catch {
            availability = .error("Update check failed: \(error.localizedDescription)")
        }
    }

    private func evaluate(manifest: SkillManifest) {
        let installed = SkillInstaller.readInstalledVersion() ?? "0.0.0"
        switch compareSemver(installed, manifest.version) {
        case .orderedAscending:
            // Has the user explicitly skipped this version?
            if Preferences.shared.skippedSkillVersion == manifest.version {
                availability = .upToDate(installed: installed)
            } else {
                availability = .updateAvailable(
                    installed: installed,
                    latest: manifest.version,
                    manifest: manifest
                )
            }
        case .orderedSame, .orderedDescending:
            availability = .upToDate(installed: installed)
        }
    }

    // ─── Apply ───────────────────────────────────────────────────────────

    /// Download the payload zip from the manifest, validate, swap into
    /// place via an atomic rename pattern, keep a .bak of the previous
    /// version for manual rollback (no UI yet).
    func applyUpdate(manifest: SkillManifest) async throws {
        guard !isApplying else { return }
        isApplying = true
        defer { isApplying = false }
        applyLog.removeAll()
        log("Starting update to \(manifest.version)…")

        guard let payloadURL = URL(string: manifest.payloadURL) else {
            throw UpdateError.invalidPayloadURL(manifest.payloadURL)
        }

        // Download to a temp file.
        let (tempZip, response) = try await URLSession.shared.download(from: payloadURL)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw UpdateError.downloadFailed(http.statusCode)
        }
        log("Downloaded payload (\(byteSizeString(at: tempZip))).")

        // Optional integrity check.
        if let expected = manifest.payloadSHA256 {
            let actual = try sha256Hex(of: tempZip)
            guard actual.lowercased() == expected.lowercased() else {
                throw UpdateError.checksumMismatch(expected: expected, actual: actual)
            }
            log("Checksum verified.")
        } else {
            log("⚠️ No checksum in manifest — skipping integrity check (v0.2 allows this).")
        }

        // Extract to a staging directory.
        let staging = try makeStagingDirectory()
        defer { try? FileManager.default.removeItem(at: staging) }
        try unzip(tempZip, into: staging)
        log("Extracted to staging.")

        // Locate the SKILL.md inside the staged tree — accept either the
        // archive being the skill dir directly, or having one wrapping
        // folder.
        let skillRoot = try locateSkillRoot(in: staging)
        log("Staged skill root: \(skillRoot.lastPathComponent)")

        // Atomic-ish swap: rename current install → .bak, move staged → real.
        let fm = FileManager.default
        let real = SkillInstaller.installedSkillURL
        let backup = real.deletingLastPathComponent()
            .appending(path: real.lastPathComponent + ".bak")

        // Drop any prior .bak so we don't accumulate.
        if fm.fileExists(atPath: backup.path) {
            try fm.removeItem(at: backup)
        }
        if fm.fileExists(atPath: real.path) {
            try fm.moveItem(at: real, to: backup)
            log("Previous install preserved at \(backup.lastPathComponent).")
        }
        try fm.moveItem(at: skillRoot, to: real)
        log("New skill installed at \(real.path).")

        // Clear the "skipped" flag now that we're past it.
        Preferences.shared.skippedSkillVersion = nil

        // Re-evaluate so the UI flips to "up to date."
        evaluate(manifest: manifest)
        log("✓ Update to \(manifest.version) complete.")
    }

    // ─── Helpers ─────────────────────────────────────────────────────────

    private func log(_ s: String) { applyLog.append(s) }

    private func makeStagingDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "c2g-skill-stage-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func unzip(_ zip: URL, into dest: URL) throws {
        // Use /usr/bin/unzip — present on every macOS, no dependency.
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        task.arguments = ["-o", "-q", zip.path, "-d", dest.path]
        try task.run()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else {
            throw UpdateError.unzipFailed(task.terminationStatus)
        }
    }

    private func locateSkillRoot(in staging: URL) throws -> URL {
        let fm = FileManager.default
        // Case A: SKILL.md at the top of staging.
        if fm.fileExists(atPath: staging.appending(path: "SKILL.md").path) {
            return staging
        }
        // Case B: one wrapping folder (the common GitHub zip layout).
        guard let contents = try? fm.contentsOfDirectory(at: staging,
                                                         includingPropertiesForKeys: nil),
              let firstDir = contents.first(where: {
                  (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?
                      .isDirectory == true
              }),
              fm.fileExists(atPath: firstDir.appending(path: "SKILL.md").path)
        else {
            throw UpdateError.invalidPayload("SKILL.md not found in staged payload")
        }
        return firstDir
    }

    private func byteSizeString(at url: URL) -> String {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    private func sha256Hex(of file: URL) throws -> String {
        // /usr/bin/shasum -a 256 — avoids importing CryptoKit which would
        // add ~negligible-but-real overhead. Output format: "<hex>  <path>"
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/shasum")
        task.arguments = ["-a", "256", file.path]
        let pipe = Pipe()
        task.standardOutput = pipe
        try task.run()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let s = String(data: data, encoding: .utf8) ?? ""
        return String(s.split(separator: " ").first ?? "")
    }

    // ─── Semver compare ──────────────────────────────────────────────────

    /// Compare "0.2.0" to "0.3.1" etc. Only handles major.minor.patch.
    private func compareSemver(_ a: String, _ b: String) -> ComparisonResult {
        func parts(_ s: String) -> [Int] {
            s.split(separator: ".")
                .map { Int($0.prefix { $0.isNumber }) ?? 0 }
        }
        let aP = parts(a), bP = parts(b)
        for i in 0..<max(aP.count, bP.count) {
            let x = i < aP.count ? aP[i] : 0
            let y = i < bP.count ? bP[i] : 0
            if x < y { return .orderedAscending }
            if x > y { return .orderedDescending }
        }
        return .orderedSame
    }

    enum UpdateError: LocalizedError {
        case invalidPayloadURL(String)
        case downloadFailed(Int)
        case checksumMismatch(expected: String, actual: String)
        case unzipFailed(Int32)
        case invalidPayload(String)

        var errorDescription: String? {
            switch self {
            case .invalidPayloadURL(let u): return "Invalid payload URL: \(u)"
            case .downloadFailed(let code): return "Payload download failed (HTTP \(code))"
            case .checksumMismatch(let e, let a):
                return "Checksum mismatch — expected \(e), got \(a)"
            case .unzipFailed(let code): return "unzip failed (exit \(code))"
            case .invalidPayload(let msg): return "Invalid payload: \(msg)"
            }
        }
    }
}
