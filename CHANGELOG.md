# Changelog

All notable changes to Cloud2GroundAI are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/).

---

## [Unreleased]

_Nothing yet._

---

## [Mac app v1.5 · skill 0.3.5] — 2026-07-12

Numeric rebrand to **Cloud2GroundAI**, and a fix for the bridge
"answers once, then goes silent" hang. Protocol unchanged (v0.2.5).

### Fixed

- **The bridge no longer wedges after the first delegation.** The watcher
  will not start a new request while an unacknowledged `response.txt` is
  still present; if the client ever read a response without writing
  `consumed.txt` — an aborted cycle, or an improvised "PONG" liveness ping —
  the bridge answered exactly one request and then silently skipped every
  one after it. The skill (0.3.5) now *reconciles* an orphaned response
  before sending (writing `consumed.txt` to release the watcher), and
  refuses to send into a bridge that still holds a stale response — handling
  the task in the cloud instead of hanging. It also states the invariant,
  everywhere, that any `response.txt` you read must be acknowledged with
  `consumed.txt` (including probes).
- **Setup's "Test the bridge" now catches a bridge that can only answer
  once.** The smoke test runs two requests back-to-back with no cleanup
  between them, so a watcher (or `consumed.txt` handshake) that dies after
  the first request fails during setup instead of in the field. This also
  fully resolves the v1.3 "stale or mismatched response" symptom.

### Changed

- **Rebranded to the single canonical name "Cloud2GroundAI"** across the
  app — display name, the LaunchAgent label
  (`com.cloudtoground.watcher` → `com.cloud2ground.watcher`), the
  background launcher (`CloudToGround` → `Cloud2Ground`), the log folder
  (`~/Library/Logs/Cloud2GroundAI`), and the entitlements file. On upgrade a
  one-time migration boots out the old LaunchAgent and removes the old
  launcher, so the old and new watchers can never run side by side.
- Skill auto-update now points at the `carlanotech/Cloud2GroundAI`
  repository.

---

## [Mac app v1.3 · skill 0.3.4] — 2026-07-07

Protocol unchanged (v0.2.5). Mac app v1.3 — installer safety fixes; skill
bumped 0.3.2 → 0.3.4.

### Fixed

- **Bridge now works on a stock Mac with no developer tools.** The watcher
  (`start_local_ai.sh`, v0.2.8) no longer depends on `python3` — a fresh
  macOS ships only a `python3` stub that fails with "No developer tools
  were found" until Xcode Command Line Tools are installed, so on every
  clean machine the smoke test failed with "Watcher did not respond." The
  four file-maintenance blocks are now plain `bash`, and the inference
  block (config/JSON, the Ollama request, and output cleanup) is now
  `/usr/bin/perl` + `JSON::PP` — both ship with macOS. No new dependency,
  no change to the app size, behavior verified identical. Found via the
  clean-VM test.
- **Setup no longer logs the user out.** The "Register background service"
  step called `launchctl bootout` with the bare GUI domain (`gui/<uid>`)
  instead of the service target (`gui/<uid>/<label>`), which tore down the
  entire login session (logout / "every app resets"). It is now
  service-scoped, and a regression guard
  (`LaunchAgentInstaller.validateBootoutSafety`, asserted by the bridge
  smoke test) blocks any return to the bare-domain form. This also
  root-causes the earlier incident previously blamed on
  `ProcessType = Interactive` — that setting was a bystander, not the cause.
- **LaunchAgent registration no longer fails with "Bootstrap failed: 5:
  Input/output error."** Install now resets the service slot before
  bootstrapping: unconditional `bootout`, wait until launchd confirms the
  label is gone, then `launchctl enable` — because a *disabled* label also
  bootstraps with EIO and `bootout` does not clear the disabled flag, so a
  label disabled by a prior run failed every bootstrap until re-enabled.
  Bootstrap is also retried once on EIO to close the async-teardown race.
- Setup wizard is now upgrade-aware: it re-runs "Install watcher script"
  when the launcher is missing and re-registers when the on-disk plist is
  out of date, so upgrades pick up changes instead of reporting
  "already done".

### Changed

- **Background service now appears as "Cloud2Ground"** in macOS Login
  Items and Activity Monitor instead of "bash". The LaunchAgent runs a
  friendly-named launcher that execs `start_local_ai.sh`.
