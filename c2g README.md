<!--
Copyright 2026 Carlano LLC
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0
-->

# <!-- TODO: name -->

> A file-based protocol that lets a cloud AI assistant hand mechanical work off to a small model running on your own machine.

[![CI](https://img.shields.io/badge/CI-pending-lightgrey)](.github/workflows/ci.yml)
[![License: Apache 2.0](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-0.1.0--draft-orange)](CHANGELOG.md)

---

## Why this exists

This started in a solar-powered home, on an M-series MacBook Air, with a single observation: most of what a cloud AI assistant does in a coding session is *mechanical* — write a helper function from a clear spec, add docstrings to a pasted block, transform a CSV into JSON, fill out a template from a one-row example. The senior-engineer work — design, judgment, debugging the weird stuff, reasoning across files — is the small fraction. Everything else is execution.

The execution doesn't need to go to a datacenter. A small coding-tuned model running locally on a laptop can do it. Every task that stays on the laptop is datacenter water and power and tokens that nobody had to spend, and a little bit of inference that ran off the sun.

This project is the contract that makes that handoff work. The cloud model stays in charge of judgment. A small local model handles the mechanical bits. They talk through a shared folder, or through a tool call when the cloud client supports MCP.

The defaults are deliberately US-anchored — **IBM Granite Code** as the primary model, **Microsoft Phi** for the lightweight tier — so the project is a clean fit for developers working under government contracts or other regulated frameworks where a software-inventory review needs to come back boring. Other strong non-Western models are documented as alternatives; they're not what new users get pointed at.

## What this is (30 seconds)

A cloud AI assistant (Claude, in the reference setup) decides a subtask is mechanical and well-defined. It writes the prompt to `request.txt` in a shared folder. A tiny watcher on your machine notices the file, calls your local model, writes the answer to `response.txt`, and cleans up. The cloud assistant reads the answer back and uses it. The whole round-trip is local — no tunnels, no accounts, no cloud inference on the delegated step.

A concrete example. You ask the cloud assistant to add a helper function that converts seconds to a human-readable duration string. Instead of generating it in the cloud, the assistant writes a 40-word prompt to `request.txt`, the local watcher hands it to a coding model, and 6 seconds later the function comes back in `response.txt`. The cloud assistant reviews it, drops it into your code, and notes *(handled locally)*. You saved a cloud round-trip on a task the local model handles cleanly.

## Quickstart (Claude on Apple Silicon)

This project targets developers using Claude on Apple Silicon Macs with
heavily-renewable home power. If that's you, the recommended setup
takes about two minutes.

```bash
# 1. Install Ollama and pull a small coding model
brew install ollama
ollama serve &                       # leave it running
ollama pull granite-code:8b

# 2. Install the MCP server
brew install pipx
pipx install local-delegate

# 3. Register the server with Claude (one MCP config entry)
#    See server/python-mcp/README.md for the exact JSON.

# 4. Install the routing skill so Claude knows when to use the tool
#    See skill/README.md for the install command.
```

Done. Open Claude and work normally. Short mechanical subtasks will
quietly route to your machine.

There are two implementations of the protocol in this repository. Use
the MCP server unless you have a reason not to:

- **`server/python-mcp/`** — recommended for Claude Code, Cowork, and
  Claude Desktop. No daemon, no shared folder, no autostart. Claude
  spawns the server on demand.
- **`watcher/bash-ollama/`** — file-based bridge. Useful for
  hand-debugging the model layer or as a fallback if you're on a client
  that doesn't speak MCP.

Both implementations are equivalent in capability and both share the
routing skill in `skill/SKILL.md`.

## The protocol stays the point

The MCP server is the recommended setup for Claude, but the asset is
[`protocol/SPEC.md`](protocol/SPEC.md) — a small contract for
handing a single mechanical subtask from a cloud assistant to a local
model. The MCP server implements the contract over stdio; the bash
watcher implements it over a shared folder. Both are interchangeable
from the routing skill's point of view.

Contributions of additional implementations are welcome:

- An MCP server in Go for a single-binary notarized release.
- A watcher for LM Studio's OpenAI-compatible server.
- A watcher for MLX (Apple Silicon native), llamafile, llama.cpp
  server, vLLM, or TGI.
- A Linux systemd unit for the bash watcher.
- A Windows port.

See [`CONTRIBUTING.md`](CONTRIBUTING.md) for the bar.

## What makes this different

Local-AI-routing tools exist (see "Prior art" below). Three things
differentiate this one and explain why it's worth your install.

**The skill is the product, not the plumbing.** Most tools in this
category give you a tool — `call_local_model(prompt)` — and leave the
question of *when* to use it to the cloud assistant's improvisation.
Cloud2GroundAI ships with an opinionated routing policy: a
decision table covering thirteen task categories, two hard tests that
gate every delegation (prompt length, verbatim usability), prompt
patterns calibrated for smaller models (prefer pattern completion over
full specification), and explicit rules for what to do when the bridge
is missing. The skill is the IP. The MCP server and bash watcher are
reference implementations of one half of the protocol; the skill is
the other half, and the one that's hardest to get right. Without it,
"delegate to local" devolves into a coin flip; with it, Claude makes
the same decision every time on the same kind of task. That's what
makes the experience feel like routing, not just access.

**US-anchored, regulated-industry friendly by default.** The defaults
are IBM Granite Code and Microsoft Phi. Other models work and are
documented as alternatives, but the project doesn't point new users at
Chinese-origin models. For a developer working under a government
contract, a CMMC-controlled program, an ITAR-restricted codebase, or
any other framework where the answer to "what foreign-origin software
is on this machine?" needs to be short, this is the only
local-AI-routing tool that ships with that posture out of the box. The
competing tools default to whatever is cheapest or fastest, which is
the wrong default for an entire category of buyer. (See
[`docs/faq.md`](docs/faq.md) for the audit-trail logic in detail.)

**A polished consumer experience, not just a developer toolkit.** The
v0.1 ships as an open-source repository for developers comfortable
with `pipx install` and JSON config files. The v1.0 — a notarized
macOS menu-bar app from Carlano LLC — is the version this project is
ultimately for. One-click install, automatic Ollama lifecycle
management, status badge in the menu bar, signed and notarized,
auto-update, zero terminal needed. The OSS is the foundation and
proves the design works; the paid app is the form factor most users
actually want. Same protocol, same skill, same defaults — different
amount of polish.

## What this is good for (and what it isn't)

The cloud assistant decides what to delegate using the routing rules in [`skill/SKILL.md`](skill/SKILL.md). The short version:

| Task type | Route | Why |
|---|---|---|
| Helper function from a clear spec | **Local** | Short prompt, pattern output |
| Docstrings on a pasted code block | **Local** | Paste is the prompt, output is additive |
| One-liner (bash, Python, awk, jq) | **Local** | Tiny prompt, directly usable |
| Template fill from a 1–2 row example | **Local** | Pattern completion, minimal prompt |
| Unit test stubs from a function signature | **Local** | Mechanical, no accuracy risk |
| Reformat / transform structured data | **Local** | Structure is the prompt, output is mechanical |
| Short regex or config snippet | **Local** | Well-defined, verifiable |
| Prose that requires technical accuracy | **Cloud** | Rework cost negates savings |
| Refactor with a vague goal | **Cloud** | Requires judgment |
| Debug a non-obvious error | **Cloud** | Requires reasoning |
| Algorithm or architecture design | **Cloud** | Requires domain knowledge |
| Cross-file or multi-step work | **Cloud** | Local model has no conversation context |
| Domain-specific reasoning | **Cloud** | Accuracy critical |
| Prompt would be >100 words | **Cloud** | Break-even exceeded |

Two hard tests gate delegation: the prompt has to be under roughly 100 words, and the output has to be usable verbatim. Anything that fails either test stays in the cloud.

## Keeping the local model current

When a newer small coding model lands — a Granite Code v2, a Phi-5,
or whatever comes next — the project publishes the new recommendation in
[`recommended-models.json`](recommended-models.json). The MCP server
fetches that file periodically, compares it against your installed
models, and surfaces a single nudge in Claude's next `status()` call.
Pull the new model with one command:

```bash
local-delegate update
```

This is the same UX you already accept for your Claude desktop app
update prompt — a notice when there's something new, an explicit
action to upgrade. The server intentionally does NOT pull new models
automatically; multi-gigabyte downloads should always be a user choice.

## Prior art and related projects

This project isn't first in the "delegate to a local model from a cloud
assistant" category. Other people have shipped tools in this space and
some of them are excellent. If the framing here doesn't fit, look at
these:

- **[houtini-lm](https://github.com/houtini-ai/houtini-lm)** — an MCP
  server that delegates Claude Code tasks to local or cloud LLMs.
  Supports LM Studio, Ollama, vLLM, DeepSeek, Groq, and Cerebras. More
  mature engineering than this project on the runtime side: per-model
  performance tracking, pre-flight token estimation, a `code_task_files`
  feature that lets the local model read source from disk without
  burning Claude's context. If you want broad runtime support and
  don't care about US-anchored defaults or the values story, use
  houtini-lm.
- **[Hybrid Claw](https://github.com/ChetanTekur/hybrid-claw)** — a
  router-proxy approach that switches OpenClaw between local Ollama
  and Claude Sonnet. Different architecture (sits in front of the
  cloud assistant rather than beside it) but similar outcome.
- **Ollama + Claude Code via the Anthropic Messages API** — a
  growing pattern where Claude Code is pointed at a local Ollama
  endpoint and the cloud is bypassed entirely. A more aggressive
  position than what this project takes (we want the cloud assistant
  in the loop for everything except the mechanical bits). Search for
  "Claude Code Ollama" tutorials; the pattern is well-documented.

Where this project differs: the routing skill as IP (most competitors
are pure plumbing), US-anchored defaults for regulated industries, and
the eventual paid Mac app from Carlano LLC for users who want the
polished experience instead of the developer setup. If those three
things don't matter to you, one of the projects above is probably a
better fit, and that's fine. The category is healthier with more than
one tool in it.

## Project status

`v0.1.0-draft`. Both the MCP server and the bash watcher work on macOS
with Ollama. The protocol is stable in shape but may pick up small
revisions before `v0.1.0` proper. Issues and PRs welcome.

## License

Apache License 2.0. See [`LICENSE`](LICENSE) and [`NOTICE`](NOTICE).

Contributions require a Developer Certificate of Origin sign-off. See [`CONTRIBUTING.md`](CONTRIBUTING.md).

## Naming

The project name isn't picked yet. Candidates and rationale are in [`NAMING.md`](NAMING.md) — feedback welcome before `v0.1.0` ships.
