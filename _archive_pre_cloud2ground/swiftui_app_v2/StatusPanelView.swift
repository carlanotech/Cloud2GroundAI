//
//  StatusPanelView.swift
//  Cloud to Ground AI — v0.2
//
//  Read-only window showing what C2G has set up on the user's machine.
//  Opens from the menu bar's "Open Status Panel" item.
//
//  Implements:
//    L2-GUI-010 (status panel window).
//
//  Step 2a build: placeholder data, real refresh probes land in step 2b.
//

import Combine
import SwiftUI

struct StatusPanelView: View {
    @ObservedObject var status: BridgeStatus
    @State private var isRefreshing = false

    var body: some View {
        Form {
            Section("Local AI") {
                LabeledContent("Ollama") {
                    Text(status.ollamaRunning.displayLabel)
                        .foregroundStyle(ollamaColor)
                }
                LabeledContent("Model") {
                    if let m = status.modelLoaded {
                        Text("\(m.name)  ·  \(m.sizeMB) MB")
                            .monospaced()
                    } else {
                        Text("—").foregroundStyle(.secondary)
                    }
                }
            }

            Section("Bridge") {
                LabeledContent("Watcher") {
                    Text(status.watcherRunning.displayLabel)
                        .foregroundStyle(watcherColor)
                }
                LabeledContent("Skill version") {
                    if let s = status.skillVersion {
                        Text(s.version).monospaced()
                    } else {
                        Text("—").foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Last update check") {
                    if let s = status.skillVersion, let last = s.lastUpdateCheck {
                        Text(last, style: .relative).foregroundStyle(.secondary)
                    } else {
                        Text("—").foregroundStyle(.secondary)
                    }
                }
            }

            Section("Network") {
                LabeledContent("Internet") {
                    Text(status.networkOnline ? "Online" : "Offline")
                        .foregroundStyle(status.networkOnline ? .green : .orange)
                }
                LabeledContent("Last refresh") {
                    Text(status.lastRefresh, style: .relative)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                HStack {
                    Spacer()
                    Button {
                        Task {
                            isRefreshing = true
                            await status.refresh()
                            isRefreshing = false
                        }
                    } label: {
                        if isRefreshing {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(isRefreshing)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 380, minHeight: 420)
        .navigationTitle("Cloud to Ground AI — Status")
        .task {
            await status.refresh()
        }
    }

    private var ollamaColor: Color {
        switch status.ollamaRunning {
        case .running: return .green
        case .installedNotRunning: return .orange
        case .notInstalled: return .red
        case .unknown: return .secondary
        }
    }

    private var watcherColor: Color {
        switch status.watcherRunning {
        case .running: return .green
        case .stopped: return .orange
        case .unknown: return .secondary
        }
    }
}
