# Cloud2GroundAI — Architecture Sketch

**Status:** Sections 2–9 describe an earlier draft architecture (chat app with three modes). That architecture was walked back 2026-06-27 PM after Andrew clarified the actual product vision. **§11 Architecture Correction is the current source of truth.** §§2–9 are retained for traceability but their structural claims are superseded by §11.

**Last updated:** 2026-06-27 (PM revision — architecture correction)

---

## 1. What the system is

A macOS application that lets a user converse with an AI in one of three operating modes — Cloud, Hybrid, or Ground — and that always makes the user aware of which AI is answering and what trade-offs they are accepting. Ground mode runs entirely on the host Mac with the network radio off; Hybrid uses a cloud model as orchestrator and a local model as delegate to reduce cloud-token spend; Cloud is direct conversation with a cloud model when the user wants maximum capability and doesn't mind the cost.

The whole thing exists because off-grid AI conversation matters (PRD-001), token reduction is a real economic and energy win when online (PRD-002), users must never be silently downgraded (PRD-003), the host runs on renewable power (PRD-004), and a non-developer should be able to install and use it without a terminal (PRD-005).

---

## 2. Top-level components

```
┌─────────────────────────────────────────────────────────────────┐
│                      SwiftUI App (host process)                 │
│                                                                 │
│  ┌─────────────┐   ┌─────────────────┐   ┌──────────────────┐  │
│  │   GUI Layer │   │ Mode Manager    │   │ Network Watcher  │  │
│  │  - Convo    │←──│  - State machine│←──│  - SCNetwork     │  │
│  │  - Mode chip│   │  - Transitions  │   │    Reachability  │  │
│  │  - Net chip │   │  - Thread reset │   │  - online/offline│  │
│  └─────────────┘   └────────┬────────┘   └──────────────────┘  │
│        ▲                    │                                   │
│        │            ┌───────┴───────┐                           │
│        │            ▼               ▼                           │
│        │   ┌─────────────┐  ┌──────────────┐                    │
│        │   │ Cloud Client│  │ Local Client │                    │
│        │   │  - Anthropic│  │  - Ollama    │                    │
│        │   │    API      │  │    via HTTP  │                    │
│        │   └──────┬──────┘  └──────┬───────┘                    │
│        │          │                │                            │
│        │   ┌──────┴────────────────┴───────┐                    │
│        └──→│       Conversation Store      │                    │
│            │   - Per-thread history        │                    │
│            │   - Per-response attribution  │                    │
│            └───────────────────────────────┘                    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
       │                                              │
       │ (Hybrid mode only)                           │ (Ground/Hybrid)
       ▼                                              ▼
┌──────────────┐                              ┌──────────────────┐
│  Bridge IPC  │                              │   Ollama (host)  │
│  (file-based │                              │   - granite-code │
│   v0.2+)     │                              │   - or qwen      │
└──────┬───────┘                              └──────────────────┘
       │
       ▼
┌──────────────────────────────┐
│ Claude (cloud, via bridge or │
│  direct API per Hybrid mode  │
│  design TBD — see §6)        │
└──────────────────────────────┘
```

---

## 3. Mode state machine

The Cloud/Hybrid/Ground mode is the primary state in the system. Every conversation thread is bound to exactly one mode for its lifetime (L2-MOD-002). A mode change starts a new thread.

```
                ┌─────────────────────────────────────┐
                │           Mode Manager              │
                │                                     │
   user toggle  │   ┌─────────┐    user toggle        │
   ─────────────┼──►│  Cloud  │◄────────────┐         │
                │   └────┬────┘             │         │
                │        │ user toggle      │         │
                │        ▼                  │         │
                │   ┌─────────┐    user     │         │
                │   │  Hybrid │◄────────────┤         │
                │   └────┬────┘             │         │
                │        │ user toggle      │         │
                │        │ OR network drop  │         │
                │        ▼                  │         │
                │   ┌─────────┐             │         │
                │   │  Ground │─────────────┘         │
                │   └────┬────┘  user toggle          │
                │        │ (network back +            │
                │        │  user toggle)              │
                │        └────────────────────────────│
                │                                     │
                └─────────────────────────────────────┘
```

