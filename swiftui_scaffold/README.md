# SwiftUI Scaffold — Drop-in Instructions

This is a working SwiftUI scaffold for Cloud to Ground AI. Every file's header comment cites the L2 engineering requirements it implements (see `SE/requirements.json`). The whole thing compiles and runs against mock AI backends; replacing the mocks with real Anthropic + Ollama clients is the first real work after this scaffold lands.

## What's here

```
C2GApp.swift                  — App entry point. Wires the three @StateObject managers.
ContentView.swift             — Main window. Status bar top, conversation middle, mode toggle bottom.

Models/
  OperatingMode.swift         — Cloud / Hybrid / Ground enum with display metadata.
  NetworkStatus.swift         — Online / Offline / Unknown enum.
  Message.swift               — A single message + full per-response Attribution.
  ConversationThread.swift    — Conversation thread, mode-bound for its lifetime (L2-MOD-002). Named to avoid Foundation.Thread clash.

State/
  ModeManager.swift           — The state machine. ObservableObject. Owns the current mode.
  NetworkMonitor.swift        — NWPathMonitor wrapper. Publishes NetworkStatus.
  ConversationStore.swift     — Thread list + active thread. Enforces mode↔thread invariant.

Views/
  ModeIndicator.swift         — Persistent mode chip (L2-GUI-002).
  NetworkStatusChip.swift     — Persistent connectivity chip (L2-GUI-004).
  ModeToggle.swift            — Three-segment picker at bottom of window.
  ConversationView.swift      — Message list + composer.
  DegradationNoticeView.swift — In-flow notice on downgrade transitions (L2-GUI-003).
  OnboardingView.swift        — First-run modal (L2-GUI-005). Also includes SettingsView stub.

AI/
  CloudAI.swift               — Protocol + MockCloudAI implementation.
  LocalAI.swift               — Protocol + MockLocalAI implementation.
```

## How to drop into Xcode

1. In Xcode: **File → New → Project → macOS → App**. Name it `Cloud to Ground AI` (or `C2G`), Interface: SwiftUI, Language: Swift, no tests for now.
2. In Project navigator: delete the auto-generated `ContentView.swift` and the `<ProjectName>App.swift` (the one Xcode created — we have our own).
3. Drag all the files from this `swiftui_scaffold/` directory into your Xcode project, preserving the folder structure (check **Create groups**, not folder references).
4. Set the deployment target to macOS 14.0 or higher (Sonoma — we use `.onChange(of:_:)` two-param closure and `Task.sleep(for:)`).
5. Build (⌘B). Should compile clean.
6. Run (⌘R). You'll get a window with the status bar at the top, an empty conversation pane, and a mode toggle at the bottom. The onboarding sheet appears on first run.

## What works right now

- The mode state machine and atomic transitions (L2-MOD-002).
- The persistent mode indicator and network status chip (L2-GUI-002, L2-GUI-004).
- Automatic safe-direction transition (online → Ground when network drops).
- Mock conversation against mock cloud/local backends — you can type a message and get a mock reply with attribution.
- Degradation notice on downgrade transitions (L2-GUI-003).
- First-run onboarding sheet (L2-GUI-005).
- Mode-bound threads — switching modes starts a fresh thread.
- Settings stub.

## What does not work yet (intentionally)

- Real Anthropic API calls — replace `MockCloudAI` with a real client.
- Real Ollama calls — replace `MockLocalAI` with a real HTTP client to `http://localhost:11434/api/chat`.
- API key / Ollama-installed checks — not in scaffold; these block first-run flow per L2-OPS-001 / L2-OPS-003.
- Persistence — `ConversationStore` is in-memory only. Persist to disk before shipping.
- Code signing, notarization, packaging — blocked on Apple Developer Program enrollment (ACT-005).
- Actual Hybrid orchestration — currently Hybrid mode just routes to CloudAI (mock). The cloud-orchestrates-local pattern lands when we implement the real Hybrid path against the bridge protocol or its successor (TS-001 in Architecture Sketch §6).

## Conventions

- Every file header cites the L2(s) it implements. Keep that in sync if you rearrange.
- Mocks live next to their protocols; real implementations should go in the same file or a clearly named sibling.
- ObservableObjects are `@MainActor`. The state model assumes UI thread for mutation.
- No external Swift package dependencies. If you add one, that's a decision worth tracking — every dep is a thing you can't audit on a one-of-a-kind project.

## Next development steps (per Architecture Sketch §8)

1. Done (this scaffold) — app skeleton + mode state.
2. Wire real `NWPathMonitor` (already there but verify on offline).
3. Replace mock backends with real ones. Start with `MockLocalAI` → real Ollama HTTP, because that doesn't need API keys.
4. Real `CloudAI` via Anthropic SDK or URLSession.
5. Persistence layer for `ConversationStore`.
6. Hybrid orchestration (TS-001 trade study first).
7. Onboarding flow that actually checks for Ollama and downloads a model if missing.
8. Packaging / distribution path (driven by ACT-005).
