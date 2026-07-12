# Cloud2GroundAI v1.3

**Free public preview** — the first signed, notarized release.

Cloud2GroundAI is a small Mac menu-bar app that sets up a private, local AI (IBM Granite, via Ollama) on your own Mac and connects it to Claude. When you work in Claude, it quietly hands the mechanical, repetitive parts of a task to the model on your machine instead of the cloud — so you use fewer cloud tokens for the same work, and your files never leave your Mac.

## Requirements

- Apple Silicon Mac (M1 or newer), macOS 14 (Sonoma) or later
- **At least 16 GB of memory** — this matters; the local model needs room to run, and on less than 16 GB it will be too slow to be useful
- ~6 GB of free disk space for the model
- Your own Claude account/subscription (this app connects Claude to the local model — it doesn't include Claude)

## Install

1. Download `Cloud_to_Ground_AI_v1.3.dmg` below, open it, and drag the app into Applications.
2. Launch it and click **Setup…** from the menu-bar icon. The wizard installs Ollama, pulls the model, installs the skill, and wires up the bridge.
3. Connect the `~/claude_bridge` folder to Claude Cowork (one time), and you're set.

A full **User Guide (PDF)** with screenshots is attached below.

## Downloads

- `Cloud_to_Ground_AI_v1.3.dmg` — the app (signed + notarized)
- `Cloud_to_Ground_AI_v1.3.dmg.sha256` — checksum to verify your download
- `Cloud2Ground-AI-User-Guide.pdf` — step-by-step setup guide

## Known issue (fixed in v1.4)

On a slow or memory-constrained Mac, if you re-run the setup wizard's **"Test the bridge"** step while a previous attempt is still finishing, it may report a *"stale or mismatched response."* Running it once more clears it. This is purely a symptom of inference speed on underpowered machines — on a Mac that meets the 16 GB requirement, the test passes in a few seconds. A fix that makes the test ignore leftover responses is queued for v1.4.

## Privacy

Cloud2GroundAI makes no calls to the Anthropic API and uploads none of your content. The local model runs entirely on your own hardware. Any telemetry or feedback channel is opt-in and off by default.

## Feedback

This preview is free while we gather feedback — please send yours to **carlanotech@pm.me**. Thanks for trying it.
