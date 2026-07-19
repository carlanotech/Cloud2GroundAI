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
| `BridgeProbe.swift` | 2b | ✅ probes (Ollama, watcher, model, skill) |
| `LocalOllamaClient.swift` | 3 | ✅ HTTP client to localhost:11434/api/chat |
| `GroundChatView.swift` | 3 | ✅ Ground chat window |
| `GroundChatWindowController.swift` | 3 | ✅ window lifecycle owner |
| `Conversation.swift` / `Message.swift` | 3 | ✅ chat model |
| `SetupController.swift` | 4 | ✅ state machine + async install orchestration |
| `SetupWizardView.swift` | 4 | ✅ 6-step wizard UI |
| `SetupWizardWindowController.swift` | 4 | ✅ window lifecycle owner |
| `OllamaInstaller.swift` | 4 | ✅ Homebrew install + model pull |
| `SkillInstaller.swift` | 4 | ✅ copy skill into ~/.claude/skills/ |
| `WatcherScriptInstaller.swift` | 4 | ✅ copy start_local_ai.sh to ~/Library/Application Support/claude_bridge/ |
| `LaunchAgentInstaller.swift` | 4 | ✅ generate plist + launchctl bootstrap |
| `BridgeSmokeTest.swift` | 4 | ✅ real-request → real-response acceptance test |
| `com.cloudtoground.watcher.plist.template` | 4 | ✅ LaunchAgent template (substituted at install) |
| `Preferences.swift` | 5 | ✅ UserDefaults wrapper, ObservableObject |
| `SkillUpdateManager.swift` | 5 | ✅ check / download / install / .bak rollback |
| `SettingsView.swift` | 5 | ✅ 3-tab Form (Behavior / Privacy / Updates) |
| `SettingsWindowController.swift` | 5 | ✅ window lifecycle owner |

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

## Xcode workflow notes (lessons from the v2 → v3 jump)

A real pattern showed up while bringing v0.2 to a clean build: when you're
iterating on a Mac app and **many files are changing across multiple
steps**, dropping the new versions into a **fresh versioned folder** (e.g.
`swiftui_app_v3/` instead of editing `swiftui_app_v2/` in place) is worth
the small friction. Three reasons:

1. **Xcode caches file references and indexed metadata.** When you delete
   a file and re-add one with the same name at the same path, Xcode
   sometimes holds the old content in its index until a full quit +
   DerivedData clear. A different path bypasses this entirely.
2. **Cloud-synced project folders (ProtonDrive, iCloud, OneDrive) can
   serve stale content.** A file edited remotely might look correct in
   Finder but the local sync hasn't picked up the new bytes yet. A new
   folder forces a fresh sync.
3. **The diff between "what I think Xcode is compiling" and "what Xcode
   is actually compiling" can drag a debugging session for an hour.** A
   fresh versioned folder is a hard reset that removes that ambiguity.

**When to bother:**

- Files changing in 3+ source files at once → use a new versioned folder
- Renaming a class / making a singleton / changing a public API → new
  versioned folder
- Tiny single-line edits → in-place is fine

**The drop-in routine that works (after a vN → vN+1 jump):**

1. In Xcode, right-click each of the old Swift files in the navigator →
   **Delete → Move to Trash**.
2. **Quit and reopen Xcode** (⌘Q then reopen). Flushes cached file
   references and IndexStore entries.
3. In Finder, wait for the new versioned folder to fully sync (no
   cloud-sync indicator on the folder).
4. Select all the new Swift files in the new folder and drag them into
   Xcode.
5. Import dialog: ✅ Copy items if needed, ✅ Create groups, ✅ correct
   target.
6. **Product → Clean Build Folder** (⇧⌘K), then ⌘B.

This is also a candidate v2.0 Pro feature: a "fresh-folder drop" helper
inside C2G that does steps 1-6 automatically when the user is iterating
on a Mac app. Tracked in Architecture Sketch §10 v2.0 features.

