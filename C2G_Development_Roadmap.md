# Cloud2GroundAI — Development Roadmap

**Version:** 0.1 Draft  
**Date:** June 2026  
**Author:** Andrew Carlile

---

## Product Vision

Cloud2GroundAI is a Mac-native workflow package for software developers who use Claude Pro/Cowork/Code and want to reduce cloud inference costs without compromising on model provenance. All local inference runs on IBM Granite 4.1 via Ollama — entirely Western-sourced, Apache 2.0 licensed, auditable. The cloud (Claude) stays as the senior engineer; Granite handles the mechanical work.

The product ships as two tightly coupled components:

1. **C2G App** — a native macOS menubar app that installs, manages, and updates the full stack
2. **C2G Skill** — a Claude Cowork/Code plugin that routes mechanical subtasks to the local bridge

---

## Architecture Overview

```
┌─────────────────────────────────────────────┐
│  Claude (Cowork / Code)                     │
│  ┌───────────────────────────────────────┐  │
│  │  C2G Skill (ollama-delegate)          │  │
│  │  - Decides when to delegate           │  │
│  │  - Writes request to bridge folder    │  │
│  │  - Reads + reviews response           │  │
│  └────────────────┬──────────────────────┘  │
└───────────────────┼─────────────────────────┘
                    │ local filesystem only
┌───────────────────┼─────────────────────────┐
│  C2G App (menubar)│                         │
│  ┌────────────────▼──────────────────────┐  │
│  │  Bridge Watcher (start_local_ai.sh)   │  │
│  │  - Polls ~/Documents/claude_bridge/   │  │
│  │  - Sends prompt to Ollama via HTTP    │  │
│  │  - Writes response back               │  │
│  └────────────────┬──────────────────────┘  │
│                   │ localhost:11434          │
│  ┌────────────────▼──────────────────────┐  │
│  │  Ollama                               │  │
│  │  Model: granite4.1:8b               │  │
│  └───────────────────────────────────────┘  │
└─────────────────────────────────────────────┘
```

No network traffic. No credential sharing. No proxying of Claude.  
Everything local runs on the user's own hardware.

---

## Goal 1 — Installer + Native macOS Menubar App

### Summary

A Swift/SwiftUI menubar app that handles the full lifecycle: first-time install, daily operation, and updates. Replaces the current manual terminal workflow entirely.

### Target user experience

1. User downloads `C2G.dmg`, drags to Applications
2. Launches C2G — menubar icon appears
3. First-run wizard: checks for Homebrew, installs Ollama, pulls `granite4.1:8b`, installs the Claude skill, sets up the bridge folder and LaunchAgent
4. Icon turns green — bridge is active
5. User opens Claude Cowork/Code and works normally — delegation happens silently

### Menubar app features (v1.0)

**Status indicator**
- Green dot: bridge running, Ollama responsive
- Yellow dot: bridge running, Ollama loading model (warm-up)
- Red dot: bridge stopped or Ollama unreachable
- Click to open menu

**Menu items**
- Bridge: Running / Stopped [toggle button]
- Model: granite4.1:8b
- Cores: 1 active (free tier) / Unlock more →
- ─────────────
- Check for Updates
- Open Bridge Logs
- ─────────────
- Quit C2G

**First-run installer wizard (separate window)**
- Step 1: Welcome + what C2G does
- Step 2: Dependency check (Homebrew, Ollama) — auto-install with user permission
- Step 3: Model download (granite4.1:8b, ~5GB — shows progress)
- Step 4: Skill install — shows .skill file, links to Claude Settings → Capabilities
- Step 5: Done — menubar icon goes green

### Update mechanism

C2G checks a GitHub releases endpoint on launch and once daily. When an update is available:
- Menubar icon shows a badge
- Menu shows "Update available: v1.x.x"
- One click downloads and replaces the watcher script + skill file
- No full app reinstall required for skill/watcher updates (only .app updates need DMG)

Update channels:
- **Watcher script** (`start_local_ai.sh`): downloaded from GitHub, replaces `~/Library/Application Support/claude_bridge/`
- **Skill file** (`.skill`): downloaded from GitHub, user prompted to reinstall via Settings → Capabilities
- **Model tuning** (automatic, no user action): pulled as part of watcher update
- **App itself**: sparkle-style update prompt, downloads new DMG

### Future features (post-v1.0)

- **Add local model**: menu option to pull additional Ollama models and configure them as additional cores
- **Core management**: UI for enabling/disabling cores, setting delegation priority
- **Purchase flow**: "Unlock additional cores" opens payment page (Stripe/Gumroad), license key activates additional core slots in the app
- **Usage stats**: tokens saved, tasks delegated, estimated cost savings

### Tech stack

| Component | Technology | Rationale |
|---|---|---|
| Menubar app | Swift + SwiftUI | Native macOS, no runtime deps, looks right |
| Background service | Existing bash watcher | Already works, proven protocol |
| Ollama communication | URLSession (HTTP to localhost) | Simple, no third-party libs needed |
| Update checks | URLSession + GitHub API | No Sparkle dependency for v1 |
| Installer wizard | SwiftUI sheet/window | Consistent with menubar app |
| DMG packaging | `create-dmg` (Homebrew) | Standard macOS distribution |

