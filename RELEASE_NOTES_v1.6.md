# Cloud2GroundAI v1.6

**Free public preview** — signed and notarized.

Cloud2GroundAI is a small Mac menu-bar app that sets up a private, local AI (IBM Granite, via Ollama) on your own Mac and connects it to Claude. When you work in Claude, it quietly hands the mechanical, repetitive parts of a task to the model on your machine instead of the cloud — so you use fewer cloud tokens for the same work, and your files never leave your Mac.

## What's new in v1.6

- **The bridge can't quietly wedge anymore.** Delegation now runs through a single shipped helper instead of hand-written steps, and the "I got your answer" acknowledgement is built into the one path that hands back a result — so it can't be skipped. This closes the "answers once, then goes silent" problem at the source rather than recovering from it after the fact.
- **You can now see whether the local AI is actually alive.** The background watcher publishes a small heartbeat, so the app (and Claude) can tell *running*, *busy*, and *stopped* apart at a glance — states that used to look identical. It also reports which model is loaded instead of guessing.
- **Faster, more reliable hand-offs inside Claude.** Response waiting is chunked so it never trips the sandbox's time limit, and Claude is nudged to quickly sanity-check any code the local model returns before using it.

## Requirements

- Apple Silicon Mac (M1 or newer), macOS 14 (Sonoma) or later
- **At least 16 GB of memory** — this matters; the local model needs room to run, and on less than 16 GB it will be too slow to be useful
- ~6 GB of free disk space for the model
- Your own Claude account/subscription (this app connects Claude to the local model — it doesn't include Claude)

## Install

1. Download `Cloud2GroundAI_v1.6.dmg` below, open it, and drag the app into Applications.
2. Launch it and click **Setup…** from the menu-bar icon. The wizard installs Ollama, pulls the model, installs the skill, and wires up the bridge.
3. Connect the `~/claude_bridge` folder to Claude Cowork (one time), and you're set.

A full **User Guide (PDF)** with screenshots is attached below.

## Downloads

- `Cloud2GroundAI_v1.6.dmg` — the app (signed + notarized)
- `Cloud2GroundAI_v1.6.dmg.sha256` — checksum to verify your download
- `Cloud2GroundAI-User-Guide.pdf` — step-by-step setup guide

## Privacy

Cloud2GroundAI makes no calls to the Anthropic API and uploads none of your content. The local model runs entirely on your own hardware. Any telemetry or feedback channel is opt-in and off by default.

## Feedback

This preview is free while we gather feedback — please send yours to **carlanotech@pm.me**. Thanks for trying it.