## Step 2b — Status panel probes (2026-06-29)

The Status panel now reads real state. Three things had to land for it to
work, and each one was a non-obvious macOS gotcha worth remembering:

1. **App Sandbox disabled.** New Xcode SwiftUI projects ship with the
   sandbox ON; `Process.run()` for pgrep / which / ollama and outbound
   URLSession to localhost are both blocked. The included
   `Cloud to Ground AI.entitlements` file turns the sandbox off for v0.2
   dev builds. Distribution path (notarized DMG vs Mac App Store) is
   tracked in ACT-007 — sandbox might come back on later with an XPC
   helper for the shell-outs.
2. **App Transport Security exception for localhost.** `Info.plist.snippet.xml`
   now adds `NSAppTransportSecurity > NSAllowsLocalNetworking = true`.
   Without this, the `URLSession.shared.data(for:)` call to
   `http://127.0.0.1:11434/api/tags` silently fails and the Ollama probe
   reports "Not installed" even when Ollama is running.
3. **Absolute-path binary lookup.** `BridgeProbe.findOllamaBinary()` checks
   five candidate paths in order: Apple Silicon Homebrew, Intel Homebrew,
   `/Applications/Ollama.app/Contents/Resources/ollama` (GUI installer),
   `~/.ollama/bin/ollama`, and `/usr/bin/ollama`. This is more robust than
   relying on `which ollama` because the GUI .app install puts the binary
   somewhere that is in *no* shell's PATH.

### To apply in Xcode (one-time)

1. **Add the entitlements file to the target.** In Xcode, drag
   `Cloud to Ground AI.entitlements` into the project. Then in the
   target's "Signing & Capabilities" tab: if "App Sandbox" capability is
   present, click the small `x` next to it to remove it. (Or, equivalently,
   leave the capability and set every checkbox inside to OFF — the
   entitlements file disables it regardless.)
