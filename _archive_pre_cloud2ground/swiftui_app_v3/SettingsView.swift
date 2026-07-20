//
//  SettingsView.swift
//  Cloud to Ground AI — v0.2 Step 5
//
//  Tabbed settings window: Behavior, Privacy, Updates. Binds directly to
//  Preferences.shared so toggles take effect immediately (L2-GUI-008).
//
//  Layout note: macOS's TabView with .tabViewStyle(.automatic) gives the
//  standard System Settings-style flat tabs at the top. Each tab is a
//  Form with LabeledContent rows so the labels right-align with the
//  controls.
//

import Combine
import SwiftUI

struct SettingsView: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var updates: SkillUpdateManager

    var body: some View {
        TabView {
            behaviorTab
                .tabItem { Label("Behavior", systemImage: "slider.horizontal.3") }

            privacyTab
                .tabItem { Label("Privacy", systemImage: "hand.raised") }

            updatesTab
                .tabItem { Label("Updates", systemImage: "arrow.triangle.2.circlepath") }
        }
        .padding()
        .frame(minWidth: 520, minHeight: 420)
    }

    // ─── Behavior tab ────────────────────────────────────────────────────

    private var behaviorTab: some View {
        Form {
            Section("Local model") {
                Picker("Default model", selection: $prefs.defaultModel) {
                    Text("granite4.1:8b  (5.4 GB, balanced)").tag("granite4.1:8b")
                    Text("granite4.1:30b  (~17 GB, higher quality)").tag("granite4.1:30b")
                }
                .pickerStyle(.menu)

                Text("The bridge watcher reads this value at startup (via the C2G_MODEL environment variable in its LaunchAgent plist). Changing it here takes effect on the next watcher restart.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Delegation timeout") {
                LabeledContent("Wait up to") {
                    HStack {
                        Slider(value: $prefs.delegationTimeoutSeconds,
                               in: 15...300, step: 5)
                            .frame(width: 220)
                        Text("\(Int(prefs.delegationTimeoutSeconds)) s")
                            .monospacedDigit()
                            .frame(width: 50, alignment: .trailing)
                    }
                }
                Text("How long the cloud will wait for a local model response before falling back to cloud-only. Per granite4.1.md: default 60 s, range 15–300 s. Slower machines or the 30b tier may need higher values.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Fallback behavior") {
                Toggle("Ask before using cloud as fallback",
                       isOn: $prefs.askBeforeUsingCloud)
                Text("If on, a delegation that times out locally will prompt before silently re-running on the cloud. Useful when on solar or limited bandwidth.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // ─── Privacy tab ─────────────────────────────────────────────────────

    private var privacyTab: some View {
        Form {
            Section("Local-only data") {
                Toggle("Delegation log (~/.c2g/delegation_log.jsonl)",
                       isOn: $prefs.delegationLogEnabled)
                Text("Records every cloud→local delegation with timestamp, task class, token counts, and outcome (verbatim / patched / rewritten / failed). This file never leaves your machine. Required for PRD-002 token-reduction measurement.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Off the machine (default: OFF)") {
                Toggle("Send anonymous usage telemetry",
                       isOn: $prefs.usageTelemetryEnabled)
                Text("Sends a daily summary of model usage counts (no prompts, no responses, no file paths) to Carlano so we can prioritize tuning. Disabled by default.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Send feedback and crash reports",
                       isOn: $prefs.feedbackEnabled)
                Text("Sends the contents of crash dumps and any feedback you submit through the menu's feedback form. Disabled by default.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundStyle(.green)
                    Text("Cloud to Ground AI makes no calls to Anthropic, OpenAI, or any inference API. The Ollama runtime on this machine is the only AI that ever sees your prompts.")
                        .font(.callout)
                }
            }
        }
        .formStyle(.grouped)
    }

    // ─── Updates tab ─────────────────────────────────────────────────────

    private var updatesTab: some View {
        Form {
            Section("Skill update channel") {
                Picker("Channel", selection: $prefs.skillUpdateChannel) {
                    ForEach(Preferences.SkillUpdateChannel.allCases) { c in
                        Text(c.displayName).tag(c)
                    }
                }
                .pickerStyle(.radioGroup)

                Text("The ollama-delegate skill is what teaches Claude to route work through your local Ollama. New versions adapt to changes in Claude and to new local models. Skill updates never include code that runs outside Cowork.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Status") {
                LabeledContent("Installed version",
                               value: SkillInstaller.readInstalledVersion() ?? "—")
                LabeledContent("Last check",
                               value: prefs.lastSkillUpdateCheck
                                    .map { Self.relativeTimeFormatter.localizedString(for: $0, relativeTo: Date()) }
                                    ?? "never")

                switch updates.availability {
                case .unknown:
                    EmptyView()
                case .upToDate(let installed):
                    Label("Up to date (\(installed))", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .updateAvailable(let installed, let latest, let manifest):
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Update available: \(installed) → \(latest)",
                              systemImage: "arrow.down.circle.fill")
                            .foregroundStyle(.blue)
                        if let notes = manifest.releaseNotes, !notes.isEmpty {
                            Text(notes)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Button("Install update") {
                                Task {
                                    try? await updates.applyUpdate(manifest: manifest)
                                }
                            }
                            .disabled(updates.isApplying)
                            Button("Skip this version") {
                                prefs.skippedSkillVersion = manifest.version
                                Task { await updates.check(channel: prefs.skillUpdateChannel) }
                            }
                            .disabled(updates.isApplying)
                        }
                    }
                case .error(let msg):
                    Label(msg, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }

                Button("Check for updates now") {
                    Task { await updates.checkIfDue(force: true) }
                }
                .disabled(updates.isChecking || prefs.skillUpdateChannel == .disabled)
            }

            if !updates.applyLog.isEmpty {
                Section("Last install log") {
                    ScrollView {
                        Text(updates.applyLog.joined(separator: "\n"))
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 120)
                }
            }
        }
        .formStyle(.grouped)
    }

    private static let relativeTimeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()
}