Rules:
- Manual toggle always wins (L2-MOD-002 — atomic, user-visible).
- Automatic transition only fires once and only in the safe direction: online → offline forces Cloud or Hybrid down to Ground. The reverse (offline → online auto-upgrade) never happens silently because it would change the answering AI mid-thread.
- Every transition triggers (a) a degradation notice if downgrading (L2-GUI-003), (b) a fresh thread (L2-MOD-002), (c) updated mode indicator (L2-GUI-002).

---

## 4. Data flow per mode

### Cloud mode
User message → Cloud Client → Anthropic API → response → Conversation Store (attribution: "Claude") → GUI.

Local model and bridge are idle. Local model may still be resident in memory to keep cold-start latency low for mode switches — TBD energy trade against the L2-PWR-002 idle budget.

### Hybrid mode
User message → Cloud Client (cloud is orchestrator per L2-AI-005). Cloud decides whether to delegate any sub-task to the local model. If so:
- Cloud Client writes to the bridge (request.txt with id-line per v0.2 protocol).
- Bridge IPC hands it to local Ollama.
- Local response comes back via response.txt.
- Cloud Client incorporates the local sub-response into its own answer.
- Per-response attribution carries both AIs' contributions (L2-AI-006).
- User sees one stream (L2-AI-005).

**Open architectural question (ACT-005-adjacent):** Does the cloud-orchestrator pattern stay file-bridge-based in the productized app, or does the app talk to the Anthropic API directly and use the bridge only for routing logic? The current SE assistant + Claude-Code + bridge pattern works because the cloud client is *Claude itself*. In a SwiftUI app, the cloud client is the *app* talking to the Anthropic API. The bridge protocol may simplify to in-process IPC between modules. Flagging this as a §6 trade study.

### Ground mode
User message → Local Client → Ollama on localhost → response → Conversation Store (attribution: local model name and version) → GUI.

No outbound network calls at all (L2-MOD-001). Cloud Client is idle and unreachable. Network Watcher continues to monitor connectivity so it can update the indicator (L2-GUI-004) but does not cause a mode change.

---

## 5. L2 ownership by component

| Component | Owns these L2s |
|---|---|
| GUI Layer | GUI-001, GUI-002, GUI-003, GUI-004, GUI-005 |
| Mode Manager | MOD-001, MOD-002 |
| Network Watcher | NET-001 |
| Cloud Client | AI-003 (routing), AI-005 (hybrid stream), AI-006 (attribution-cloud-side) |
| Local Client | AI-001, AI-002, AI-004, AI-006 (attribution-local-side), AI-007 |
| Bridge IPC | BRG-001, BRG-002, BRG-003 |
| Conversation Store | AI-006 (storage of attribution) |
| Installer / first-run | OPS-001, OPS-002, OPS-003, OPS-004 |
| Packaging | PLAT-001, PLAT-002 |
| Power-aware idle policy | PWR-001, PWR-002 |

---

## 6. Open architectural trade studies

Per the skill's §3.4 — weight by mistake-cost and risk, not by price. These should resolve before code dependencies on them harden.

### TS-001 — Cloud client architecture in Hybrid mode
Do we use the existing file-bridge to route between cloud and local, or does the SwiftUI app talk to the Anthropic API directly and call Ollama directly, with the bridge protocol becoming an internal IPC abstraction? Trade dimensions: implementation effort, observability, ability to evolve the routing policy, energy cost of the bridge polling pattern. Recommendation pending.

### TS-002 — Default local model: granite-code:8b vs qwen2.5-coder:7b
Both meet the L2-AI-001 / L2-AI-007 thresholds on the reference machine. Granite has better delegation track record on this project (gethostname case study). Qwen is smaller, faster cold-start. Trade dimensions: usability for non-code conversation, memory, latency, output quality. Recommendation pending — likely keep both available with granite as default.

### TS-003 — Distribution mechanism (driven by ACT-005)
Mac App Store vs notarized DMG. App Store gives auto-updates and easier install at the cost of sandbox constraints and review process; notarized DMG gives freedom (bundle Ollama, write outside sandbox) but requires hand-rolled update mechanism (Sparkle?). Trade dimensions: ease of install for non-developers (PRD-005), ability to bundle the local model runtime, recurring developer-program cost, update reliability.

