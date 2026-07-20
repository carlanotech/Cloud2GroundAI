//
//  BridgeStatus.swift
//  Cloud to Ground AI — v0.2
//
//  Single source of truth for what C2G has set up on the user's machine
//  right now. Status Panel reads from `BridgeStatus.shared`; NetworkMonitor
//  writes to it on connectivity changes; BridgeProbe writes to it on refresh.
//
//  Why a shared singleton: multiple windows / menu items / monitors all
//  need to observe the same state. Re-instantiating per window would
//  produce divergent panels. The singleton lives for the app's lifetime.
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class BridgeStatus: ObservableObject {
    static let shared = BridgeStatus()

    @Published var ollamaRunning: OllamaState = .unknown
    @Published var modelLoaded: ModelInfo? = nil
    @Published var watcherRunning: WatcherState = .unknown
    @Published var skillVersion: SkillInfo? = nil
    @Published var networkOnline: Bool = false
    @Published var lastRefresh: Date = .now

    private init() {}

    /// Run all probes and publish results. Called by the Status Panel on
    /// open, by the refresh button, and on a low-cadence internal timer
    /// (future enhancement — every 30s while panel is visible).
    func refresh() async {
        let r = await BridgeProbe.probeAll()
        ollamaRunning = r.ollama
        watcherRunning = r.watcher
        modelLoaded = r.model
        // Keep existing skillVersion's lastUpdateCheck if the new probe
        // doesn't have one (auto-update channel will set it later).
        if let s = r.skill {
            skillVersion = s
        }
        lastRefresh = .now
    }

    // ─── State types ────────────────────────────────────────────────────

    enum OllamaState: Equatable {
        case running(version: String)
        case installedNotRunning
        case notInstalled
        case unknown

        var displayLabel: String {
            switch self {
            case .running(let v): return "Running (\(v))"
            case .installedNotRunning: return "Installed, not running"
            case .notInstalled: return "Not installed"
            case .unknown: return "Checking…"
            }
        }
    }

    struct ModelInfo: Equatable {
        let name: String          // e.g. "granite4.1:8b"
        let sizeMB: Int
        let lastUsed: Date?
    }

    enum WatcherState: Equatable {
        case running(pid: Int32)
        case stopped
        case unknown

        var displayLabel: String {
            switch self {
            case .running(let pid): return "Running (PID \(pid))"
            case .stopped: return "Stopped"
            case .unknown: return "Checking…"
            }
        }
    }

    struct SkillInfo: Equatable {
        let version: String
        let installedAt: Date
        let lastUpdateCheck: Date?
    }
}
