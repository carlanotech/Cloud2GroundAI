---
name: ollama-delegate
version: 0.4.0
description: >
  Standing operating procedure for routing mechanical subtasks from a cloud
  AI assistant to a local model via the file-based bridge protocol. Use this
  skill whenever you are about to generate code, transform a file, write a
  script, or do any well-defined mechanical task — even if the user did not
  explicitly ask for local delegation. Read the active model's tuning file
  in models/ before composing prompts; the orchestrator (this file) is
  model-agnostic.
---

# Local AI Delegation — Standing Operating Procedure

## What this file is

This is the **orchestrator**. It defines:
- When to delegate vs. when to handle a task in the cloud
- The lifecycle of a delegation through the file-based bridge protocol
- How to decide which `models/<name>.md` tuning file to follow

This file is **model-agnostic**. Every model-specific rule lives in
`models/<model-name>.md`. If you find yourself adding a rule here that
mentions a specific model by name, you are doing it wrong — move it
to the model's tuning file instead.

## The protocol is a shipped helper, not inline bash you retype (v0.4.0)

`bridge_delegate` (shipped alongside this file) is the **only** supported way
to drive the bridge. Do **not** hand-roll `request.txt` / `response.txt` /
`consumed.txt` handling from memory — that is exactly how the acknowledgement
step gets silently dropped, which wedges the watcher for every later request
and looks identical to a dead watcher (the multi-session hangs of 2026-07-11
and 2026-07-13). The helper makes the ack **unskippable by construction**: a
response body is emitted in exactly one place, and that same code path writes
`consumed.txt` before it returns. If you call the helper, you cannot skip the
ack; if you retype the loop, you can. Call the helper.

Locate it (it sits next to this SKILL.md):

```bash
BD=""
for d in /sessions/*/mnt/.claude/skills/ollama-delegate \
         "$HOME"/.claude/skills/ollama-delegate \
         /var/folders/*/T/claude-hostloop-plugins/*/skills/ollama-delegate; do
    [ -f "$d/bridge_delegate" ] && { BD="$d/bridge_delegate"; break; }
done
# Fallback: the skill loader prints "Base directory for this skill: <path>" —
# use "<that path>/bridge_delegate" if the glob above found nothing.
```

Run everything as `bash "$BD" <subcommand>`. Subcommands:
`status`, `send` (prompt on stdin → prints `REQ_ID`), `poll <REQ_ID>`
(one bounded chunk), and `run` (send + one poll chunk).

## Why this exists

The cloud assistant is the senior engineer. Local models are the assistants.
Routing mechanical, well-defined subtasks to a local model saves cloud
tokens and datacenter inference, and on a solar-powered Mac means the
work runs off the sun. The protocol is described in `protocol/SPEC.md`.

### The economic argument (and why imperfect local output is still a win)

A common skeptic objection: *"If the local model makes mistakes, the
cloud assistant still has to step in — so what did you actually save?"*

The answer is the cost asymmetry between writing and reviewing. Writing
new code is expensive: the cloud model has to generate every token,
reason about structure, choose names, lay out logic. Reviewing existing
code is cheap: the cloud model reads, spots issues, and edits surgically.

Empirically, reviewing-and-correcting costs roughly **one quarter** of
writing-from-scratch in tokens consumed. So the math on a delegation
where the local model gets it *partly* wrong still favours delegation:

| Approach | Cloud tokens spent |
|---|---|
| Cloud writes the whole function from scratch | 1.0× (baseline) |
| Local writes it, cloud reviews and ships verbatim | ~0.1× |
| Local writes it, cloud spots one bug and patches it | ~0.3× |
| Local writes it, cloud throws it out and rewrites entirely | ~1.1× |

Three of four outcomes save tokens. Only the worst case (full rewrite)
is a loss, and even then the loss is small. As long as the local model
is right *or partially right* most of the time, every delegation that
isn't an outright disaster is a net win.

This is why the workflow is "delegate, then review" not "decide in
advance whether to delegate." The cloud assistant's review pass is
already part of the senior-engineer role — we are not adding work, we
are *moving* the writing work off the cloud.

