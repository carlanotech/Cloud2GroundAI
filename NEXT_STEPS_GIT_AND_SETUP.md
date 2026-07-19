# Next steps — git cleanup + finishing the Setup system

**Written:** 2026-07-19, end of session
**For:** whoever (human or Claude) picks this up next — written to be self-contained, no prior conversation context assumed.

This session did a lot: fixed real bugs in the MLX bridge, retired Ollama from the delegation bridge and the app's status panel, built a real MLX-backed Ground chat (persistent conversation, resident model, idle-unload), and added a read-from-folder attach feature. All of that is done, build-verified, and committed. See `MORNING_HANDOFF — 2026-07-19.md` in this same folder for the first half of that work in detail.

Two things are explicitly **not done** and are the subject of this doc: (1) the git working tree has real cleanup needed, and (2) the Setup Wizard is still 100% Ollama and will error out if run today.

---

## Part 1 — Git cleanup

There are **two separate git repositories** in this project:

- **Outer repo**: `Cloud2GroundAI/` (the ProtonDrive folder itself). Created this session — didn't exist before. Currently clean except `.claude/settings.local.json` (permission allowlist, harmless) and a submodule-pointer diff for `Cloud2Ground` (expected, since that's a nested repo).
- **`Cloud2Ground/` repo**: pre-existing, has real history going back before this session (`v1.4`, various smoke-test fixes). This is where the actual app source lives and where the cleanup is needed.

### 1a. A mistake I made and already partially fixed

One commit this session, `5470576 "Add read-from-folder to Ground chat: attach-file button"`, has a **misleading message**: the commit call was missing a `-- <pathspec>` argument, so instead of committing the 4 files I'd just written, it committed whatever else was sitting staged in the git index at that moment — which turned out to be pre-existing staged files (`MLX_DOCUMENTATION_INDEX.md`, `MLX_MIGRATION_COMPLETE.md`, `MLX_PRODUCTION_PLAN.md`, etc., under a mangled absolute-path directory inside `Cloud2Ground.xcodeproj/` — see 1c below). Run `git show --stat 5470576` to see for yourself.

**This did not lose any work.** My actual 4 files (`GroundChatView.swift`, `Message.swift`, `Preferences.swift`, `GroundFileReader.swift`) were sitting uncommitted in the working tree the whole time, and I've since committed them properly in a later commit (also titled "Add read-from-folder to Ground chat: attach-file button" — yes, two commits now have nearly the same title; the second one's body explains the mixup). Nothing to do here except be aware of it if the history looks confusing. If you want to clean up the misleading commit message on `5470576`, that's a `git rebase -i` history rewrite — I'd leave it alone unless it's actually causing confusion, since rewriting history has its own risks and this branch may already be something you treat as shared/stable.

**Lesson for whoever commits next in this repo**: always use `git commit -m "..." -- <exact files>`, never a bare `git commit` with no pathspec, in this repo. There is other people's (Claude-in-Xcode's, presumably) work sitting staged in the index at all times, and a bare commit will scoop it up under whatever message you happen to be writing.

### 1b. Everything currently uncommitted (as of end of session)

Run `cd Cloud2Ground && git status --short` — you should see something close to this:

```
 M Cloud2Ground.xcodeproj/.../SKILL_MLX_v2.md          (mangled path, see 1c)
 M Cloud2Ground.xcodeproj/project.pbxproj
 M Cloud2Ground.xcodeproj/project.xcworkspace/contents.xcworkspacedata
 M Cloud2Ground/BridgeSmokeTest.swift
 D "Cloud2Ground/Cloud to Ground AI.entitlements"
 M Cloud2Ground/Info.plist.snippet.xml
 M Cloud2Ground/LaunchAgentInstaller.swift
 M Cloud2Ground/MenuBarApp.swift
 M Cloud2Ground/NetworkMonitor.swift
 M Cloud2Ground/README.md
 M Cloud2Ground/SettingsWindowController.swift
 M Cloud2Ground/SetupController.swift
 M Cloud2Ground/SetupWizardView.swift
 M Cloud2Ground/SetupWizardWindowController.swift
 M Cloud2Ground/StatusPanelWindowController.swift
 M Cloud2Ground/WatcherScriptInstaller.swift
 D Cloud2Ground/com.cloudtoground.watcher.plist.template
 M Cloud2Ground/skill/SKILL.md
 M Cloud2Ground/skill/VERSION
 M Cloud2Ground/skill/models/granite4.1.md
 M Cloud2Ground/start_local_ai.sh
 D com.cloudtoground.watcher.plist.template
?? Cloud2Ground.xcodeproj/project.xcworkspace/xcshareddata/
?? Cloud2Ground.xcodeproj/project.xcworkspace/xcuserdata/
?? Cloud2Ground/Cloud2Ground.entitlements
?? Cloud2Ground/FileBlockParser.swift
?? Cloud2Ground/GroundFileWriter.swift
?? Cloud2Ground/com.cloud2ground.watcher.plist.template
?? Cloud2Ground/skill/bridge_delegate
?? com.cloud2ground.watcher.plist.template
```

