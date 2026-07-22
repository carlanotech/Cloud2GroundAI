# Cloud2Ground — Project State

**Written:** 2026-07-20
**For:** whoever (human or Claude) needs a current picture without reading the full doc pile. Written to be self-contained.

This supersedes `C2G_GitHub_Release_Plan.md` and `C2G_Development_Roadmap.md` for
"what's next" purposes — both predate the MLX migration and are Ollama-era. The
two docs this one is closest to (and mostly summarizes) are
`MORNING_HANDOFF — 2026-07-19.md` and `NEXT_STEPS_GIT_AND_SETUP.md`, both from
the overnight 2026-07-19 session. Read those for full detail; this is the
short version plus a check against the actual repo state as of 2026-07-20.

---

## What Cloud2Ground is

A macOS menubar app that gives Claude Code / Cowork access to a local model
(Granite, via MLX-Swift) for two purposes: **delegation** (the cloud assistant
offloads mechanical subtasks to it via a file-based bridge protocol) and
**Ground chat** (a persistent, in-app conversation with the local model,
independent of any cloud session).

Two git repositories are involved:
- **Outer repo** (`Cloud2GroundAI/`, this ProtonDrive folder) — planning docs,
  the `skill/` directory (the delegation skill Claude Code/Cowork actually
  loads), `mlx_poc/` (the dev-mode MLX watcher + binary).
- **Inner repo** (`Cloud2Ground/`) — the Xcode project, real app source.

## What's built and working right now

- **Delegation bridge is 100% MLX**, no Ollama dependency. `c2g-mlx`
  (Swift/Metal binary) replaced Ollama entirely as of the 2026-07-19
  overnight session. Model defaults to `granite-3.3-8b-instruct-8bit`,
  temperature/topP/maxTokens are correctly wired, markdown fence-stripping
  is ported, `TIMEOUT` vs `WAITING` reporting is fixed (see
  [skill/SKILL-MLX.md](skill/SKILL-MLX.md), now **v2.4.0**).
- **Ground chat is also 100% MLX** (`LocalMLXChatClient.swift`), converted the
  same session — persistent sessions, resident-model idle-unload, and a
  read-from-folder attach-file feature.
- **The app's status panel** builds clean against MLX
  (`xcodebuild ... BUILD SUCCEEDED`, confirmed).
- **The live dev watcher** runs today as LaunchAgent
  `com.cloud2ground.mlx-watcher-dev`, independent of Xcode or any GUI app
  (confirmed by directly killing Xcode and checking the heartbeat kept
  ticking) — installed via `mlx_poc/install_launchd_dev.sh`.
- **Git hygiene from the 2026-07-19 session is now mostly resolved**: the
  `CloudToGround` → `Cloud2Ground` rebrand tail was committed
  (`1a61dbc`), the mangled-path files inside `Cloud2Ground.xcodeproj/` (an
  Xcode-integration bug, confirmed by Claude in Xcode itself) were rescued
  and removed (`0219bb2`, 22:00 that night), and a `.gitignore` for
  per-developer Xcode state was added.

**App version:** `MARKETING_VERSION` in the Xcode project is `2.0`.

## What's NOT done — the actual blocker

**The Setup Wizard (first-run install experience) is still 100% Ollama and
will error out if run today.** This has been true since the MLX migration
and remains true as of the latest inner-repo commit — verified directly by
grepping for `ollama` (case-insensitive) in the relevant files:

| File | Ollama references | Status |
|---|---|---|
| `OllamaInstaller.swift` | 43 | Installs Ollama via Homebrew — no MLX equivalent needed at all; `c2g-mlx` downloads weights itself |
| `SetupController.swift` | 16 | Orchestrates the wizard, calls the installers above |
| `SetupWizardView.swift` | 11 | Wizard UI copy, likely shows "Installing Ollama…" text |
| `WatcherScriptInstaller.swift` | 1 | Looks for `start_local_ai.sh`, which was archived this session — running this step today throws `InstallError.bundledScriptNotFound` |
| `LaunchAgentInstaller.swift` | 0 | Mechanically sound (battle-tested bootstrap/bootout/EIO-retry logic) — only its plist *content* needs MLX env vars instead of Ollama's |

This isn't a mechanical rename. `NEXT_STEPS_GIT_AND_SETUP.md` lays out three
real product decisions that need to be made first:
1. Does the wizard still need a separate "install the runtime" step at all,
   or does it collapse to "start the watcher" (since MLX downloads weights
   lazily on first use)?
2. Where does the `c2g-mlx` binary (44MB) + `mlx.metallib` (3MB) get bundled
   — compiled into the app's build phase, or fetched on first run?
3. Should the production watcher be a bundled bash script (port
   `watch_mlx_v2.sh` as-is) or Swift-native, matching the pattern
   `LocalMLXChatClient.swift` already uses?

There's also one small open item worth reconciling: the inner repo has an
uncommitted `DELEGATION_SKILL_BUGS_AND_FIXES.md` (staged, dated 2026-07-19,
status "awaiting fixes") describing three delegation-skill bugs found during
testing — missing `bridge_delegate` in the bundle, a status-schema mismatch,
and garbled/timeout output. The latter two look like exactly what tonight's
`skill/SKILL-MLX.md` v2.3–2.4 work already fixed (the `TIMEOUT`/`WAITING`
distinction, schema handling); worth a quick pass to confirm all three are
actually closed and either update or delete that doc.

## On the "DMG release plan"

**Packaging/shipping a DMG is not the next step right now** — worth flagging
since it's easy to assume otherwise. `C2G_GitHub_Release_Plan.md` and
`release_staging/` (v1.6) both describe the **previous, Ollama-based** app;
they predate the MLX migration and are explicitly marked stale as of
2026-07-19. Building a DMG from the current `main` would ship a broken
first-run experience: the Setup Wizard would immediately fail trying to
install Ollama-era dependencies that were archived this session.

The real next step is finishing the MLX port of the Setup Wizard (Part 2 of
`NEXT_STEPS_GIT_AND_SETUP.md`) — starting with the three design questions
above. DMG packaging, signing, and notarization (all done before, for v1.3/
v1.6) are the step *after* that, once the wizard actually works end-to-end
for a new user with no prior Ollama install.

## Version reference

| Component | Version | State |
|---|---|---|
| App (`MARKETING_VERSION`) | 2.0 | Builds clean, MLX-backed |
| Outer-repo skill (`skill/SKILL-MLX.md`) | 2.4.0 | Current, MLX-only |
| Inner-repo bundled skill (`Cloud2Ground/skill/VERSION`) | 0.4.0 | Stale — pre-MLX-rename, needs syncing before wizard work resumes |
| `release_staging/` | v1.6 | Old Ollama-era staged release, not current |
| `C2G_GitHub_Release_Plan.md` | — | Superseded 2026-07-19, Ollama-era |

---

## Bottom line

The hard part — retiring Ollama from the delegation bridge and Ground chat,
and fixing the real bugs that came with it — is done and working. What's left
before a real release is one well-scoped but non-trivial piece of product
work: rebuilding the Setup Wizard's three installer subsystems for MLX, which
needs the three design decisions above answered first. DMG packaging is real
work too, but it's downstream of that, not concurrent with it.
