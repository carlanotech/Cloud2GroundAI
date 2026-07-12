# Cloud2GroundAI — FAQ

## About the product

### What does Cloud2GroundAI actually do?

Three things on your Mac, all local:

1. **It installs and manages a local AI bridge.** A small bash watcher
   (or its alternatives) reads request files from a folder and runs
   inference against a local IBM Granite model via Ollama, then writes
   the response back to a file. This is the bridge.
2. **It installs a skill into Cowork.** Anthropic's Claude clients
   discover skills under `~/.claude/skills/`. The bundled
   `ollama-delegate` skill teaches Claude to delegate mechanical
   subtasks (helper functions, one-liners, docstring batches) to the
   local model via the bridge instead of doing them in the cloud.
3. **It gives you a Ground-mode chat window.** When your internet is
   down, you can open a chat with the locally-installed Granite model
   directly from the menu bar icon. No Claude, no cloud, just Granite.

### Why does it exist?

Two reasons. **First**, the Anthropic harness ban announced in February
2026 makes it risky to route cloud-Claude conversations through any
intermediate "harness." C2G doesn't do that. It is the inverse: a
local-AI server that the *user's own* Claude Desktop / Cowork / Code
client decides whether to delegate to, on a task-by-task basis. The
user remains a paying Claude customer; nothing flows through a third
party. The legal positioning document the project ships with explains
this in detail.

**Second**, the "ground" framing. The user pays for cloud Claude. They
don't want to pay for cloud Claude to write boilerplate docstrings.
Routing the boilerplate to local Granite reduces cloud token spend.
On a solar-powered Mac, it also means the boilerplate work runs off
the sun.

### Does C2G replace Claude Desktop?

No. C2G runs alongside your existing Claude installation. Most of the
time you keep using Claude exactly as before; C2G's value is invisible
(Claude silently delegates some tasks to local Granite). The Ground
chat window is the only user-facing surface that competes with Claude,
and only when you're offline.

### Do I need an Anthropic API key?

No. C2G makes **zero** calls to the Anthropic API. The only AI
integration with Anthropic is whatever your Claude Desktop / Cowork /
Code installation already does on your behalf — that account, those
tokens, that billing relationship. C2G is invisible to Anthropic at the
network level.

### What runs locally vs in the cloud?

| Component | Where it runs |
|---|---|
| The C2G Mac app itself | Locally, no network calls |
| The bash watcher | Locally |
| Ollama | Locally |
| IBM Granite 4.1 (8B or 30B) | Locally |
| Your prompts to local Granite | Locally only |
| Claude Desktop / Cowork / Code | Wherever your Claude account routes them |
| Your prompts to Claude | Through Anthropic, exactly as without C2G |

---

## Privacy and data handling

### Does C2G send my prompts anywhere?

No. The skill instructs Claude to write request files into a folder on
your Mac. The watcher reads them, runs the model locally, writes the
response back. No prompts, completions, file contents, or conversation
history leave your machine.

### Does C2G have telemetry?

Two opt-in channels exist, both **off by default**:

- **Anonymous usage telemetry** — a daily summary of model usage counts,
  no prompts or responses or paths. Helps the project prioritize
  tuning. Off by default.
- **Feedback and crash reports** — only the contents of crashes and
  any feedback you explicitly submit through the menu. Off by default.

There is also a **local-only delegation log** at
`~/.c2g/delegation_log.jsonl` that records per-delegation metadata
(timestamp, task class, token counts, outcome) for measurement. This
file never leaves your machine. It is on by default because the
project's token-reduction claims depend on having this data. You can
turn it off in Settings → Privacy.

### How can I verify nothing's leaving the machine?

Two ways:

- **Inspection**: open the Mac app's Status Panel. Every component the
  app manages (Ollama, model, bridge watcher, installed skill) is
  listed with its state. Toggle every opt-in channel off and observe
  the absence of network traffic.
- **Audit**: read the source code in this repo. The watcher (`start_local_ai.sh`)
  is one bash file. The skill (`skill/`) is markdown. The Mac app is
  Swift, ~25 files, all in this repo at the matching version tag. There
  are no obfuscated binaries.

### What about the skill update channel?

The skill update channel **defaults to "Stable" and will check once per
24 hours**. It fetches a JSON manifest from a Carlano-hosted endpoint;
no user data is sent in the request. You can switch it to "Disabled"
in Settings → Updates if you prefer to update manually.

The manifest endpoint URL is hardcoded into the app. It will be
something like:

```
https://carlano.com/c2g/skill/stable/manifest.json
```

(The exact URL is wired in at release time and listed in the release notes.)

---

## Installation and setup

### What do I need to run C2G?

- macOS 14 (Sonoma) or later, Apple Silicon recommended.
- At least 16 GB RAM for granite4.1:8b. 32 GB recommended for :30b.
- About 6 GB free disk for the 8b model, ~18 GB for 30b.
- Claude Desktop, Cowork, or Claude Code installed.

