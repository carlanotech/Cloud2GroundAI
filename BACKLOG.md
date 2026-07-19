# Cloud2GroundAI — Backlog

Started 2026-07-08, right after the **v1.3** release (first signed/notarized
public build). Items are things we consciously deferred, not bugs blocking a
ship. Newest milestone on top.

---

## v1.4 (next)

1. **[DONE 2026-07-09]** **Smoke test: don't fail on a stale/mismatched-id
   response.** `BridgeSmokeTest` used to fail the instant a `response.txt`
   arrived whose first line didn't echo our request id. Now treats it as a
   leftover, discards it, and keeps polling for *our* id until the timeout.
   *Why:* found in the Parallels VM test — on very slow hardware a previous
   inference was still running (holding `processing.lock`), finished late, and
   wrote its answer with the *old* id during a new test, causing a false
   "stale or mismatched response". Same class of bug fixed in the skill's poll
   loop (`SKILL.md` Step 4). File: `BridgeSmokeTest.swift`.

2. **[DONE 2026-07-09]** **Remove the remaining `python3` use from the skill
   (client side).** `SKILL.md` read the poll timeout, the model name, and the
   request id via `python3` one-liners — now python-free (`sed` / `uuidgen`),
   so a Claude Code user on a bare Mac with no Command Line Tools won't hit the
   "no python3" wall. Shipped as skill **0.3.5**. File: `skill/SKILL.md`.

3. **[DONE 2026-07-09]** **Smoke test: detect watcher-not-running via
   `processing.lock`.** If Ollama is up but the watcher never takes
   `processing.lock` within ~15s, the smoke test now reports "watcher isn't
   running" instead of a misleading slow/stuck timeout. Keys liveness on the
   lock (a slow/stuck inference still holds one), not on a possibly-stale
   `response.txt`. File: `BridgeSmokeTest.swift`.

4. **[DONE 2026-07-09]** **Smoke test: write `consumed.txt`.** The smoke test
   used to skip `consumed.txt` on the mistaken assumption the watcher cleaned
   up lazily. It doesn't — the watcher only clears `response.txt` on
   `consumed.txt` or restart — so the skipped ack left an orphaned response
   that *blocked the next request*, and sandboxed sessions can't delete it.
   This silently wedged the bridge and caused a long false-alarm debugging
   session (see the "misdiagnosed watcher" thread, 2026-07-08/09). Now acks on
   read, and clears any stale `consumed.txt` up front. File:
   `BridgeSmokeTest.swift`.

---

## Also queued (surfaced during v1.3 work, not yet scheduled)

- **Watcher SIGTERM trap doesn't exit + nukes the shared bridge (found
  2026-07-09).** `start_local_ai.sh`'s `trap '…' EXIT INT TERM` runs its
  cleanup handler but never `exit`s, so a normal `kill` (SIGTERM) does NOT
  stop the watcher — you have to `kill -9`. Worse, that same handler does
  `find "$BRIDGE" -mindepth 1 -maxdepth 1 -delete` on *every* TERM, so a
  polite kill of one watcher wipes the whole `_bridge` — including a request
  another watcher may be mid-processing. Fix: `exit` after cleanup on INT/TERM,
  and scope the delete to this watcher's own transient files (or only on
  genuine shutdown), not a blanket wipe of the shared folder. File:
  `start_local_ai.sh`.