A concrete example from the 2026-06-20 session: Granite produced a
`get_lan_ips()` function that was almost correct but used the
macOS-broken `socket.gethostname()` approach. Claude caught the bug,
explained why, and wrote the corrected version. The total cloud cost
of (review + correction) was a fraction of what writing the function
from scratch would have been — even though the local output had a real
bug. The bug didn't break the value proposition. It demonstrated it.

---

## Step 1 — Check if the bridge is active

```bash
bash "$BD" status
```

`status` reads the watcher's heartbeat (`_bridge/status.json`) and prints one
of these, which map directly to what you do next:

| Output | Exit | Meaning | Do |
|---|---|---|---|
| `ALIVE model=<name> …` | 0 | Watcher up and idle | Proceed to Step 2 (the model name is already in hand — see below) |
| `BUSY model=<name> …` | 0 | Watcher up, mid-inference | Wait a few seconds and re-check, or proceed — `send` will queue behind it |
| `DEAD …` | 3 | Heartbeat present but frozen | Watcher process died; ask the user to restart it, handle this task in cloud meanwhile |
| `NO-HEARTBEAT …` | 4 | `status.json` absent | Either a pre-v0.4 watcher (still works — skip to Step 2 and rely on Step 4's `WATCHER-DOWN` check) or the watcher isn't running |
| `NO-BRIDGE …` | 4 | `~/claude_bridge` not connected | See Outcome C below |

`status` is **clock-skew-immune**: it decides ALIVE by sampling the watcher's
`seq` counter twice and checking that it *advanced*, so it works identically
whether bash is running on the host or in a remote Cowork sandbox. This
replaces the old `curl`/`pgrep` liveness probe, which gave false negatives
from the sandbox (no network route to the host's `localhost` or process
table). **Never improvise a PONG/liveness round-trip through the bridge** —
an ad-hoc request you don't ack leaves a `response.txt` that blocks every
later request. `status` is the liveness check; it touches no request state.

**Outcome C — `NO-BRIDGE` (bridge folder not found):** the likely cause is
that `~/claude_bridge` just isn't connected to this session yet — it's a
separate grant from the project folder, and in a sandboxed Cowork session it
must be mounted before the helper can see it.

- **If a folder-request tool is available** (e.g. `request_cowork_directory`
  in Cowork), call it with path `~/claude_bridge` to pop a one-click connect
  prompt, then retry `status`. Prefer this.
- **Only if that isn't available**, ask the user to connect `~/claude_bridge`
  via the folder picker, then retry.

If the bridge genuinely isn't set up (no `~/claude_bridge` at all), the user
hasn't installed the Mac app / run its setup wizard yet — handle the task
yourself, no mention needed.

**History (2026-07-06):** the bridge used to live at `~/Documents/claude_bridge`.
Moved to `~/claude_bridge` (outside Documents) because macOS TCC blocks a
background LaunchAgent's process from ever reading/writing inside
Documents/Desktop/Downloads on a fresh account — confirmed via a clean
Parallels VM test where every bridge file operation failed with
"[Errno 1] Operation not permitted." A plain folder elsewhere under `$HOME`
isn't covered by that protection.

---

## Step 2 — Identify the active local model and load its tuning file

If Step 1 printed `ALIVE`/`BUSY`, the model name is already in that line
(published by the watcher's heartbeat — no more guessing from whichever
tuning file happens to be present). If you need it on a pre-v0.4 watcher
(`NO-HEARTBEAT`), fall back to asking Ollama directly on the host:

```bash
# Only needed when status.json is absent AND bash is on the host (not sandboxed).
# python-free: pull the first "name" field out of /api/tags with grep+sed.
ACTIVE_MODEL=$(curl -sf http://localhost:11434/api/tags 2>/dev/null \
    | grep -o '"name"[[:space:]]*:[[:space:]]*"[^"]*"' \
    | head -n 1 | sed 's/.*:[[:space:]]*"\([^"]*\)"/\1/')
```

Then find the matching tuning file by reading **`models/model_families.json`**
(the single source of truth, also read directly by `start_local_ai.sh` for
prompt wrapping and Ollama options, so it can't drift out of sync with what
the watcher actually does): find the entry in `families` whose
`match_prefixes` contains a case-insensitive prefix of the model name, and
load its `tuning_file`. If nothing matches, use the `default` entry's
`tuning_file` (`models/_generic.md`) and note in the response that the model
is untuned.

Read the tuning file end-to-end before composing any delegation prompt.
Per-model files define output-format conventions, prompt patterns that work
for that model, model-specific failure modes, and any special framing needed
(most framing now happens in the watcher, not the prompt).

---

## Step 3 — Decide whether to delegate

Two universal hard tests (apply to every model):

**Test 1 — Prompt length.** Could you write the prompt in under ~100 words?
If not, you've already done most of the work yourself.

**Test 2 — Verbatim test.** Would you use the output verbatim, or would you
need to edit it for accuracy, tone, or domain correctness?

If either test fails, keep the task in the cloud.

Universal routing rules:

| Task type | Route | Why |
|---|---|---|
| Helper function from a clear spec | **Local** | Short prompt, pattern output |
| Docstrings on a pasted code block | **Local** | Paste = prompt, additive output |
| One-liner (bash, Python, awk, jq) | **Local** | Tiny prompt, directly usable |
| Template fill from 1–2 row example | **Local** | Pattern completion, minimal prompt |
| Unit test stubs from a function signature | **Local** | Mechanical, no accuracy risk |
| Reformat / transform structured data | **Local** | Mechanical, verifiable |
| Short regex or config snippet | **Local** | Well-defined, verifiable |
| Prose with technical accuracy | **Cloud** | Rework cost negates savings |
| Refactor with a vague goal | **Cloud** | Requires judgment |
| Debug a non-obvious error | **Cloud** | Requires reasoning |
| Algorithm or architecture design | **Cloud** | Requires domain knowledge |
| Cross-file or multi-step work | **Cloud** | Local model has no conversation context |
| Domain-specific reasoning | **Cloud** | Accuracy critical |
| Prompt would be >100 words | **Cloud** | Break-even exceeded |
| Bridge not running / different machine | **Cloud** (silently) | — |

Per-model routing addenda (when NOT to delegate even if the universal
rules say to) live in the model's tuning file.

---

## Step 4 — Send the request and wait for the response

Compose the prompt per the active model's tuning file, then hand it to the
helper. There are two shapes; both ack automatically on completion.

**One-shot (fast tasks):**

```bash
PROMPT='<your prompt, structured per the model tuning file>'
printf '%s' "$PROMPT" | bash "$BD" run
```

`run` prints `REQ_ID=<id>` then a terminal line. If it prints `=== DONE ===`,
the text after it is the model's answer — go to Step 5. If it prints
`=== WAITING … ===` (the inference is slower than one poll chunk), continue
with the explicit poll below using the `REQ_ID` it gave you.

**Explicit send + poll (the general case, and required for slow tasks):**

```bash
REQ_ID=$(printf '%s' "$PROMPT" | bash "$BD" send)   # prints the request id
bash "$BD" poll "$REQ_ID"                            # one bounded chunk
```

**Re-run the `poll` line until it prints a terminal marker.** Each `poll` is a
single bounded chunk (~35 s) that stays under the ~45 s cap on one `bash` call
in a Cowork sandbox — so it never gets killed mid-wait. State is derived from
`request.txt`'s age, so it survives across the separate `bash` calls. Outcomes:

- `=== DONE ===` → answer follows; the ack was already written. Go to Step 5.
- `=== WAITING (~Ns of Bs) — re-run … ===` → not finished; run the same
  `poll "$REQ_ID"` again.
- `=== TIMEOUT … ===` → budget exhausted; handle the task in cloud. Do **not**
  retry the local model on the same prompt.
- `=== WATCHER-DOWN … ===` → the watcher didn't pick the request up; surface
  it to the user and handle the task in cloud.

The budget comes from `bridge_config.json` (written by the app's Settings
"leash length" slider), falling back to 120 s — the same source and default
the watcher uses, so the two can't drift. You never write `consumed.txt`
yourself; `poll` does it inside the DONE branch. If you ever find yourself
typing `consumed.txt`, stop — you're reimplementing the helper.

---

## Step 5 — Evaluate, smoke-test, and use the result

1. **Read it** for obvious wrongness (see the model's known failure modes).
2. **Smoke-test returned code before integrating it.** This is a *step*, not
   advice. For a returned function, write and run a handful of assertions on
   known input/output pairs — especially the model's documented weak spots
   (unit conventions, name shadowing, missing imports). Cheap, and it catches
   the silently-wrong class the eye misses. (2026-06-27: a granite
   `eclipse_fraction` was ~57× off from a deg/rad bug that read fine and only
   a numerical sanity check surfaced.) For non-code output, spot-check against
   a reference.
3. **Then:**
   - **Looks good / passes:** use it, note *(handled locally via <model name>)*
   - **Minor issues:** fix them yourself, use the corrected version
   - **Clearly wrong:** discard, handle yourself — do not retry the local model

If a category of failure repeats across multiple sessions, add it to the
active model's tuning file under "Observed weaknesses → mitigations."
The tuning file is the long-term knowledge store; this orchestrator is not.

---

## On adding a new local model

1. Pull the model on the host (e.g. `ollama pull llama3.2-coder:8b`).
2. Add an entry to `models/model_families.json`: `match_prefixes`,
   `tuning_file`, `prompt_wrapping` (`"none"` unless the model needs
   special framing), and `ollama_options`.
3. Copy `models/_template.md` to `models/<model-name>.md` and fill it in
   from a handful of delegation tests. Start from the generic guidance
   in `_generic.md`.
4. Re-run the Setup Wizard's "Install watcher script" step (or manually
   restart the watcher) so it picks up the updated `model_families.json`.
   Update the watcher's `MODEL=`/`C2G_MODEL` if you're also switching the
   default model.

The orchestrator does not need to change, and neither does
`start_local_ai.sh` — new model = new JSON entry + new tuning file.

---

## On debugging sessions that don't involve delegation

A surprising fraction of "C2G work sessions" turn out to be **pure
diagnostic + cloud-side fixes** with zero local-model invocation. Two
patterns recur, both worth knowing:

### The decision NOT to delegate is itself a data point

When a session ends without any `delegation_log.jsonl` entries, that is
not "nothing happened" — it's a routing signal. Capture it in the
relevant model's `models/<name>.md` session log with a short note
explaining *why* delegation didn't fit. Future routing decisions
benefit from knowing which task classes consistently route to cloud.

Common reasons captured in past sessions:
- SwiftUI structural work above ~2 sections
- Debugging-by-diagnosis (reading error output and reasoning about
  platform behaviour, runtime semantics, or permissions)
- Cross-component wiring where the value is in the connections, not
  in any individual file

### "Remove until it works again" beats "add diagnostic instrumentation"

When a SwiftUI / AppKit lifecycle bug surfaces (icon won't appear,
window doesn't show, view doesn't update), the instinct is to add
print statements, deferred logging, and exploratory code paths. This
almost always makes the problem harder to see, because the added code
interacts with the lifecycle issue.

**The faster path:** identify the most recent working state, revert to
it byte-for-byte, and re-introduce changes one at a time. Established
2026-06-29 evening when ~90 minutes of "add more diagnostics" was
collapsed in ~5 minutes by reverting MenuBarApp.swift to the morning's
version and observing the icon return.

This is the AppKit / SwiftUI corollary of the universal "git bisect"
pattern. Capture as a debugging rule because cloud-assistant
instinct strongly favours instrumentation; the rule exists to
counter that instinct.

---

## History

**v0.4.0 (2026-07-13) — the loop became a shipped helper.** Steps 1 and 4 used
to be inline bash templates the orchestrator retyped every session. That's how
the `consumed.txt` ack got dropped more than once, wedging the watcher in a way
indistinguishable from a dead process. Three changes closed the whole failure
class:

- **`bridge_delegate`** (new, ships beside this file) is now the only supported
  driver. The ack is unskippable by construction: a response body is emitted in
  exactly one code path, which writes `consumed.txt` before returning.
- **Heartbeat** (`start_local_ai.sh` v0.2.9 writes `_bridge/status.json`) makes
  liveness *observable* from the sandbox — `status` distinguishes alive / busy /
  dead / no-heartbeat, which previously all looked identical (files not moving).
  It also publishes the active model, so Step 2 no longer guesses it.
- **Chunked polling** (already the model since 2026-07-03) is now folded into
  the helper's `poll`, so the ~45 s sandbox call cap can't be tripped by a
  driver that polls the whole budget in one call.

The `smoke-test returned code` reflex in Step 5 was promoted from advice to a
numbered step in the same revision.
