//
//  Preferences.swift
//  Cloud to Ground AI — v0.2 Step 5
//
//  Single source of truth for all persisted user settings. Backed by
//  UserDefaults so values survive across launches. ObservableObject so
//  SwiftUI views bind directly to the published properties; @Published
//  setters persist to UserDefaults synchronously, so toggles take effect
//  immediately (L2-GUI-008 requirement: no app restart).
//
//  Design choices:
//
//  * Privacy-preserving defaults. Every "send something off the machine"
//    flag is OFF. Every "collect locally" flag that touches user content
//    defaults to ON only if it doesn't leak (delegation log is local-only
//    per L2-OPS-006, so it's on by default — that's the data that makes
//    PRD-002 measurable).
//
//  * Single singleton, no DI. Step 4 didn't use a Preferences object; we
//    add it now and progressively migrate scattered defaults (timeout,
//    chosen model) into it. Future-proof by making Preferences.shared
//    the canonical access point even when a value isn't yet read here.
//
//  * Keys namespaced under "c2g." so any future preference inspector
//    (or `defaults read com.cloudtoground.app`) shows our keys grouped.
//

import Combine
import Foundation

@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()

    // ─── Keys (single place to rename) ───────────────────────────────────

    private enum Key {
        static let defaultModel        = "c2g.defaultModel"
        static let delegationTimeoutS  = "c2g.delegationTimeoutSeconds"
        static let delegationLogEnabled = "c2g.delegationLogEnabled"
        static let usageTelemetryEnabled = "c2g.usageTelemetryEnabled"
        static let feedbackEnabled     = "c2g.feedbackEnabled"
        static let skillUpdateChannel  = "c2g.skillUpdateChannel"
        static let lastSkillUpdateCheck = "c2g.lastSkillUpdateCheck"
        static let skippedSkillVersion = "c2g.skippedSkillVersion"
        static let askBeforeUsingCloud = "c2g.askBeforeUsingCloud"
        static let groundOutputFolderPath = "c2g.groundOutputFolderPath"
    }

    // ─── Behavior ────────────────────────────────────────────────────────

    /// Which Granite tier to target for delegation. Mirrors what the
    /// LaunchAgent plist passes as C2G_MODEL.
    @Published var defaultModel: String {
        didSet { UserDefaults.standard.set(defaultModel, forKey: Key.defaultModel) }
    }

    /// How long the cloud waits for a local response before falling back.
    /// Per granite4.1.md "On the response-time timeout" — default 60s,
    /// range 15–300s, exposed as a slider in Settings.
    @Published var delegationTimeoutSeconds: Double {
        didSet { UserDefaults.standard.set(delegationTimeoutSeconds,
                                           forKey: Key.delegationTimeoutS) }
    }

    /// Should the cloud explicitly prompt before falling back from local to
    /// cloud? Useful for power-conscious users.
    @Published var askBeforeUsingCloud: Bool {
        didSet { UserDefaults.standard.set(askBeforeUsingCloud,
                                           forKey: Key.askBeforeUsingCloud) }
    }

    /// Folder where Ground-chat "save file" cards write. nil = not chosen
    /// yet (the first Save prompts an NSOpenPanel). Stored as a plain path
    /// because App Sandbox is OFF (see Cloud2Ground.entitlements). If
    /// ACT-007 later selects Mac App Store distribution, sandbox turns on
    /// and this must become a security-scoped bookmark — swap the bodies of
    /// this property and `groundOutputFolder` below; callers don't change.
    @Published var groundOutputFolderPath: String? {
        didSet {
            if let p = groundOutputFolderPath {
                UserDefaults.standard.set(p, forKey: Key.groundOutputFolderPath)
            } else {
                UserDefaults.standard.removeObject(forKey: Key.groundOutputFolderPath)
            }
        }
    }

    /// URL view of the chosen output folder. The bookmark-ready seam: a
    /// future sandboxed build replaces the get/set bodies with bookmark
    /// resolution/creation and the rest of the app is unaffected.
    var groundOutputFolder: URL? {
        get { groundOutputFolderPath.map { URL(fileURLWithPath: $0, isDirectory: true) } }
        set { groundOutputFolderPath = newValue?.path }
    }

    // ─── Privacy (per L2-GUI-008) ────────────────────────────────────────

    /// Local-only delegation log per L2-OPS-006. ON by default because
    /// the data never leaves the machine and PRD-002's measurement
    /// depends on it.
    @Published var delegationLogEnabled: Bool {
        didSet { UserDefaults.standard.set(delegationLogEnabled,
                                           forKey: Key.delegationLogEnabled) }
    }

    /// Anonymous usage telemetry to Carlano. OFF by default. Channel
    /// spec is TBD pending the L2-OPS-007 endpoint design.
    @Published var usageTelemetryEnabled: Bool {
        didSet { UserDefaults.standard.set(usageTelemetryEnabled,
                                           forKey: Key.usageTelemetryEnabled) }
    }

    /// Feedback / crash report uploads. OFF by default.
    @Published var feedbackEnabled: Bool {
        didSet { UserDefaults.standard.set(feedbackEnabled,
                                           forKey: Key.feedbackEnabled) }
    }

    // ─── Skill update (L2-OPS-010) ───────────────────────────────────────

    enum SkillUpdateChannel: String, CaseIterable, Identifiable {
        case stable
        case beta
        case disabled
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .stable:   return "Stable (recommended)"
            case .beta:     return "Beta (early access)"
            case .disabled: return "Disabled (I'll update manually)"
            }
        }
    }

    @Published var skillUpdateChannel: SkillUpdateChannel {
        didSet { UserDefaults.standard.set(skillUpdateChannel.rawValue,
                                           forKey: Key.skillUpdateChannel) }
    }

    /// Last time we checked for an update, regardless of channel.
    @Published var lastSkillUpdateCheck: Date? {
        didSet {
            if let d = lastSkillUpdateCheck {
                UserDefaults.standard.set(d, forKey: Key.lastSkillUpdateCheck)
            } else {
                UserDefaults.standard.removeObject(forKey: Key.lastSkillUpdateCheck)
            }
        }
    }

    /// Version the user explicitly chose to skip (so we don't nag).
    /// Cleared when a newer version appears.
    @Published var skippedSkillVersion: String? {
        didSet {
            if let v = skippedSkillVersion {
                UserDefaults.standard.set(v, forKey: Key.skippedSkillVersion)
            } else {
                UserDefaults.standard.removeObject(forKey: Key.skippedSkillVersion)
            }
        }
    }

    // ─── Init / defaults ─────────────────────────────────────────────────

    private init() {
        let d = UserDefaults.standard

        self.defaultModel = d.string(forKey: Key.defaultModel) ?? "granite4.1:8b"

        // Handle the "key never set" case for Doubles separately — UserDefaults
        // returns 0.0 for missing keys which would collapse our slider to 0.
        if d.object(forKey: Key.delegationTimeoutS) != nil {
            self.delegationTimeoutSeconds = d.double(forKey: Key.delegationTimeoutS)
        } else {
            self.delegationTimeoutSeconds = 60.0  // default per granite4.1.md
        }

        self.askBeforeUsingCloud = d.bool(forKey: Key.askBeforeUsingCloud)

        // delegationLog default: ON (local-only, needed for PRD-002).
        // UserDefaults.bool returns false for missing keys; invert sense.
        if d.object(forKey: Key.delegationLogEnabled) != nil {
            self.delegationLogEnabled = d.bool(forKey: Key.delegationLogEnabled)
        } else {
            self.delegationLogEnabled = true
        }

        self.usageTelemetryEnabled = d.bool(forKey: Key.usageTelemetryEnabled)
        self.feedbackEnabled = d.bool(forKey: Key.feedbackEnabled)

        let raw = d.string(forKey: Key.skillUpdateChannel) ?? SkillUpdateChannel.stable.rawValue
        self.skillUpdateChannel = SkillUpdateChannel(rawValue: raw) ?? .stable

        self.lastSkillUpdateCheck = d.object(forKey: Key.lastSkillUpdateCheck) as? Date
        self.skippedSkillVersion = d.string(forKey: Key.skippedSkillVersion)
        self.groundOutputFolderPath = d.string(forKey: Key.groundOutputFolderPath)
    }
}