### File layout

```
C2GApp/
├── C2GApp.swift              # App entry point, menubar setup
├── AppDelegate.swift         # NSStatusItem, menu construction
├── BridgeManager.swift       # Start/stop watcher, check Ollama health
├── InstallerWizard.swift     # First-run setup flow
├── UpdateChecker.swift       # GitHub releases polling
├── Views/
│   ├── StatusMenuView.swift  # The dropdown menu
│   ├── WizardView.swift      # First-run wizard
│   └── LogsView.swift        # Bridge log viewer
└── Resources/
    ├── start_local_ai.sh     # Bundled watcher (updated on app update)
    └── ollama-delegate.skill # Bundled skill file
```

### Development sequence

1. `BridgeManager.swift` — start/stop watcher process, poll Ollama health endpoint, publish status to SwiftUI
2. `AppDelegate.swift` — basic menubar icon + menu with live status
3. `InstallerWizard.swift` — first-run flow (Homebrew check → Ollama install → model pull → skill prompt)
4. `UpdateChecker.swift` — GitHub releases check, download watcher/skill updates
5. DMG packaging + code signing (requires Apple Developer account)

---

## Goal 2 — Official Claude Plugin Marketplace Listing

### Summary

Get C2G listed in Anthropic's official plugin directory at `claude.com/plugins`. The free tier (1 core) is the listing. Paid tiers are handled externally.

### Two-track distribution

**Track A — Community self-install (immediate, no approval needed)**

Host a `marketplace.json` on GitHub. Any user can add it with:
```
/plugin marketplace add https://github.com/[your-org]/c2g-plugins
```

This is live as soon as the GitHub repo is set up. Good for early adopters and beta testers.

**Track B — Official claude.com/plugins listing (requires Anthropic approval)**

Requirements (based on Anthropic's current submission process):
- Stable GitHub repo with `marketplace.json`
- Landing page describing the plugin
- Privacy policy
- Support contact
- Plugin must pass Anthropic's automated validation + safety screening
- For curated listing: Anthropic discretion

**Sequencing:** Send legal paper to Anthropic → get approval/feedback → submit for official listing. The legal paper establishes the relationship and pre-empts any harness-ban concern.

### Freemium model

| Tier | Price | What you get |
|---|---|---|
| Free | $0 | 1 local core (granite4.1:8b), skill + watcher, community support |
| Pro | TBD | Additional model slots, priority model updates, email support |
| Team | TBD | Shared bridge configs, team licensing, invoice billing |

Payment handled externally (Stripe or Gumroad). License key unlocks additional core slots in the C2G App. The Claude plugin itself remains free and open — monetisation is through the App.

### What goes in the marketplace listing

- **Name:** Cloud2GroundAI
- **Tagline:** Run IBM Granite locally. Let Claude stay in charge.
- **Description:** Reduces cloud token usage by delegating mechanical coding tasks to a local IBM Granite 4.1 model running via Ollama. Western-sourced, Apache 2.0 licensed, zero network traffic. Requires Claude Pro+ and an Apple Silicon Mac.
- **Category:** Developer Tools
- **Requirements:** Claude Pro or higher, macOS (Apple Silicon), C2G App installed

---

## Development Principles

**Senior/junior model applies to our own development too.** Claude (me) designs, architects, and reviews. Granite handles boilerplate Swift code generation via the bridge. This keeps cloud token costs low and dogfoods the product as we build it.

**No non-Western dependencies.** Every library, tool, and model in the stack should be from a Western-headquartered company with auditable training data. This is a feature, not a constraint.

**Skill-first updates.** The skill and watcher can be updated without a full app release. Design the app so skill/watcher updates are decoupled from `.app` updates — faster iteration, lower friction for users.

**The bridge protocol is stable.** Do not change the request.txt/response.txt/consumed.txt protocol without a version bump. Future features (multiple cores, model switching) extend the protocol, never break it.

---

## Milestones

| Milestone | Description | Depends on |
|---|---|---|
| M1 | BridgeManager + basic menubar status | — |
| M2 | InstallerWizard (full first-run flow) | M1 |
| M3 | UpdateChecker + one-click watcher/skill update | M1 |
| M4 | DMG packaging + signing | M2, M3 |
| M5 | Community marketplace.json on GitHub | M4 |
| M6 | Anthropic legal outreach + feedback | Legal paper done ✓ |
| M7 | Official claude.com/plugins submission | M5, M6 |
| M8 | Purchase flow + license key activation | M4 |

---

## Open Questions

- **Apple Developer account**: do you have one? Code signing and notarization are required for DMG distribution outside the Mac App Store. If not, that's a prerequisite before M4.
- **GitHub org**: will C2G have its own org/repo, or live under your personal account?
- **App name**: "Cloud2GroundAI" is the product name — is "C2G" the right short form for the app?
- **Pricing**: Pro and Team tiers are TBD — worth deciding before M8 so the purchase flow is designed correctly.