**None of this is mine.** I deliberately never touched any of it — every commit I made this session used an explicit file pathspec specifically to avoid disturbing whatever this is. I don't know for certain what produced it (I never watched it happen), but the pattern is a strong clue:

- `Cloud to Ground AI.entitlements` **deleted**, `Cloud2Ground.entitlements` **added** (new, untracked).
- `com.cloudtoground.watcher.plist.template` **deleted** (two copies), `com.cloud2ground.watcher.plist.template` **added** (two copies, untracked).
- `FileBlockParser.swift` and `GroundFileWriter.swift` show as **untracked** — meaning they were never committed at all, even though they're real, working, already-built code (the output-folder write feature, confirmed working in this session's manual GUI test).

That rename pattern (`CloudToGround` → `Cloud2Ground`) matches a rebrand that (per old code comments) happened around 2026-07-11 — this is very likely that rebrand's uncommitted tail, sitting in the working tree ever since, possibly touched again by Xcode's own build process when you did a build-and-run partway through this session (Xcode routinely rewrites `project.pbxproj`/workspace files on every build — that part is normal and expected). `SKILL.md`, `VERSION`, `granite4.1.md`, `start_local_ai.sh` all being modified inside `Cloud2Ground/` (as opposed to the outer repo's copies, which I did touch and archive) are a **separate, bundled copy** living inside the Xcode project — `WatcherScriptInstaller.swift`/`SkillInstaller.swift` bundle these as app resources, and Xcode's "file system synchronized group" project format can re-sync bundled resource copies from source on build.

### 1c. The mangled-path files under `Cloud2Ground.xcodeproj/`

You'll see paths like:
```
Cloud2Ground.xcodeproj/UsersandrewcarlileLibraryCloudStorageProtonDrive-acarlile@pm.me-folderCarlanoCloud2GroundAIMLX_MIGRATION_COMPLETE.md
```
This is a real absolute path with every `/` stripped out, used as a literal directory/file name inside the `.xcodeproj`. These appear to be genuine content (I read several of them via `git cat-file -p <blob-hash>` earlier this session, since the actual files don't exist on disk — only in git's object store, staged in the index) — they're Claude-in-Xcode's own planning docs (`MLX_MIGRATION_COMPLETE.md`, `MLX_PRODUCTION_PLAN.md`, etc.), already committed to history now (accidentally, via the `5470576` mixup described above), so at least they're not at risk of being lost anymore. Why Xcode created this bizarre mangled-path structure at all is worth asking Claude in Xcode about — I don't know the mechanism, only that it's there.

### 1d. Recommended next step for git cleanup

Don't just `git add -A && git commit`. Go through it deliberately:

1. `git diff -- Cloud2Ground/project.pbxproj` etc. — confirm the Xcode-metadata churn is just normal build noise, not a real structural change.
2. Decide whether the `CloudToGround` → `Cloud2Ground` rename files are meant to be committed now (finishing that old rebrand) or were an accident.
3. `FileBlockParser.swift` and `GroundFileWriter.swift` should definitely get committed — they're real, tested, working code with no reason to stay untracked.
4. Ask Claude in Xcode (or check its own session history, if it has any equivalent) what it was doing with the mangled `.xcodeproj` paths — that's unusual enough to be worth understanding before deciding to commit, rename, or clean it up.

---

## Part 2 — Finishing the Setup system

The Setup Wizard (first-run install experience) is **entirely unconverted from Ollama and will error out if you run it today**. This was deliberately left alone all session — retargeting it needs real design decisions, not mechanical find-and-replace. Two confirmed concrete breaks, found by checking (not guessing):

1. **`WatcherScriptInstaller.swift`** looks for `start_local_ai.sh` at the project root as its dev-mode fallback. That file was archived to `_archive_ollama_era/start_local_ai.sh` in the outer repo this session. Running the wizard's "install watcher script" step today throws `InstallError.bundledScriptNotFound`.
2. **`SkillInstaller.swift`**'s `install()` (not the `skillName` constant, which I did fix — see below) still expects `skill/models/model_families.json`, `granite4.1.md`, etc. at their old paths — also archived to `skill/_archive/models/` this session. Same failure mode.

### What's already fixed vs. what's still broken

**Fixed this session** (narrow, low-risk, doesn't touch the install *flow*):
- `SkillInstaller.skillName` renamed `"ollama-delegate"` → `"mlx-delegate"` — this was affecting the *running* Settings > Updates tab (reachable today, not wizard-only), so it was in scope and fixed. `install()`'s file-copying logic is untouched and still broken per #2 above.
- Various stale comments/doc strings across `BridgeConfigWriter.swift`, `SkillUpdateManager.swift`, `BridgeProbe.swift`.
- Settings window's Privacy and Updates tab copy text (no longer claims "Ollama runtime" / "ollama-delegate skill").

**Still fully Ollama, untouched, needs a real design pass:**

| File | What it does | Why it's not a quick fix |
|---|---|---|
| `OllamaInstaller.swift` | Installs Ollama via Homebrew, `ollama pull <model>`, `ollama serve` | No MLX equivalent needed at all — `c2g-mlx` downloads weights automatically via Hugging Face on first run, no separate "install a runtime" step exists in the MLX world |
| `WatcherScriptInstaller.swift` | Copies `start_local_ai.sh` + `model_families.json` into `~/Library/Application Support/claude_bridge/`, writes a friendly-named launcher wrapper | Needs to copy `watch_mlx_v2.sh` + the `c2g-mlx` binary (44MB) + `mlx.metallib` (3MB) instead — bundling a binary + Metal shader library into the Xcode app is new build-phase work, not done yet |
| `LaunchAgentInstaller.swift` | Registers the `com.cloud2ground.watcher` LaunchAgent (mature, battle-tested — real incident history in its comments: an EIO bootstrap race, a near-miss that would have logged the user out, an Xcode bundle-resource bug found via Parallels VM testing) | Plist template hardcodes `C2G_MODEL=granite4.1:8b` (Ollama format) and points at the Ollama-era launcher. This file's *mechanics* (bootstrap/bootout safety, EIO retry logic) are solid and reusable — only the plist *content* needs to change to MLX env vars (`C2G_MLX_MODEL`, `C2G_MLX_TEMPERATURE`, `C2G_MLX_BIN`) |
| `SetupController.swift` | Orchestrates the wizard's step sequence, calls into all three installers above | Drives the whole flow — can't be fixed independently of the above |
| `SetupWizardView.swift` | The wizard's UI/copy | Likely has visible "Installing Ollama…" style text — not audited this session |
| `SkillInstaller.swift`'s `install()` | Copies skill files from bundle to `~/.claude/skills/` | File lists (`topLevelFiles`, `modelsFiles`) assume the archived Ollama-era `skill/models/` layout |

### Real design questions to resolve before touching this (don't just port mechanically)

1. **Does the packaged app still need a separate "install the runtime" step at all?** For MLX, arguably no — the model downloads lazily on first inference. The wizard step might collapse from "install Ollama → pull model → start serve" down to just "start the watcher" (which then downloads on first use, same as `granite_repl.sh`/`c2g-mlx` already do today in dev). If the wizard wants a visible progress bar for that first download, that's new work — `mlx-swift-lm`'s own download-progress API hasn't been explored.
2. **Where does the `c2g-mlx` binary + `mlx.metallib` get built and bundled?** Two options: (a) a build phase that compiles `mlx_poc/c2g-mlx` as part of the Xcode app's build and copies the product into the app bundle's Resources, or (b) ship it as a separate download the app fetches on first run (keeps the DMG smaller, adds a network dependency to first launch). This is a real product decision.
3. **Should the resident model + idle-unload logic (built this session, see `MORNING_HANDOFF`) live inside the shipped `watch_mlx_v2.sh`, or should the packaged app manage the resident `c2g-mlx` process directly in Swift** (similar to how `LocalMLXChatClient.swift` already does it for Ground chat)? Given the app already has a working Swift-native pattern for this (spawn via `Process`+`Pipe`, own the lifecycle), it might be cleaner for the *installed* production watcher to be Swift-native too, rather than a bundled bash script — but that's a bigger rewrite than porting the existing script.
4. **What happens to `LaunchAgentInstaller.swift`'s hard-won safety mechanics?** Whatever gets decided above, that file's actual `launchctl bootstrap`/`bootout` logic (the EIO-retry loop, the service-vs-bare-domain safety check) should probably be reused as-is regardless of what runs inside the LaunchAgent — it's solid, tested code solving a real problem (macOS launchd quirks), independent of Ollama vs. MLX.

### A working reference implementation already exists

This session built and verified (see `MORNING_HANDOFF — 2026-07-19.md` and the outer repo's `mlx_poc/` commits) a **complete, working, standalone launchd setup** for the MLX watcher — just not integrated into the app's own installer:

- `mlx_poc/com.cloud2ground.mlx-watcher-dev.plist.template`
- `mlx_poc/install_launchd_dev.sh` / `uninstall_launchd_dev.sh`

These solve real problems worth reusing the *lessons* from (not necessarily the scripts verbatim): most importantly, **launchd cannot execute anything inside the ProtonDrive CloudStorage mount** — a background LaunchAgent with no interactive session gets `Operation not permitted` on both `cwd` and `exec` there. The fix (confirmed working) is copying the watcher + binary + metallib to a plain location outside the synced folder (`~/Library/Application Support/Cloud2Ground/mlx-dev/`) before registering the LaunchAgent. Whatever the real installer ends up doing, it needs this same out-of-ProtonDrive copy step — `WatcherScriptInstaller.swift` already does an equivalent copy-out-of-source-tree step for the Ollama era, so this isn't a new pattern, just needs applying to the MLX binary + metallib too.

---

## Key facts a fresh session should know before touching any of this

- **Two backends coexist by design right now, and that's intentional, not a bug**: the delegation bridge (Claude Code/Cowork skill) is 100% MLX. Ground chat (in-app conversation) is also 100% MLX now (as of this session). The **Setup Wizard** is 100% Ollama still — three different subsystems, three different current states, on purpose, because the Wizard needs a real redesign pass rather than a rename.
- **Two watcher scripts exist**: `start_local_ai.sh` (Ollama, archived to `_archive_ollama_era/` in the outer repo, but a *second bundled copy* still lives inside `Cloud2Ground/` for the Wizard — see Part 1b) and `mlx_poc/watch_mlx_v2.sh` (MLX, current, has resident-model + idle-unload support added this session).
- **The real, live MLX watcher right now** runs via `mlx_poc/install_launchd_dev.sh`, as LaunchAgent `com.cloud2ground.mlx-watcher-dev`, installed to `~/Library/Application Support/Cloud2Ground/mlx-dev/`. Check it with `launchctl print gui/501/com.cloud2ground.mlx-watcher-dev` or `bash ~/.claude/skills/mlx-delegate/bridge_delegate status`.
- **ProtonDrive sync causes two distinct, real gotchas** discovered this session: (1) rapid file edits can produce "Edit conflict" duplicate files that Xcode's synchronized-group project format will silently compile as ambiguous duplicates — sweep for `find . -iname '*Edit conflict*'` periodically; (2) `swift build` on files inside the ProtonDrive mount occasionally throws `"input file ... was modified during the build"` — usually transient, just retry.
- **`git commit` in the `Cloud2Ground` repo needs an explicit `-- <pathspec>`**, always — see Part 1a.