- **Rename everything `CloudToGround` → `Cloud2Ground` (decided
  2026-07-09).** The codebase mixes two names: the app/bundle is `Cloud2Ground`
  but the LaunchAgent label + wrapper are `com.cloudtoground.watcher` /
  "CloudToGround". Decision: standardize on **Cloud2Ground**. Rename the
  LaunchAgent label to `com.cloud2ground.watcher` in `LaunchAgentInstaller`
  (+ the plist template, `WatcherScriptInstaller` wrapper leaf name, and any
  install/bootout paths), then on upgrade **bootout the old label** so a stale
  `com.cloudtoground.watcher` can't linger as a second agent. *Context:* a
  leftover hand-rolled `com.andrewcarlile.ollama-bridge` LaunchAgent running
  the same script alongside `com.cloudtoground.watcher` caused a two-watcher
  race + stale-artifact mess on 2026-07-08/09; the rename work should include a
  one-time sweep for any other ad-hoc agents/login-items pointing at
  `start_local_ai.sh`.
  Also in scope for this pass (batched here on purpose so we don't ship a
  half-renamed state — deferred from v1.4 on 2026-07-10):
    - **DMG filename**: `build-dmg.sh` emits `Cloud_to_Ground_AI_v<ver>.dmg`
      (spelled-out "to"). Change `DMG_NAME` to the `Cloud2Ground` form.
    - **Top-level project folder**: rename `Cloud2GroundAI/` →
      `Cloud2GroundAI/` (verified safe — nothing hardcodes its absolute path;
      do it with Xcode + the app quit and ProtonDrive sync idle, then re-add
      the folder to Cowork).
    - **Open question — the spelled-out product/display name.** "Cloud to
      Ground AI" is currently the app's *display* name and the DMG *volume*
      name (distinct from the `CloudToGround` code identifier and the
      `Cloud2Ground` bundle name). Decide whether that user-facing branding
      also moves to "Cloud2Ground" or stays as-is; the code-identifier rename
      doesn't require changing it.

- **Hardware capability check (ties to L2-OPS-003).** Warn users below
  ~16 GB RAM that the 8B model will be too slow to be usable — the 6 GB test
  VM proved this (~90 s for a two-word reply due to swap thrashing).
  Optionally prefer/offer a smaller model on low-RAM machines instead of
  silently being unusably slow.

- **Liquid Glass / macOS 26 app icon.** v1.3 ships the classic PNG
  `AppIcon.appiconset`. When we target macOS 26, wire the layered Icon
  Composer design (Default / Dark / Tinted / Clear) from the "macOS app icon
  design" project so the system generates appearances automatically.

- **Re-enable the beta skill-update channel.** Disabled in v1.3 (stable-only)
  in `SkillUpdateManager` + hidden in Settings. Turn back on when there's a
  real beta manifest to point at.

- **[DONE 2026-07-10]** **Smoke-test timeout vs. the Settings "leash length"
  slider.** The smoke test used to wait a fixed 180 s while the watcher's own
  request timeout came from `bridge_config.json` (default 120 s, slider up to
  300 s) — so a leash above 3 min let the watcher outlast the smoke test and
  red-X a working bridge. `BridgeSmokeTest` now reads the same
  `delegation_timeout_seconds` and waits that + a 60 s margin (falling back to
  120+60 = 180 s, the old value, when the config is absent). *Surfaced for
  real by the 2026-07-10 slow-VM ping test:* ~72 s inference on a CPU-only VM
  kept tripping the 120 s watcher cap, and raising the leash would otherwise
  have desynced the wizard's smoke test. File: `BridgeSmokeTest.swift`.

- **Skill auto-update hardening (L2-OPS-010 TBDs).** The downloaded payload
  isn't code-signed/verified beyond the SHA-256 in the manifest, and there's
  no in-app "roll back" surface (a `.bak` of the prior version is kept, but
  only recoverable by hand).

- **Housekeeping.** Delete the remaining dead scaffolds (`swiftui_app_v2`,
  `swiftui_app_v3`, `swiftui_scaffold`) the way we removed v4; and sync the
  stray `cloud-to-ground-ai-repo/start_local_ai.sh` copy up to the v0.2.8
  python3-free (perl) watcher.

---

## v2.0 (paid release, ~Dec 2026)

Move from free preview to a paid subscription via a **Merchant of Record**
(Lemon Squeezy — handles checkout, recurring billing, and global tax for ~5%),
with a light in-app license check. Full plan, tiering, engineering tasks, and
timeline in **`planning/v2-monetization-plan.md`**. Resolves SE action
`ACT-007`. Five decisions still open (platform confirm, free/paid line,
pricing, trial, existing-user conversion) — see §7 of the plan.

