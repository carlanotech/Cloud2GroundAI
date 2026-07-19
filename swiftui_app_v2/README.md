# Cloud to Ground AI — SwiftUI App v0.2

**Status:** Step 2a of 5 — Status Panel window landed 2026-06-29.

This is the architecture-corrected replacement for the original
`swiftui_scaffold/` directory. The old scaffold built a 3-mode chat app
that competed with Claude Desktop; the corrected design is a small menu
bar utility that installs and manages the bridge, plus a Ground chat
fallback for offline use. See Architecture Sketch §11.

## What's in this folder

| File | Step | Status |
|---|---|---|
| `MenuBarApp.swift` | 1 | ✅ shipped and verified in Xcode |
| `Info.plist.snippet.xml` | 1 | ✅ keys to merge into Xcode project |
| `BridgeStatus.swift` | 1 + 2a | ✅ scaffold + `import Combine` fix applied |
| `StatusPanelView.swift` | 2a (this step) | ✅ SwiftUI window with 3 sections, refresh button |
| `StatusPanelWindowController.swift` | 2a | ✅ window lifecycle owner |
| `BridgeProbe.swift` | 2b | ⬜ next — real shell-outs (pgrep, ollama, curl) |
| `LocalOllamaClient.swift` | 3 | ⬜ |
| `GroundChatView.swift` | 3 | ⬜ |
| `SetupController.swift` | 4 | ⬜ |
| `SetupWizardView.swift` | 4 | ⬜ |
| `SkillUpdateManager.swift` | 5 | ⬜ |
| `SettingsView.swift` (privacy panel) | 5 | ⬜ |

## Verified in Xcode (Personal Team signing)

- Menu bar icon renders (leaf, template image, auto-themes).
- No dock icon, no app-switcher entry (LSUIElement = YES).
- Menu items dispatch to AppDelegate via explicit `target = self`.
- "Open Status Panel" opens a SwiftUI window in 3-section Form layout.
- Window can be closed and reopened from the menu without duplicating.
- Network status shows "Online" / "Offline" based on real connectivity.
- Last refresh timestamp ticks as expected.
- Build succeeds with Apple Development cert (free Personal Team, no
  paid Apple Developer Program enrollment required for local testing).

## How to drop into Xcode

1. **File → New → Project → macOS → App.** Name: `Cloud to Ground AI`.
   Interface: SwiftUI. Language: Swift. No tests for now.
2. **Delete the auto-generated `ContentView.swift` and `<ProjectName>App.swift`** —
   we have our own `MenuBarApp.swift`.
3. **Drag the .swift files from this directory into Project navigator.**
   Check "Create groups."
4. **Merge `Info.plist.snippet.xml` into the project's Info.plist:**
   - Xcode → click the target → Info tab → Custom macOS Application Target
     Properties.
   - Add the `LSUIElement` boolean (set true), `CFBundleDisplayName`,
     `CFBundleName`, `NSHumanReadableCopyright` keys with the values from
     the snippet file.
5. **Set the deployment target to macOS 14.0+** (Sonoma).
6. **Build (⌘B), then Run (⌘R).** Behaviour you should see:
   - No dock icon, no main window.
   - A leaf icon appears in your menu bar at the top of the screen.
   - Clicking the icon shows a menu: Open Status Panel, Open Ground Chat,
     separator, Settings…, separator, Quit Cloud to Ground AI.
   - Each menu item prints to the Xcode console when clicked. Real
     functionality lands in steps 2-5.

If anything fails to compile or the icon doesn't appear, paste me the
error and I'll fix it.

## Step roadmap

1. **Menu bar skeleton** (this step). Icon shows, menu works, no real
   functionality. Validates the app runs in Xcode.
2. **Status panel** (L2-GUI-010). Split into two sub-steps:
   - **2a** ✅ — Window opens from the menu, SwiftUI Form with three
     sections, refresh button, color-coded status. Placeholder data.
   - **2b** — Real probes: `pgrep -f start_local_ai.sh` for watcher PID,
     `ollama list` for installed models, `curl localhost:11434/api/tags`
     for Ollama API liveness, Cowork skill directory inspection for
     installed skill version. Wire into `BridgeStatus.refresh()`.
3. **Real Ollama client + Ground chat** (L2-AI-001 + L2-GUI-011 +
   L2-MOD-001). Replace placeholder model invocation with a real HTTP
   client to localhost:11434. Conversation UI for offline use.
4. **Setup wizard** (L2-OPS-009 + L2-OPS-011). First-run flow: install
   Ollama (Homebrew or direct), pull granite4.1, install the skill into
   Cowork's directory, register the watcher as a LaunchAgent.
5. **Skill auto-update + privacy settings** (L2-OPS-010 + L2-GUI-008).
   Background update check; settings panel with per-channel opt-in
   toggles (feedback, usage telemetry).

## Conventions

- Every file header cites the L2 requirement(s) it implements.
- AppKit `NSObject` types use explicit memory management notes where
  lifetime is non-obvious (see the `statusItem` comment in `MenuBarApp.swift`).
- Granite-delegated drafts are noted in the file header, with the outcome
  class (verbatim / patched / rewritten) per the ollama-delegate cost model.
- No external Swift package dependencies — every dep is something we
  can't audit on a one-of-a-kind project.

## Differences from `swiftui_scaffold/` (the old folder)

If you're looking at the old folder for reference: most of it was a
3-mode chat app that doesn't fit the corrected architecture. Files that
carry over (in modified form) when steps 2-5 land:
- `Models/Message.swift` → carries forward unchanged
- `Models/NetworkStatus.swift` → carries forward unchanged
- `State/NetworkMonitor.swift` → carries forward unchanged
- `AI/LocalAI.swift` (protocol only, mock replaced) → step 3

Everything else in the old scaffold is being superseded.