### Do I need an Apple Developer account?

No, that's only the project owner's concern (for code-signing the
binary). End users install the notarized DMG like any other Mac app.

### Why does the Setup Wizard ask to install Ollama?

Because C2G uses Ollama as the local model runtime. The wizard can
install it via Homebrew for you, or link you to the official Ollama
download page. After install, the wizard pulls the Granite model and
registers the bridge watcher as a LaunchAgent so it starts on login.

### Why is the bridge folder in ~/Documents instead of somewhere hidden?

Two reasons:

1. **macOS TCC (Transparency, Consent, and Control)**: the watcher
   needs to read and write files in this folder. Documents is one of
   the few locations where both the user-installed Ollama runtime and
   Anthropic's Cowork client can read/write without per-file consent
   prompts.
2. **Discoverability**: if something goes wrong, the user can navigate
   to `~/Documents/claude_bridge/_bridge/` in Finder and see exactly
   what request and response files look like. Transparency is a
   feature.

The watcher script itself lives at `~/Library/Application Support/claude_bridge/`
because launchd-spawned bash can't always write to `~/Documents/` without
prior interactive consent, but it CAN read from there. The split is
load-bearing.

---

## Using C2G

### What kinds of tasks get delegated to local Granite?

By default: short, mechanical, well-specified ones. The orchestrator
file (`skill/SKILL.md`) has the full routing table. Roughly:

**Delegated to local Granite:**

- Helper functions from a clear spec
- Docstrings on pasted code
- One-liner bash/Python/awk/jq
- Template fill from one or two example rows
- Unit test stubs from a function signature
- Short regex or config snippets

**Kept in cloud Claude:**

- Prose with technical accuracy requirements
- Refactors with vague goals
- Debugging non-obvious errors
- Algorithm or architecture design
- Cross-file or multi-step work
- Anything where the prompt would be >100 words

The split is empirical and gets refined as observed task outcomes are
logged.

### Will local output have bugs?

Yes, sometimes. Granite isn't Claude. The economic argument is in
`skill/SKILL.md` — reviewing code is much cheaper than writing it
from scratch, so even local output that needs cloud-side patches is
typically a net token savings. The case study at
`CASE_STUDY_gethostname.md` walks through one such bug-and-patch
exchange in detail.

### How do I know which tasks Claude delegated?

When Claude uses the local skill, it adds a small inline note like
`(handled locally via granite4.1)` to the response. The Settings →
Privacy panel lets you turn on the local delegation log if you want
a full record.

### Can I change the local model?

Yes, to any model Ollama can run. Settings → Behavior has a free-text
model field with `granite4.1:8b` (default, balanced) and
`granite4.1:30b` (higher quality, more RAM) offered as one-click
suggestions — but typing in any other Ollama tag works too; the
installer and detection logic don't require a Granite-family name. The
change takes effect on the next watcher restart (the LaunchAgent
auto-restarts on logout/login, or you can quit and relaunch C2G).

An untuned model still works — it just runs with neutral, generic
generation settings (`skill/models/model_families.json`'s fallback
entry) instead of settings tuned for that specific model. Writing a
tuning file in `skill/models/<name>.md` and adding a `model_families.json`
entry gets you the tuned behavior. See the contributing guide.

---

## Troubleshooting

### The menu bar icon doesn't appear.

Three things to try, in order:

1. **Move your cursor to the top of the screen.** If you're using a
   full-screen app, macOS hides the menu bar until cursor-near-top.
2. **Hold Command and drag a menu bar icon sideways.** macOS hides
   overflow items behind the notch on newer Macs. The C2G leaf icon
   may be hidden there.
3. **Restart the Mac.** Especially after a fresh install or upgrade,
   macOS Launch Services sometimes takes a reboot to fully recognize
   a new menu bar app.

### The Status panel says "Ollama: Not installed" but I installed it.

Check Settings → Behavior, then click the Refresh button in the Status
Panel. If still missing, open Terminal and run `which ollama`. If it
returns `/opt/homebrew/bin/ollama`, you're on a known-good path. If
nothing, Ollama isn't in your shell PATH and may have been installed
to a non-default location; reinstall via the C2G Setup Wizard.

### The Status panel says "Watcher: Stopped" but the LaunchAgent is registered.

Open Terminal and run:

```bash
launchctl print gui/$(id -u)/com.cloudtoground.watcher 2>&1 | head -20
```

If `state = running`, the watcher is up and the probe is reading
incorrectly. Refresh the Status Panel.

If `state = not loaded`, the LaunchAgent isn't actually registered.
Re-run the Setup Wizard's "Register LaunchAgent" step.

### Claude isn't delegating to local Granite.

Three things to check:

1. **Is the skill installed?** Check `~/.claude/skills/ollama-delegate/`
   exists and contains `SKILL.md`.
2. **Is the bridge folder set up?** Check `~/Documents/claude_bridge/_bridge/`
   exists.
