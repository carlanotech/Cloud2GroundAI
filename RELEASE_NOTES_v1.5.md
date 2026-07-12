# Cloud2GroundAI v1.5

**Free public preview** — signed and notarized.

Cloud2GroundAI is a small Mac menu-bar app that sets up a private, local AI (IBM Granite, via Ollama) on your own Mac and connects it to Claude. When you work in Claude, it quietly hands the mechanical, repetitive parts of a task to the model on your machine instead of the cloud — so you use fewer cloud tokens for the same work, and your files never leave your Mac.

## What's new in v1.5

- **Fixed: the bridge no longer goes silent after one task.** Earlier builds could answer a single delegation and then quietly ignore every request after it if a response was never acknowledged. The bridge now self-heals and recovers on the next request instead of wedging.
- **A tougher setup test.** "Test the bridge" now runs two requests back-to-back, so any one-shot failure is caught during setup rather than showing up later. This also clears the v1.3 "stale or mismatched response" symptom for good.
- **Cleaner, consistent naming** throughout the app, with an automatic one-time cleanup of the old background helper when you upgrade.

## Requirements

- Apple Silicon Mac (M1 or newer), macOS 14 (Sonoma) or later
- **At least 16 GB of memory** — this matters; the local model needs room to run, and on less than 16 GB it will be too slow to be useful
- ~6 GB of free disk space for the model
- Your own Claude account/subscription (this app connects Claude to the local model — it doesn't include Claude)

## Install

1. Download `Cloud2GroundAI_v1.5.dmg` below, open it, and drag the app into Applications.
2. Launch it and click **Setup…** from the menu-bar icon. The wizard installs Ollama, pulls the model, installs the skill, and wires up the bridge.
3. Connect the `~/claude_bridge` folder to Claude Cowork (one time), and you're set.

A full **User Guide (PDF)** with screenshots is attached below.

## Downloads

- `Cloud2GroundAI_v1.5.dmg` — the app (signed + notarized)
- `Cloud2GroundAI_v1.5.dmg.sha256` — checksum to verify your download
- `Cloud2GroundAI-User-Guide.pdf` — step-by-step setup guide

## Privacy

Cloud2GroundAI makes no calls to the Anthropic API and uploads none of your content. The local model runs entirely on your own hardware. Any telemetry or feedback channel is opt-in and off by default.

## Feedback

This preview is free while we gather feedback — please send yours to **carlanotech@pm.me**. Thanks for trying it.
