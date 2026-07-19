//
//  SkillInstaller.swift
//  Cloud to Ground AI — v0.2 Setup Wizard support
//
//  Copies the ollama-delegate skill payload from the app bundle to
//  ~/.claude/skills/ollama-delegate/ so Cowork picks it up.
//
//  Implements L2-OPS-009 (skill auto-install).
//
//  Cowork's skill discovery is filesystem-based — it walks
//  ~/.claude/skills/<name>/ and reads each SKILL.md's YAML frontmatter to
//  decide when to invoke the skill. As long as the SKILL.md frontmatter
//  is intact and the `description` field matches what Cowork was looking
//  for, the skill will fire.
//
//  Source-vs-installed problem (noted in granite4.1.md session log
//  2026-06-29): editing the source skill in the user's project doesn't
//  affect the installed copy in ~/.claude/skills. The wizard explicitly
//  copies SOURCE → INSTALLED, so re-running the wizard refreshes the
//  installed skill to the version shipped with this C2G build.
//
//  At v0.2 we copy ALL files in the source skill directory recursively.
//  This includes SKILL.md, VERSION, and the models/ subdirectory.
//

import Foundation

enum SkillInstaller {

    static let skillName = "ollama-delegate"

    /// Where Cowork looks for skills.
    static var installedSkillURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".claude/skills/\(skillName)")
    }

    /// Result of an install — used by the wizard UI to show a diff.
    struct InstallSummary {
        let previousVersion: String?
        let installedVersion: String
        let filesCopied: Int
    }

    /// Copy the bundled skill into the user's ~/.claude/skills/ directory.
    /// Returns a summary the wizard can display ("Upgraded from 0.1.0 to
    /// 0.2.0, 4 files copied" or similar).
    static func install() throws -> InstallSummary {
        let fm = FileManager.default
        let source = try locateBundledSkill()

        let previousVersion = readInstalledVersion()

        // Ensure the parent ~/.claude/skills directory exists.
        let parent = installedSkillURL.deletingLastPathComponent()
        if !fm.fileExists(atPath: parent.path) {
            try fm.createDirectory(at: parent,
                                   withIntermediateDirectories: true)
        }

        // Wipe the existing skill directory so removed files in the new
        // version don't linger. (User customisations to the installed
        // skill would be lost; at v0.2 we explicitly don't support that.)
        if fm.fileExists(atPath: installedSkillURL.path) {
            try fm.removeItem(at: installedSkillURL)
        }

        try fm.copyItem(at: source, to: installedSkillURL)

        let copied = countFiles(in: installedSkillURL)
        let newVersion = readInstalledVersion() ?? "unknown"

        return InstallSummary(
            previousVersion: previousVersion,
            installedVersion: newVersion,
            filesCopied: copied
        )
    }

    /// Is a skill of any version installed?
    static func isInstalled() -> Bool {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        return fm.fileExists(atPath: installedSkillURL.path, isDirectory: &isDir)
            && isDir.boolValue
    }

    /// Currently-installed version (from SKILL.md frontmatter, falls
    /// back to VERSION file).
    static func readInstalledVersion() -> String? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: installedSkillURL.path) else { return nil }

        // Try frontmatter first.
        let skillFile = installedSkillURL.appending(path: "SKILL.md")
        if let contents = try? String(contentsOf: skillFile, encoding: .utf8),
           let v = parseFrontmatterVersion(contents) {
            return v
        }

        // Fall back to VERSION file.
        let versionFile = installedSkillURL.appending(path: "VERSION")
        if let raw = try? String(contentsOf: versionFile, encoding: .utf8) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        return nil
    }

    // ─── Internals ───────────────────────────────────────────────────────

    private static func locateBundledSkill() throws -> URL {
        // Production: app bundle Resources/skill/
        if let bundleSkill = Bundle.main.url(
            forResource: "skill",
            withExtension: nil
        ), FileManager.default.fileExists(atPath: bundleSkill.path) {
            return bundleSkill
        }
        // Dev fallback: walk up from swiftui_app_v3/SkillInstaller.swift
        // to the project root, then into skill/.
        let here = URL(fileURLWithPath: #file).deletingLastPathComponent()
        let projectRoot = here.deletingLastPathComponent()
        let candidate = projectRoot.appending(path: "skill")
        if FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }
        throw InstallError.bundledSkillNotFound
    }

    private static func parseFrontmatterVersion(_ contents: String) -> String? {
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else {
            return nil
        }
        for line in lines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" { return nil }
            if trimmed.lowercased().hasPrefix("version:") {
                let value = trimmed.dropFirst("version:".count)
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                return value.isEmpty ? nil : value
            }
        }
        return nil
    }

    private static func countFiles(in dir: URL) -> Int {
        guard let enumerator = FileManager.default.enumerator(
            at: dir,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else { return 0 }
        var count = 0
        for case let url as URL in enumerator {
            if (try? url.resourceValues(forKeys: [.isRegularFileKey]))?
                .isRegularFile == true {
                count += 1
            }
        }
        return count
    }

    enum InstallError: LocalizedError {
        case bundledSkillNotFound
        var errorDescription: String? {
            switch self {
            case .bundledSkillNotFound:
                return "Bundled skill payload not found."
            }
        }
    }
}