3. **Is Claude using a version that supports skills?** Claude Desktop
   ≥ a certain version, Cowork, and Claude Code all do. The Anthropic
   web client does not.

You can verify the skill is active by asking Claude to write a simple
helper function and watching for a `(handled locally via granite4.1)`
note in the response.

### The bridge sometimes returns "ERROR: ..." responses.

This means Ollama failed the inference. Common causes:

- **Out of memory** — the 30b tier needs ~17 GB of RAM. If your Mac is
  under memory pressure, the model can't run. Switch to 8b in Settings.
- **Model not pulled** — `ollama list` should show your chosen model.
  If absent, re-run the Setup Wizard's "Pull model" step.
- **Context length** — prompts above ~30000 characters can overflow
  the model's context window. Trim the prompt or break into multiple
  delegations.

---

## Compliance and procurement

### What's the data jurisdiction story?

Cloud2GroundAI itself, the skill, and the watcher are developed by
Carlano Technology Solutions LLC, a US-headquartered company. The
bundled local model (IBM Granite 4.1) is published by IBM, also
US-headquartered. The runtime (Ollama) is published by Ollama Inc.,
also US-headquartered. There is no Chinese-, Russian-, or other
non-Western-headquartered code in the stack as shipped.

This is relevant for ITAR / CMMC / FedRAMP procurement decisions
where vendor provenance matters.

### Is there a SOC 2 or ISO 27001 report?

Not for the OSS preview. v2.0 (paid tier) will pursue formal
compliance attestations as the customer base demands it.

### Can I run this in an air-gapped environment?

In principle yes — after first install, no component reaches outbound
except the optional skill update channel (which you can disable).
First-install does require network access for Homebrew + Ollama + the
model pull.

For true air-gap, you'd need to pre-stage the Granite model file and
the Ollama binary on the target machine. Not a documented workflow
yet; open an issue if you need it.

### What about export control?

The source code (skill, watcher, app) is published under Apache 2.0
with no encryption export-controlled functionality. The IBM Granite
model is also openly published (Apache 2.0). No EAR / ITAR controls
apply at the cloud-to-ground layer. Local cryptographic operations are
limited to TLS for the optional skill update channel and SHA-256
integrity verification on downloaded payloads — standard macOS system
libraries.

---

## The economics

### Why is local-with-bugs still a savings if Claude has to fix the bugs?

Because reviewing code is much cheaper than writing it from scratch.
The full table is in `skill/SKILL.md`:

| Outcome | Cloud tokens spent |
|---|---|
| Cloud writes whole function from scratch | 1.0× (baseline) |
| Local writes it, cloud reviews and ships verbatim | ~0.1× |
| Local writes it, cloud spots a bug and patches | ~0.3× |
| Local writes it, cloud throws it out and rewrites | ~1.1× |

Three of four outcomes save. Only "complete rewrite" loses, and the
loss is small. As long as local output is right *or partially right*
most of the time, delegation is a net win.

### How much do I actually save?

Depends on workload mix. The product goal (PRD-002) is a 50%
cloud-token reduction on a representative workload, with a 20% margin
(so the engineering CBE needs to hit 60% to claim 50%). Real-user
measurements will be reported in CHANGELOG entries as the data
accumulates.

### Why is this open source if it's a product?

The skill, watcher, and core protocol are the IP that makes the
delegation work. We give them away because (a) the value is the
*continuous tuning* as Claude and local models evolve, which is what
the v2.0 paid tier offers, and (b) the auditability is core to the
trust posture for ITAR/CMMC procurement. A binary blob that "phones
home" would not be acceptable to those buyers; an Apache-2.0 repo is.

The paid tier (v2.0) sells:
- Curated update channels with tested-on-real-workloads tuning files
- Multiple local model "slots" beyond the free single core
- Email support
- Team licensing

The free tier (this repo, v1.x) is always usable, forever. The paid
tier is the convenience layer.

---

## Project status and roadmap

### What's the release status?

As of this writing: **v0.2.x is internally complete** — the Mac app
runs end-to-end on the maintainer's machine. **v0.1.0 public release**
is gated on (a) Apple Developer Program enrollment (in progress),
(b) Anthropic legal positioning letter acknowledgement (sent),
(c) DMG packaging and notarization, (d) Phase 1 documentation
(this file is part of it).

### Where does it go from here?

`C2G_Development_Roadmap.md` (internal — not in the public repo) and
the architecture sketch outline the path. Headline items:

- **v0.1.0** — public preview release. Single core, free, OSS.
- **v0.2.x** — quality-of-life, including multi-tier model picker.
- **v1.0** — first stable, with hardened LaunchAgent and full
  observability.
- **v2.0** — paid tier with curated update channels and multi-core
  delegation. Mac App Store evaluated for distribution at this point.

The public roadmap will live at `ROADMAP.md` once the public repo is
flipped on.