### TS-004 — Local model bundling vs first-run download
Bundle Ollama + a default model in the .app for guaranteed first-run success at the cost of a much larger download. Or download on first run with a progress UI. Coupled to TS-003.

### TS-005 — UI framework
SwiftUI is the assumed choice (Xcode installed, native macOS, no other dependency). Cross-platform (Tauri, Electron) would broaden reach but adds runtime weight and complicates the PRD-004 energy story. Recommend keeping SwiftUI unless we have a compelling cross-platform target later.

---

## 7. Component boundaries — what is a clean interface

Three boundaries deserve explicit attention because changes across them are the ones most likely to break things later:

**App ↔ Ollama.** Today via HTTP at localhost:11434. The Local Client should wrap this so the rest of the app talks to a `LocalAI` protocol, not directly to URLSession against localhost. That way swapping the local backend (e.g. to MLX-native) is a single-file change.

**App ↔ Anthropic API.** Same logic — wrap behind a `CloudAI` protocol. Mode Manager picks which conforming instance to use.

**Mode Manager ↔ Conversation Store.** The Mode Manager owns the invariant that a thread is bound to one AI. The Store should refuse to attach a response from `LocalAI` to a thread that was started by `CloudAI` (or vice versa), or it should auto-create a new thread on the mismatch. The first option is safer.

---

## 8. The scaffolding plan (what gets built first)

In order — each step picks up one or more L2s:

1. **App skeleton + mode state model.** ContentView, ModeManager (enum + state), ModeIndicator chip, mode toggle UI. Closes L2-MOD-001 (Ground-mode capability is a state at this point, not yet inference), L2-GUI-002 (mode indicator visible).

2. **Network watcher + status chip.** NWPathMonitor, NetworkStatus model, NetworkStatusChip in the GUI. Closes L2-NET-001 and L2-GUI-004. Automatic transition online→offline wires in here.

3. **Conversation Store + mock CloudAI/LocalAI.** Per-thread history with attribution. Mock backends return placeholder text so the rest of the UI can be exercised. Closes L2-AI-006 (storage side).

4. **Real LocalAI via Ollama.** Replace the mock with HTTP calls. Closes L2-AI-001, L2-AI-002, L2-AI-007 (memory verification).

5. **Real CloudAI via Anthropic API.** Same pattern. Adds API key handling — note this is a PRD-005 implication (non-developer onboarding for API keys is its own UX problem; consider a Hybrid-only mode where the user signs in once).

6. **Mode transition logic + thread reset + degradation notice.** Closes L2-MOD-002, L2-GUI-003.