- Skill 0.3.3 → 0.3.4: the bridge IPC folder moved out of
  `~/Documents/claude_bridge` to `~/claude_bridge` — a background
  LaunchAgent's `python3` is blocked by macOS TCC from reading
  `~/Documents` on a fresh account. The delegation poll timeout is now read
  from `bridge_config.json` (written by the Mac app's Settings "leash
  length" slider) instead of a hardcoded value, unifying three
  previously-drifted numbers (`SKILL.md` 90s, watcher 120s, `SPEC` 60s).

### Added (systems engineering)

- Requirement `C2G-L2-OPS-012` (non-disruptive install/uninstall), traced
  to `PRD-005`, with its verification tied to the `validateBootoutSafety`
  guard above.

---

## [0.2.5] — 2026-07-03

Protocol v0.2.5. Skill bumped to 0.3.2. Mac app model-detection and
LaunchAgent registration fixes.

### Changed

- Per-model prompt wrapping and Ollama generation options are no longer
  a hardcoded `if/elif/else` chain in `start_local_ai.sh`. They're read
  at request time from `skill/models/model_families.json`, now the
  single source of truth for both the watcher and `SKILL.md` Step 2's
  tuning-file routing. Previously these facts were hand-copied into
  three places (the watcher, `SKILL.md`, `protocol/SPEC.md`) and had
  already drifted out of sync at least once. Falls back to neutral,
  model-agnostic generation defaults if the config file is missing or
  malformed.
- The Mac app no longer requires a `granite4.1`-prefixed model name to
  recognize a model as installed. `BridgeProbe.probeModel()`,
  `SetupController`'s install-detection, and the Setup Wizard / Settings
  model pickers now accept any Ollama model — the pickers are free-text
  fields with Granite 4.1 8b/30b offered as one-click suggested
  defaults, not the only options.
- `SKILL.md` Step 1's bridge health check no longer produces a false
  "bridge down" reading when running inside a sandboxed environment
  (e.g. Cowork) where `curl`/`pgrep` have no route to the host Mac.
  `processing.lock` appearing within ~10s of a request is now the
  liveness signal in that case.
- `com.cloudtoground.watcher.plist.template`: `ProcessType` changed from
  `Interactive` to `Background` (the correct classification for a
  headless script with no UI), and an explicit `ThrottleInterval` of 10s
  was added as a real restart-throttling safety net. The previous
  `Interactive` setting was based on a mistaken belief that it affected
  restart throttling — it doesn't; `ThrottleInterval` does, and wasn't
  set at all before this fix.

### Fixed

- `WatcherScriptInstaller` and `SkillInstaller`'s dev-tree fallback path
  (used because the Xcode target's Copy Bundle Resources phase doesn't
  yet include `start_local_ai.sh` / `skill/` / the plist template)
  computed the project root one directory too shallow and silently
  failed on every use. Both "Install watcher script" and "Install skill"
  wizard steps were affected.
- Setup Wizard now surfaces the exact `~/Documents/claude_bridge` path
  (with copy / reveal-in-Finder actions) at the point the folder is
  created, so a Cowork session knows to connect it as a folder — this
  was previously only documented inside `SKILL.md` itself, which isn't
  readable until the folder is already connected.

## [0.2.4] — 2026-06-29

Protocol v0.2.4. First version targeted at the macOS app distribution
("Cloud2GroundAI v0.2"). Behavior changes are scoped to the local
watcher; cloud-side and skill-side integrations remain unchanged.

### Changed

- Default model is now `granite4.1:8b` (was `granite-code:8b`). Override
  via the `C2G_MODEL` environment variable, which the Mac app's
  LaunchAgent plist sets.
- IBM Q/A prompt-template wrapping and `<|endoftext|>` stop sequence are
  now applied **only for `granite-code:*`**. `granite4.1` follows
  instructions directly per its tuning file.
- Ollama generation options are now per-model. `granite4.1` uses
  `temperature=0.2`, `num_predict=2048`, no explicit stop sequence.
  `granite-code` retains its IBM-recommended settings.

### Added

- `skill/manifest.json` — versioned skill update manifest, consumed by
  the Mac app's Settings → Updates tab.
- `recommended-models.json` — declares the recommended local model +
  minimum Ollama version, consumed by the C2G update-nudge mechanism.

## [0.2.3] — 2026-06-22

Protocol v0.2.3.

### Added

- Expected-start anchoring. An optional `# start: <token>` request line
  (after the optional `# id:` line) declares the token the answer should
  begin with. The output preamble stripper anchors on this token in
  addition to the existing code-keyword anchors, allowing leading
  indentation. Fixes pattern-completion output (e.g. `    "pump_2": {...}`)
  whose first line is an indented quoted key the keyword-only anchor
  missed.
- Auto-detection of "Start with \`X\`" instructions in the prompt body,
  so existing skill prompts get the same fix for free.

### Compatibility

- Backward compatible: requests without `# start:` behave as before.

## [0.2.2] — 2026-06-20 (evening)

### Added

- Output post-processing strips markdown fences and a short
  natural-language preamble before the first code-keyword line. Granite
  Code's IBM Q/A template encourages prose answers; this normalises the
  output to a clean code block.

## [0.2.1] — 2026-06-20 (afternoon)

### Added

- Model-specific prompt wrapping. For `granite-code:*`, the prompt is
  wrapped in IBM's "Question:/Answer:" template per the watsonx
  documentation. Other models pass through unchanged.

### Changed

- Ollama generation options pinned to IBM-recommended values for
  Granite Code: `temperature=0`, `repeat_penalty=1.05`,
  `num_predict=900`, `stop=["<|endoftext|>"]`.

## [0.2.0] — 2026-06-20 (morning)

Protocol v0.2 baseline. Introduces the request-ID convention and the
race-fix cleanup pass that prevent the previous response leaking into
the next request cycle.

### Added

- Optional `# id: <uuid>` first line of `request.txt`, echoed back as
  the first line of `response.txt`. Clients enforce id matching; the
  watcher just round-trips the field.

### Fixed

- Race fix: when `consumed.txt` is observed, both `response.txt` and
  `consumed.txt` are removed BEFORE the loop checks for the next
  `request.txt`. Eliminates the window where a new request could be
  answered with the previous response.

---

## Pre-protocol-versioning history

The earliest watcher implementation predates the protocol versioning
scheme. The history is recoverable from the project's internal notes
but not formally cataloged here. v0.2.0 is the first "spec-respecting"
release.
