<!--
Copyright 2026 Carlano Technology Solutions LLC
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0
-->

# Cloud2GroundAI

> A small macOS app and a Claude skill that quietly delegate mechanical
> coding work from cloud Claude to a local IBM Granite model running on
> your own machine.

[![License: Apache 2.0](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
[![Download](https://img.shields.io/badge/download-v1.5-blue)](https://github.com/carlanotech/Cloud2GroundAI/releases/latest)
[![Status](https://img.shields.io/badge/status-public%20preview-orange)](#status)
[![Platform: macOS 14+](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey.svg)](#requirements)

---

## What this is

This started in a solar-powered home, on an M-series MacBook Air, with
a single observation: most of what a cloud AI assistant does in a
coding session is **mechanical** — write a helper function from a clear
spec, add docstrings to a pasted block, transform a CSV into JSON,
fill out a template from a one-row example. The senior-engineer work —
design, judgment, debugging the weird stuff, reasoning across files —
is the small fraction. Everything else is execution.

The execution doesn't need to go to a datacenter. A small coding-tuned
model running locally on a laptop can do it. Every task that stays on
the laptop is datacenter water and power and tokens that nobody had to
spend, and a little bit of inference that ran off the sun.

This project is the contract that makes that handoff work. The cloud
model stays in charge of judgment. A small local model handles the
mechanical bits. They talk through a shared folder. **The user remains
a paying Claude customer; nothing flows through a third party.**

The defaults are deliberately Western-anchored — **IBM Granite 4.1**
as the primary model on **Ollama** as the runtime — so the project is
a clean fit for developers working under government contracts or other
regulated frameworks where a software-inventory review needs to come
back boring.

## The two pieces

Cloud2GroundAI ships as two coordinated parts:

**1. A small Mac app (the menu bar app)** that:
- Installs Ollama and pulls the recommended Granite model
- Installs the routing skill into your Cowork skills folder
- Runs the bridge watcher as a per-user LaunchAgent
- Shows the bridge state in a Status Panel
- Provides a Ground-mode chat window for when your internet is down

**2. A Claude skill** (`skill/`) that teaches Cowork / Claude Desktop /
Claude Code when to route a mechanical subtask to local Granite
through the bridge.

You install the Mac app once. After that, Claude does the right thing
silently.

## What happens in a delegation

You ask Claude to add a helper function that converts seconds to a
human-readable duration. Instead of generating it in the cloud, Claude
follows the skill's routing rules, decides the task is mechanical,
and writes a 40-word prompt to `~/claude_bridge/_bridge/request.txt`.
The local watcher notices the file, calls Granite via Ollama, writes
the answer to `response.txt`. Claude reads it, reviews it, drops it
into your code, and notes *(handled locally via granite4.1)*.

You saved a cloud round-trip on a task the local model handles
cleanly. If Granite gets it wrong, Claude catches the bug and patches
it — and that's still cheaper than writing from scratch. See
[`skill/SKILL.md`](skill/SKILL.md) for the full economic argument.

## Quickstart

### For users

Download the latest DMG from the
[releases page](https://github.com/carlanotech/Cloud2GroundAI/releases/latest),
open it, and drag Cloud2GroundAI into Applications. A step-by-step
**User Guide (PDF)**, with screenshots, is attached to each release
alongside the DMG. The first time you launch the app, click **Setup…**
from the menu-bar icon and the wizard will walk you through:

1. Installing Ollama (via Homebrew, or a manual download link)
2. Pulling a local model — Granite 4.1 8b/30b are the tested, suggested
   defaults (~5 GB / ~17 GB), but any Ollama model works
3. Installing the skill into `~/.claude/skills/ollama-delegate/`
4. Installing the watcher script
5. Registering the watcher as a LaunchAgent so it auto-starts
6. Running a smoke test to prove the whole stack is wired correctly

Total time, given a healthy internet connection: about ten minutes,
most of it model download.

After setup, open Claude as normal. Short mechanical subtasks will
quietly route to your machine.

### For people who want to install only the skill (no Mac app)

If you'd rather skip the app and wire everything by hand:

```bash
# 1. Install Ollama and the model
brew install ollama
ollama serve &                       # leave it running
ollama pull granite4.1:8b

# 2. Install the watcher script
mkdir -p "$HOME/Library/Application Support/claude_bridge"
cp start_local_ai.sh "$HOME/Library/Application Support/claude_bridge/"
chmod +x "$HOME/Library/Application Support/claude_bridge/start_local_ai.sh"

# 3. Run the watcher in a Terminal tab (or wire it as a LaunchAgent yourself)
bash "$HOME/Library/Application Support/claude_bridge/start_local_ai.sh"

# 4. Install the skill into Cowork
mkdir -p ~/.claude/skills/ollama-delegate
cp -R skill/* ~/.claude/skills/ollama-delegate/
```

That's it. The protocol is filesystem-only; nothing else has to change.

## Requirements

- **macOS 14 (Sonoma) or later**, Apple Silicon recommended
- **16 GB RAM** for the default `granite4.1:8b` model (32 GB for `:30b`)
- **~6 GB free disk** for the 8b model (~18 GB for 30b)
- **Claude Desktop, Cowork, or Claude Code** installed and configured

## The protocol is the asset

The Mac app and the watcher are reference implementations. The actual
asset is **[`protocol/SPEC.md`](protocol/SPEC.md)** — a small,
file-based contract for handing one mechanical subtask from a cloud
assistant to a local model. Alternative implementations (Python, Rust,
native daemons) are welcome and should pass the conformance tests at
`tests/protocol_conformance/` (TODO: not yet written).

A Python MCP server implementation is on the roadmap — see
[CONTRIBUTING.md](CONTRIBUTING.md) under "What we welcome."

## What's in this repo

```
├── README.md                # this file
├── LICENSE                  # Apache 2.0
├── NOTICE                   # attribution
├── CHANGELOG.md             # release history
├── CONTRIBUTING.md          # how to contribute, DCO requirement
├── recommended-models.json  # what model the C2G app should nudge users toward
├── protocol/
│   └── SPEC.md              # the file-based protocol, the asset
├── skill/                   # the Cowork skill that does the routing
│   ├── SKILL.md             # the routing orchestrator
│   ├── VERSION              # versioned skill releases (Mac app reads this)
│   ├── manifest.json        # update channel manifest
│   └── models/              # per-model tuning files
│       ├── granite4.1.md       # the primary tuning file
│       ├── granite-code.md     # legacy
│       ├── _generic.md         # fallback
│       ├── _template.md        # for adding new models
│       └── model_families.json # prompt-wrapping + Ollama options, single source of truth
├── start_local_ai.sh        # the bash watcher (reference server)
├── Cloud2Ground/            # the Mac app sources (Xcode project)
├── docs/
│   └── faq.md               # privacy, troubleshooting, the economics
└── scripts/
    └── build-dmg.sh         # release packaging
```

## Privacy by default

The C2G Mac app makes **zero** outbound network calls unless you
explicitly enable an opt-in channel in **Settings → Privacy**. By
default:

- Anonymous usage telemetry: **off**
- Feedback / crash reports: **off**
- Skill update channel: **Stable** (fetches a manifest JSON once per
  24h; carries no user data)

The local delegation log (`~/.c2g/delegation_log.jsonl`) is on by
default because the project's token-reduction claims depend on having
this data — but the log stays on your machine.

**Cloud2GroundAI itself makes no calls to the Anthropic API.**
The only AI integration with Anthropic is whatever your existing
Claude installation already does on your behalf. C2G is invisible to
Anthropic at the network level.

See [`docs/faq.md`](docs/faq.md) for the full data-handling description.

## License

Apache License 2.0. See [`LICENSE`](LICENSE) and [`NOTICE`](NOTICE).

## Trademarks

"Cloud2GroundAI" and the leaf logo are unregistered trademarks of
Carlano Technology Solutions LLC. See [NOTICE](NOTICE) for third-party
trademark attribution.

## Status

This is a **free public preview** — the app you download is **v1.3**.
The DMG is code-signed with a Developer ID Application certificate and
notarized by Apple, so it opens cleanly with no Gatekeeper warnings.
The full stack (install → skill → bridge → local model → response) has
been verified end-to-end on real hardware and on a clean macOS install.

**Known issue (fixed in v1.4):** on a slow or memory-constrained Mac,
if you re-run the wizard's "Test the bridge" step while a previous
attempt is still finishing, it can report a "stale or mismatched
response." Re-running it once more clears it. The underlying cause is
purely inference speed on underpowered machines; on a Mac that meets
the 16 GB requirement the test passes in seconds.

The preview is free while we gather feedback — please send yours to
**carlanotech@pm.me**.

## Reporting issues

- **Bugs:** open an [issue](https://github.com/carlanotech/Cloud2GroundAI/issues).
- **Security:** email carlanotech@pm.me. Do not open a public issue
  for security-sensitive reports.
- **Design discussions:** start a [discussion](https://github.com/carlanotech/Cloud2GroundAI/discussions).

## Acknowledgements

- **IBM** for publishing Granite under Apache 2.0
- **Ollama** for making local model serving boring and reliable
- **Anthropic** for Claude and for taking the harness-vs-skill
  distinction seriously