7. **Hybrid orchestration.** Cloud asks Local for help on delegated subtasks. Routing policy starts simple (use ollama-delegate skill's universal tests) and tunes after measurement. Closes L2-AI-003, L2-AI-004, L2-AI-005, L2-BRG-001, L2-BRG-002.

8. **First-run onboarding + local model install.** Closes L2-OPS-001, L2-OPS-003, L2-GUI-005, contributes to L2-OPS-002.

9. **Packaging, signing, notarization, update mechanism.** Closes L2-PLAT-001, L2-PLAT-002, L2-OPS-004. Blocked on Apple Developer Program enrollment completion.

10. **Power audit + tuning.** Measures against L2-PWR-001 and L2-PWR-002. Tunes idle and polling behavior to fit. Closes the power story for PRD-004.

Step 1 is what the SwiftUI scaffold delivers. Steps 2–6 are the first prototype. Steps 7–10 are the production push.

---

## 10. Addendum — 2026-06-27 decisions

Several substantive decisions landed after the first-pass sketch was written. They are captured here rather than rewriting the whole document; the sketch above remains accurate at the structural level but should be read with these updates in mind.

### License and distribution (closes ACT-005, opens ACT-007)

The v1.0 release is licensed **Apache 2.0**. Source ships on GitHub; binaries distribute as a **notarized DMG via GitHub Releases**. The whole v1.0 phase is free, framed as a public preview that runs **through 2026-11-30**.

v2.0 is paid. The distribution mechanism for v2.0 (Mac App Store with an MLX pivot to escape the Ollama sandbox problem, vs. notarized DMG + Paddle/Lemon Squeezy, vs. a hybrid where both exist) gets picked by **2026-10-15** under ACT-007. That deadline is six weeks before the free-preview window ends — enough time to migrate.

Why Apache 2.0 specifically: generous, recognized, mild patent grant, fully compatible with charging for binaries and subscriptions. The "license pivot to BSL" option (Sentry / HashiCorp pattern) remains available for v2.0+ if the open license becomes a competitive problem later.

### PRD-003 expanded — honest visibility + data sovereignty (PRD-007 folded in)

The privacy thread was originally proposed as a new L1 (PRD-007 — User data sovereignty). Andrew chose to fold it into PRD-003 instead because both threads share the same foundation: trust. Knowing which AI is answering and knowing what data the system collects are two faces of the same product commitment.

PRD-003 now covers: mode/AI attribution (the original scope), capability-degradation disclosure on mode change (the original scope), AND default-local data sovereignty with per-channel opt-in for any upload. Derived L2s now under PRD-003: L2-OPS-006 (delegation telemetry, local-only), L2-OPS-007 (opt-in feedback), L2-OPS-008 (opt-in usage telemetry), L2-GUI-008 (privacy settings panel).

This is also reflected in the product positioning captured in `metadata.json`: "We sell the connection, the maintained skill, and the auto-updates. We do not sell the local AI (Granite stays on your machine). We do not collect your content. Telemetry and feedback are opt-in and off by default."

### Hybrid mode routing policy is now split (updates L2-AI-003)

Original L2-AI-003 said "delegate to local when the task is well-specified and quality is achievable." That stays, with an addition:

- **Code work delegated to local: no Claude verification.** Andrew's reasoning: code is self-verifying. The compiler and the runtime catch any hallucinated APIs or wrong logic when the user actually runs the result. Claude doesn't need to read every Granite response.
- **Non-code work delegated to local: mandatory Claude verification.** Writing, summarization, Q&A facts can't be self-verified by the user. Claude reads the local output and confirms before display. Verification cost is ~0.3x of cloud-only, so the math still favours delegation comfortably.

This affects the data flow in §4 — Hybrid mode for non-code tasks has a mandatory verification step between local response and user display.

### Two-tier local model strategy (updates L2-AI-007, L2-OPS-003, closes TS-002)

The product ships with **two granite4.1 tiers** at v1.0 (locked 2026-06-27 after Ollama library verification):
- **Small tier:** `granite4.1:8b` at Q4, ~5 GB resident. Runs on Apple Silicon Macs with ≥16 GB RAM.
- **Large tier:** `granite4.1:30b` at Q4, ~18 GB resident. Targets Macs with ≥24 GB RAM (Andrew's M5 24GB qualifies).

Both tiers support 32K–128K practical context, native code, tool use, and structured JSON output. Single-family choice (granite4.1 at two sizes) keeps the skill-maintenance burden manageable per Andrew's "1 or 2 local AIs at a time" preference. IBM's published benchmarks claim 8B "beats 32B" competitors.

At install / first run, the system detects machine capability and recommends a tier (L2-OPS-003 update). User can override. Only one tier is resident at runtime.

### Long-context handling — much less critical than initially feared (updates L2-AI-002)

Original concern: code-review prompts ("paste a file") would exceed Granite 8B's 8K context. **With granite4.1, this largely goes away** — both tiers support 32K–128K practical context, which absorbs the bulk of Andrew's observed workload. The long-context-to-Claude routing remains as a guarantee for outlier multi-file pastes, but is expected to fire rarely. This pushes the cost projection (~79% reduction) further toward the conservative side of optimistic.

### Cost projection — the 50% target is conservative

Running the worksheet-derived workload mix through the ollama-delegate cost model gives an estimated total cost multiplier of ~0.21, i.e. **~79% reduction**. The 50% L1 target stays as the public commitment (under-promise) but internal expectation is in the 60-70% range. If sustained measurement comes in under 50%, something is wrong — most likely either the routing policy is mis-classifying tasks or the verification overhead is larger than projected.

### Trade study updates

- **TS-002** (local model choice) — closed 2026-06-27. We ship `granite4.1:8b` (small) and `granite4.1:30b` (large). Granite 4.1 chosen over granite-code (the 2025 family) for its much larger practical context window (32K–128K vs 8K), native tool-use, and IBM's recent benchmarks. Qwen and other families are not in the running for v1.0 — single-family commitment keeps the skill maintainable.
- **TS-003** (distribution mechanism) — closed for v1.0 (notarized DMG via GitHub Releases, Apache 2.0). Re-opens for v2.0 as ACT-007.
- **TS-004** (bundle vs first-run download) — leaning toward first-run download with progress UI for both tiers, because bundling both would push the DMG over 10 GB. Confirmed as soon as we benchmark download UX.
- **TS-005** (SwiftUI vs cross-platform) — unchanged, SwiftUI.

### New trade study

- **TS-006** (Ollama vs MLX as local backend) — opened. If we go to the Mac App Store for v2.0, Ollama's sandbox incompatibility forces a pivot to MLX. MLX runs in-process, sandbox-friendly, but is its own framework with its own model formats. This study needs to happen during the free-preview window so we know whether the App Store path is viable for v2.0.

### v1.1 roadmap items (lessons from real delegation use)

The 2026-06-27 STRUVE thermal delegation session produced concrete UX findings that don't belong in v1.0 but should land in the first patch release:

- **Warm-up ping for granite.** Cold-start latency observed: ~19s on the first delegation after a watcher restart, dropping to ~6s on warm subsequent delegations. When the user is active in Claude Desktop and the bridge is idle, the watcher should ping granite periodically (every ~5 min) to keep the model resident. Trade-off against PWR budget — needs a careful idle-power measurement to confirm it stays inside L2-PWR-002 ≤0.5W headroom. Owning L2: candidate L2-BRG-004 (warm-keep policy).
- **"Sanity-cases-included" delegation flag in the skill.** For numerical/scientific code, the skill should generate the delegation prompt with explicit sanity-case requests pre-filled, e.g. "Provide N test cases against published reference values." Reduces the manual burden on the cloud verifier. Owning L2: extension of L2-AI-003.
- **Per-model tuning files as living artefacts.** `skill/models/granite4.1.md` now contains the observed-weaknesses → mitigations section that was empty in `_template.md`. Each new delegation outcome that surfaces a new failure mode should land here. The auto-update channel (L2-OPS-010) is the productized version of "patterns from many users' logs become updates everyone gets."
- **User-configurable delegation timeout** (per Andrew 2026-06-29). The bridge protocol currently hardcodes a 90s response wait. Different users have different patience and different machine speeds — slower Macs running the larger Granite tier will naturally take longer than reference-machine timings. Surface this as a settings-panel control: default 60s, range 15s-300s. When the timeout fires, the skill should mark the delegation as `abandoned_for_cloud` and Claude completes the task directly. Owning L2: extension of L2-OPS-006 (telemetry tracks abandoned outcomes per task class so users can tune their own timeout based on observed patterns).

### v2.0 product features (post-2026-11-30, paid release)

The free v1.0 preview targets the general AI-assisted-knowledge-worker audience. v2.0 introduces a **C2G Pro for Developers** tier — a paid SKU specifically for Mac developers — confirmed as the direction by Andrew 2026-06-29.

Pro-tier additions on top of the base C2G:

- **Xcode awareness.** The C2G app and skill understand `.xcodeproj` structure (targets, schemes, build phases). The status panel surfaces "Xcode project detected" with build status and the active target. The skill can read xcodebuild output, parse errors, and feed them into Claude conversations automatically.
- **Per-file routing override.** Project-level config that says "Views/* → always cloud, Models/* → try granite first." Today's lessons (SwiftUI structural work is above granite's comfort zone, AppKit boilerplate is OK) become user-configurable per project. Lives in a `.c2g-routing` config file at the project root.
- **Xcode Source Editor extension.** A small Xcode app extension that adds menu items: "Ask Claude (current selection)", "Ask Granite (current selection)", "Review this file with Claude." Routes through the existing C2G bridge — no new authentication path.
- **Build-error capture loop.** When the user runs ⌘B in Xcode and it fails, C2G can offer to send the failing file + error text to Claude automatically. Same harness-ban-safe architecture as the base product: the call goes through the user's own Claude Desktop / Cowork install, not through C2G's servers.
- **Code-specialized local model option.** Pro users can opt into a `granite-code:8b`-class model alongside or instead of `granite4.1:8b` for code tasks specifically, since code-specialized models outperform general-purpose ones on Swift / Python / TypeScript work.
- **"Fresh-folder drop" helper for multi-file Xcode iteration.** Captured 2026-06-29 after a real session: when a lot of files change across multiple build steps, Xcode's cached file references + ProtonDrive/iCloud sync lag combine to produce phantom errors that survive deletion + re-drag. Dropping the new file set into a fresh versioned folder (vN → vN+1) at a new path bypasses both caches and reliably gets to a clean build. The Pro app could automate this: detect "user is iterating on a Mac project," provide a one-click "Stage to v(N+1)" action that copies the current swiftui_app_v{N}/ folder to a v(N+1)/ sibling, opens Finder at the new location, and gives the user a checklist of the import steps. Saves the hour-long debugging cycle of "is Xcode actually compiling what I think it is."

Pricing thought (not committed): Pro is a single SKU above the base C2G subscription — covers all of the above as a bundle, not à la carte.

Anthropic-letter implication: the Xcode features still don't make Claude API calls themselves. They install a skill into the user's Cowork install (sanctioned plugin path) and run a Source Editor extension that talks to the same bridge. The v3 letter's structural argument continues to hold; the Pro features are a richer skill, not a different relationship with Anthropic.

Owning actions (new): would open ACT-008 (scope C2G Pro v2.0 feature set) and ACT-009 (decide whether Pro is bundled into the v2.0 paid SKU or stratified — base subscription + Pro upsell).

---

## 11. Architecture Correction — 2026-06-27 PM

The architecture described in §§2–9 above was a misreading of Andrew's product vision. This section supersedes those sections at the structural level. The L1/L2 SE work and the addendum-§10 decisions (license, model tiers, routing policy) remain valid; what changes is the shape of the product they describe.

### What C2G actually is

C2G is a small macOS app and a set of background components that, together, enable the user's existing Claude workflow to consume fewer cloud tokens by delegating mechanical work to a locally-installed Granite model. It is not a chat client. The user's primary AI surface remains Claude Desktop, Claude CLI, or Cowork — whatever they already use.

Three components, with distinct user-facing roles:

**The installer/manager app** is what the user runs once at first launch. It walks them through installing Ollama (if missing), pulling the right `granite4.1` tier for their machine, dropping the `ollama-delegate` skill into Cowork's skill directory, and registering a LaunchAgent for the bridge watcher. After this first run, the user rarely opens the app again unless something breaks or they want to change settings.

**The background service** — the bridge watcher plus the menu bar item — runs from then on as a per-user LaunchAgent. The watcher provides the file-based IPC that Claude (running in the official Claude Desktop / CLI / Cowork) uses to delegate work to local Granite. The menu bar item shows, at a glance, whether the bridge is up and whether the user is online. This is the surface the user lives with most of the time. No dock icon by default.

**The Ground-mode chat window** opens from the menu bar (manually, or auto-opened when the user attempts a Claude action while offline). It is a simple conversation interface backed solely by the local Granite model. There is no mode toggle inside it — it is Ground mode by definition. It is the offline fallback, not a competing client to Claude Desktop.

### Component diagram (corrected)

```
┌────────────────────────────────────────────────────────────────┐
│            macOS user session                                  │
│                                                                │
│  ┌─────────────────┐         ┌──────────────────────────────┐  │
│  │  Claude Desktop │         │  C2G menu bar app            │  │
│  │  / CLI / Cowork │  ───┐   │  - Status indicator          │  │
│  │  (the user's    │     │   │  - Quick actions             │  │
│  │   primary AI    │     │   │  - Status panel              │  │
│  │   surface)      │     │   │  - Ground chat window        │  │
│  └────────┬────────┘     │   │  - Settings                  │  │
│           │              │   └────────┬─────────────────────┘  │
│           │ via skill    │            │                        │
│           │ + bridge     │            │ shows status of:       │
│           ▼              │            ▼                        │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │   ollama-delegate skill (installed in Cowork)           │   │
│  │   + bridge watcher (LaunchAgent, file-based IPC)        │   │
│  │   + Ollama + granite4.1:8b or :30b                      │   │
│  │   ↑ all installed and updated by the C2G app            │   │
│  └─────────────────────────────────────────────────────────┘   │
│                            ▲                                   │
│                            │                                   │
│                            ▼                                   │
│                  ┌─────────────────┐                           │
│                  │   Anthropic     │ (user's own subscription, │
│                  │   API endpoint  │  C2G never touches it)    │
│                  └─────────────────┘                           │
└────────────────────────────────────────────────────────────────┘
```

### Data flow per scenario

**User online, working in Claude Desktop.** User asks Claude something. Claude (running in Claude Desktop with the user's own subscription) reads the ollama-delegate skill, decides whether to delegate part of the work to local Granite. If so, Claude writes a request to the bridge folder; the watcher (running as the user's LaunchAgent) picks it up, runs Ollama locally, writes the response back. Claude integrates the local result into its answer to the user. The C2G app itself does not appear in this data path — it just installed and maintained the skill and the watcher. The user pays Anthropic for Claude tokens (fewer than they would have without the skill); they pay no one for the Granite tokens because Granite runs on their own hardware.

**User goes offline.** Network drops. Claude Desktop fails because it depends on the Anthropic API. The user clicks the C2G menu bar item, picks "Open Ground chat." A window opens; the user converses with local Granite. When the network comes back, the user closes the Ground chat window and returns to Claude Desktop.

**User wants to see what C2G is doing.** Clicks the menu bar item → "Status panel." Sees: Ollama running with version, granite4.1 tier currently loaded, bridge watcher up, ollama-delegate skill v1.2 installed in Cowork, last skill update timestamp, current connectivity, opt-in toggles, cumulative carbon estimate from PRD-006.

### What this means for the Anthropic positioning

The C2G app never makes calls to the Anthropic API on the user's behalf. The user's Anthropic subscription is unchanged and untouched. Claude Desktop talks to Anthropic; C2G talks to local Ollama. The skill living inside Cowork is what bridges the two. There is no OAuth code path, no API key handling, no subscription proxying in any C2G binary because there is no need for one.

This is structurally stronger than the v2 letter's argument (which described C2G as making API calls with user-provided keys). The corrected story is: C2G doesn't touch Anthropic infrastructure at all. It installs and maintains a skill that Claude itself uses to be more efficient.

### What this means for the SwiftUI scaffold

The existing scaffold's three-mode conversation view, mode indicator, degradation notice, cloud client protocol, and Hybrid mode logic are not part of the corrected product. They should be removed or repurposed:
- `ContentView.swift` (mode-toggle layout) → repurpose as the status panel window or remove.
- `ModeManager.swift` → remove (no in-app mode state machine).
- `ModeIndicator.swift`, `ModeToggle.swift`, `DegradationNoticeView.swift` → remove.
- `NetworkStatusChip.swift` → repurpose as a network status row inside the status panel.
- `ConversationView.swift` → simplify radically; back it only with `LocalAI` (no `CloudAI`); rename to `GroundChatView.swift`.
- `CloudAI.swift` → remove from the scaffold (no in-app cloud calls).
- `LocalAI.swift` → keep, will be backed by a real Ollama HTTP client.
- `OperatingMode.swift`, `NetworkStatus.swift`, `ConversationStore.swift`, `Message.swift`, `ConversationThread.swift` → simplify; remove mode-related fields.

The scaffold needs new files for: `MenuBarApp.swift` (app entry as `NSApplicationDelegate` driving an `NSStatusItem`), `StatusPanelView.swift`, `SetupWizardView.swift`, `SettingsView.swift` (already exists as a stub, expand).

That trim is queued as the next chunk of work; not in this turn because the letter is the priority deliverable.

### What this means for §§2–9 above

Those sections described a different product. The decisions captured in §10 (license = Apache 2.0; free preview through 2026-11-30; granite4.1:8b + granite4.1:30b tiers; routing policy split; long-context routing) all carry over unchanged — they apply to the corrected product the same way. The §§2–9 component descriptions, mode state machine, and data flows do not.