2. **Merge the NSAppTransportSecurity dict** from `Info.plist.snippet.xml`
   into the project's Info.plist via Target → Info tab → Custom macOS
   Application Target Properties. Add key `App Transport Security Settings`
   (Xcode's pretty name for `NSAppTransportSecurity`), then inside it add
   `Allow Local Networking` = YES.
3. Clean build folder (⇧⌘K), rebuild (⌘B), run.

### Expected output after the patches

| Panel row | Before | After |
|---|---|---|
| Ollama | "Not installed" | "Running" with version (e.g. 0.24.0) |
| Model | "—" | "granite4.1:8b" with size |
| Watcher | "Stopped" | "Running" with PID (when `start_local_ai.sh` is up) |

If any row still shows the wrong state, check Xcode's console — the
probe failures are wrapped in `try?` and silently return `.unknown` or
`.notInstalled`. A future change should add a `--debug` build flag that
logs probe failures explicitly.

## Step 4 — Setup Wizard (2026-06-29)

The wizard automates what Andrew currently does manually. Open it from
the menu bar: **Setup…**. Six steps, each idempotent and skippable:

1. **Install Ollama** via Homebrew (`brew install ollama`), or link out
   to ollama.com if Homebrew isn't installed.
2. **Pull the model** — `granite4.1:8b` (5.4 GB, default) or
   `granite4.1:30b` (~17 GB, higher quality). Picker in the wizard.
3. **Install the delegate skill** into `~/.claude/skills/ollama-delegate/`.
   Reads the version from SKILL.md frontmatter before overwriting so the
   log shows "0.1.0 → 0.2.0" rather than a blind overwrite.
4. **Install the watcher script** to
   `~/Library/Application Support/claude_bridge/start_local_ai.sh` and
   create the IPC bridge folder at `~/Documents/claude_bridge/_bridge/`.
   The location split is load-bearing (TCC on Documents vs launchd).
5. **Register the LaunchAgent** at
   `~/Library/LaunchAgents/com.cloudtoground.watcher.plist` via
   `launchctl bootstrap gui/<uid> …`. Sets `KeepAlive` so launchd
   restarts the watcher on crash, and `C2G_MODEL=granite4.1:8b` so the
   watcher script uses the right model.
6. **Smoke test** — writes a real `request.txt` with a UUID, polls for
   `response.txt`, validates the UUID echoes back, displays the answer.
   This is the only step that proves the whole bridge stack actually
   works. Without it, the other 5 ✅ are structural-only.

### Model migration baked into this step

Started this morning: the watcher script was hardcoded to
`granite-code:8b`, but the C2G surfaces (Status panel, skill, tuning
files) have moved to `granite4.1:8b`. As of v0.2.4 of the watcher script
(2026-06-29) the model defaults to `granite4.1:8b` and the IBM Q/A
prompt template + `<|endoftext|>` stop sequence are scoped to
`granite-code:*` only, because granite4.1 doesn't need them per its
tuning file. Override via `C2G_MODEL` env var (which the LaunchAgent
plist sets).

### To apply in Xcode (one-time)

1. **Drag all 9 new files** from `swiftui_app_v3/` into the Xcode
   project navigator: `SetupController.swift`, `SetupWizardView.swift`,
   `SetupWizardWindowController.swift`, `OllamaInstaller.swift`,
   `SkillInstaller.swift`, `WatcherScriptInstaller.swift`,
   `LaunchAgentInstaller.swift`, `BridgeSmokeTest.swift`,
   `com.cloudtoground.watcher.plist.template`.
2. **Replace `MenuBarApp.swift`** with the updated one (adds the
   "Setup…" menu item).
3. **Replace `start_local_ai.sh`** in `Cloud to Ground AI/` (project
   root) with the updated v0.2.4 script — this is what the wizard
   bundles. The dev-fallback in `WatcherScriptInstaller` reads it from
   here.
4. **Add the plist template to "Copy Bundle Resources"** so the
   wizard can find it in production: Target → Build Phases → Copy
   Bundle Resources → `+` → `com.cloudtoground.watcher.plist.template`.
5. Clean Build (⇧⌘K), ⌘B, ⌘R. Click the menu icon → **Setup…**.

### Expected wizard behaviour on Andrew's machine (already set up)

Because you already have everything installed manually, the wizard
should show:

| Step | State on first open |
|---|---|
| 1. Install Ollama | ✅ already done (detects 0.24.0) |
| 2. Pull granite4.1:8b | depends — if `granite4.1:8b` is in your `ollama list`, ✅ |
| 3. Install delegate skill | ✅ already done (0.2.0) |
| 4. Install watcher script | ✅ already done (your current copy) |
| 5. Register LaunchAgent | ⚠️ **not yet** — you're running the watcher from a Terminal tab manually. Run this step to convert to auto-start. |
| 6. Smoke test | runs against the LaunchAgent watcher (kill your Terminal one first to be sure) |

The clean test path: stop your Terminal-launched watcher, click "Register
LaunchAgent", then "Run smoke test." If it passes, your bridge is now
auto-managed and survives logout/login.

## Step 5 — Skill auto-update + Settings (2026-06-29)

The menu bar's **Settings…** item now opens a 3-tab window. Defaults are
privacy-preserving — every "off the machine" channel is OFF until the
user explicitly turns it on.

**Behavior tab**:
- Default model picker (granite4.1:8b / 30b)
- Delegation timeout slider (15–300 s, default 60 s, per granite4.1.md)
- "Ask before using cloud as fallback" toggle (useful on solar / limited
  bandwidth)

**Privacy tab** (per L2-GUI-008):
- Delegation log toggle — local-only file at `~/.c2g/delegation_log.jsonl`,
  ON by default because PRD-002's token-reduction measurement depends on
  it and the data never leaves the machine.
- Anonymous usage telemetry — OFF by default.
- Feedback + crash reports — OFF by default.
- Footer notes that C2G itself makes no calls to Anthropic, OpenAI, or
  any inference API.

**Updates tab** (per L2-OPS-010):
- Channel picker: Stable (recommended) / Beta / Disabled
- Installed version + last-check timestamp
- "Check for updates now" button (force-checks even if <24 h since last)
- When an update is available: "Install update" and "Skip this version"
  buttons. Skipped versions are remembered until a newer one appears.
- Apply log shown after the most recent install.

### How the auto-update flow works under the hood

`SkillUpdateManager` fetches a per-channel manifest JSON (URLs are
placeholders in v0.2 — `https://carlano.example.com/c2g/skill/<channel>/manifest.json`
— wire to the real endpoint when L2-OPS-010's TBD list closes). The
manifest carries:

```json
{
  "version": "0.3.0",
  "payloadURL": "https://…/ollama-delegate-0.3.0.zip",
  "payloadSHA256": "abcd…",
  "releasedAt": "2026-07-01T12:00:00Z",
  "releaseNotes": "Fixes the math.acos units bug in granite4.1 prompts."
}
```

If the manifest's version is newer than `SkillInstaller.readInstalledVersion()`,
the user sees the prompt. Install path:

1. Download payload to a temp file
2. Verify SHA-256 (optional in v0.2; required in v1.0)
3. Unzip to a staging directory
4. Locate `SKILL.md` (handles both flat-archive and one-wrapping-folder layouts)
5. Rename current install to `ollama-delegate.bak` (manual rollback path)
6. Move staged tree into `~/.claude/skills/ollama-delegate/`
7. Re-evaluate availability so the UI flips to "up to date"

### What's still TBD for v1.0

- **Code signing**. Manifest currently carries an unverified SHA-256;
  v1.0 needs a detached signature verified against a Carlano-published
  public key.
- **Rollback UI**. The `.bak` directory is preserved but there's no
  button. v1.0: "Roll back to N-1" in the Updates tab.
- **Sparkle compatibility**. We're not using Sparkle for v0.2 (overkill
  for a non-binary payload). If a v2.0 paid app needs Sparkle for the
  app binary itself, the skill update channel can either coexist or
  collapse into it.

### Auto-check schedule

`SkillUpdateManager.checkIfDue` runs at every app launch (called from
`applicationDidFinishLaunching`) and is a no-op if (a) the channel is
disabled, or (b) the last check was <24 h ago. This satisfies L2-OPS-010's
"≤ once per day" requirement without needing a separate background timer.

### To apply in Xcode (one-time)

1. **Drag the 4 new files** from `swiftui_app_v3/` into the Xcode
   project navigator: `Preferences.swift`, `SkillUpdateManager.swift`,
   `SettingsView.swift`, `SettingsWindowController.swift`.
2. **Replace `MenuBarApp.swift`** with the updated one (wires
   `openSettings` to the new window and adds the launch-time
   `checkIfDue` task).
3. Clean Build (⇧⌘K), ⌘B, ⌘R. Click menu icon → **Settings…**.

## Step roadmap

1. **Menu bar skeleton** ✅ Icon shows, menu works.
2. **Status panel** (L2-GUI-010).
   - **2a** ✅ — Window, Form layout, refresh button, placeholder data.
   - **2b** ✅ — Real probes via sandbox-off + ATS exception + absolute-
     path binary lookup. Wired into `BridgeStatus.refresh()`.
3. **Real Ollama client + Ground chat** (L2-AI-001 + L2-GUI-011 +
   L2-MOD-001). Replace placeholder model invocation with a real HTTP
   client to localhost:11434. Conversation UI for offline use.
4. **Setup wizard** ✅ (L2-OPS-009 + L2-OPS-011). 6-step flow with
   detect-then-act idempotency, scrollable log, and an end-to-end smoke
   test as the only acceptance criterion.
5. **Skill auto-update + privacy settings** ✅ (L2-OPS-010 + L2-GUI-008).
   3-tab settings window (Behavior / Privacy / Updates) bound to a
   Preferences ObservableObject; launch-time skill-update check that
   respects per-channel preference; .bak preserved for manual rollback.

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
