---
name: ollama-delegate
version: 0.3.7
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
SANDBOXED=""
BRIDGE=$(ls -d /sessions/*/mnt/claude_bridge/_bridge 2>/dev/null | head -1)
if [ -n "$BRIDGE" ]; then
    SANDBOXED=1
elif [ -d "$HOME/claude_bridge/_bridge" ]; then
    BRIDGE="$HOME/claude_bridge/_bridge"
fi

if [ -n "$BRIDGE" ] && [ -z "$SANDBOXED" ]; then
    # curl/pgrep are only meaningful when bash is running directly on
    # Andrew's Mac (Claude Code). See the sandboxed note below.
    OLLAMA_OK=$(curl -sf --max-time 2 http://localhost:11434/api/tags > /dev/null 2>&1 && echo yes || echo no)
    WATCHER_OK=$(pgrep -f "start_local_ai.sh" > /dev/null 2>&1 && echo yes || echo no)
fi
```

**Sandboxed note (Cowork / any remote bash sandbox):** if `BRIDGE` was found
under `/sessions/*/mnt/...`, the bash tool is running in an isolated remote
sandbox with no network route to the host Mac's `localhost` or process
table. `curl` and `pgrep` will report "no" on a live bridge every time —
this is a false negative, not a real signal. Do not run them, and do not
treat a missing `OLLAMA_OK`/`WATCHER_OK` as "down" in this case. Skip
straight to Outcome A; Step 4's `processing.lock` appearance is the real
liveness check when sandboxed.

**Never improvise a PONG/liveness round-trip through the bridge.** Sending an
ad-hoc `request.txt` ("reply with PONG") and reading the answer works once —
but if you don't then write `consumed.txt`, the `response.txt` you left behind
blocks the watcher from every subsequent request (see the Step 4 reconcile).
Use `processing.lock` appearing within ~10s as the liveness signal, never a
hand-rolled ping. The invariant, everywhere: **any `response.txt` you read,
you acknowledge with `consumed.txt`** — no exceptions, including probes.

**Outcome A — fully ready**: `BRIDGE` set and either (a) `SANDBOXED=1`, or
(b) both `OLLAMA_OK` and `WATCHER_OK` = yes. Proceed to Step 2.

**Outcome B — bridge folder exists but Ollama or watcher is down**
(non-sandboxed only — `OLLAMA_OK` or `WATCHER_OK` = no): ask the user to
start it before proceeding (see prior guidance in `SKILL.md` history; the
exact terminal command is system-specific).

**Outcome C — bridge folder not found**: the likely cause is that
`~/claude_bridge` just isn't connected to this session yet — it's a separate
grant from the project folder, and in a sandboxed Cowork session it must be
mounted before Step 1 can see it. Don't make the user hunt for it:

- **If a folder-request tool is available** (e.g. `request_cowork_directory`
  in Cowork), call it with path `~/claude_bridge` to pop a one-click connect
  prompt, then retry Step 1. This is the smooth path — prefer it.
- **If no such tool exists** (e.g. some Claude Code setups) but the user is on
  the host, `~/claude_bridge/_bridge` may be readable directly — the Step 1
  check already tries that path.
- **Only if neither works**, ask the user to connect `~/claude_bridge` via
  Cowork's folder picker, then retry Step 1.

If the bridge genuinely isn't set up (no `~/claude_bridge` at all), the user
hasn't installed the Mac app / run its setup wizard yet — handle the task
yourself, no mention needed.

**History (2026-07-06):** this used to point at `~/Documents/claude_bridge`.
Moved to `~/claude_bridge` (outside Documents) because macOS TCC blocks a
background LaunchAgent's python3 from ever reading/writing inside
Documents/Desktop/Downloads on a fresh account — confirmed via a clean
Parallels VM test where every bridge file operation failed with
"[Errno 1] Operation not permitted." A plain folder elsewhere under `$HOME`
isn't covered by that protection.

---

## Step 2 — Identify the active local model and load its tuning file

```bash
# Ask Ollama which model is currently loaded / configured for the bridge.
# python-free: pull the first "name" field out of /api/tags with grep+sed so
# this works on a bare Mac with no Command Line Tools (no python3, no jq).
ACTIVE_MODEL=$(curl -sf http://localhost:11434/api/tags 2>/dev/null \
    | grep -o '"name"[[:space:]]*:[[:space:]]*"[^"]*"' \
    | head -n 1 \
    | sed 's/.*:[[:space:]]*"\([^"]*\)"/\1/')
```

Then find the matching tuning file by reading **`models/model_families.json`**
(not a hand-maintained table here — this file is the single source of
truth, also read directly by `start_local_ai.sh` for prompt wrapping and
Ollama options, so it can't drift out of sync with what the watcher
actually does): find the entry in `families` whose `match_prefixes`
contains a case-insensitive prefix of `ACTIVE_MODEL`, and load its
`tuning_file`. If nothing matches, use the `default` entry's
`tuning_file` (`models/_generic.md`) and add a note in the response that
the model is untuned.

*(History: prior to 2026-07-01 this step held its own copy of a
prefix → tuning-file table, duplicating facts also hand-copied into
`start_local_ai.sh` and `protocol/SPEC.md`. They drifted — see
`model_families.json`'s `_doc` field. Don't reintroduce a table here;
read the JSON.)*

Read the tuning file end-to-end before composing any delegation prompt.
Per-model files define:
- Output-format conventions the model expects
- Known prompt patterns that work for that model
- Failure modes specific to that model
- Whether the prompt needs special framing (e.g. Granite Q/A template,
  Claude system-role wrapping, etc.) — though most framing now happens
  in the watcher, not the prompt

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

```bash
# Generate a unique id (protocol v0.2+; watcher echoes it back).
# python-free: uuidgen ships in the macOS base system (no CLT needed).
REQ_ID="t-$(uuidgen | tr -d '-' | tr 'A-Z' 'a-z' | cut -c1-12)"

# Wait until the bridge is idle — and RECONCILE a stale response first.
# A response.txt is cleared only when the CLIENT writes consumed.txt (the
# watcher then deletes both). If any earlier read left a response.txt WITHOUT
# writing consumed.txt — an aborted cycle, or an improvised PONG/liveness
# ping — the watcher's process-guard (it requires response.txt to be absent)
# refuses EVERY future request. Writing request.txt into that state is the
# "one request answered, then silence forever" trap (the 2026-07-11 hang).
# So: if a leftover response is present while nothing is being processed, it
# is orphaned (ours isn't sent yet) — acknowledge it to release the watcher.
for i in $(seq 1 15); do
    if [ ! -f "$BRIDGE/request.txt" ] \
       && [ ! -f "$BRIDGE/response.txt" ] \
       && [ ! -f "$BRIDGE/processing.lock" ]; then
        break
    fi
    if [ -f "$BRIDGE/response.txt" ] && [ ! -f "$BRIDGE/processing.lock" ]; then
        echo "done" > "$BRIDGE/consumed.txt"   # release an orphaned response
    fi
    sleep 1
done

# Hard stop: never send into a bridge that still holds a response.txt. If the
# reconcile above could not clear it, the watcher cannot answer us — surface
# it and handle the task in the cloud rather than writing a request that will
# hang. This is the invariant the 2026-07-11 single-request hang violated.
if [ -f "$BRIDGE/response.txt" ]; then
    echo "bridge has an unclearable stale response — not sending; handle in cloud" >&2
    # Do NOT write request.txt below; fall back to Step 5 as a cloud task.
fi

# Compose the prompt (apply the model's tuning rules)
{
  echo "# id: $REQ_ID"
  cat << 'PROMPT'
<your prompt here, structured per the active model's tuning file>
PROMPT
} > "$BRIDGE/request.txt"

```

**Poll in sandbox-safe chunks — this is a SEPARATE shell call, run more than once.**
A Cowork sandbox caps a single `bash` call at ~45 s, so do NOT poll the full
90–120 s budget in one call — it gets killed mid-wait and looks like a failure
even though the request was written fine (this is the friction the
2026-07-13 Material-Optimization test hit). Instead run the block below and
**re-run it** until it prints `DONE`, `TIMEOUT`, or `WATCHER-DOWN`. State does
not persist between `bash` calls, so elapsed time is derived from `request.txt`'s
age, and `REQ_ID` is the id you wrote in the send step above.

```bash
# ── POLL ONE CHUNK — re-run until it prints DONE / TIMEOUT / WATCHER-DOWN ──
CHUNK=35   # stay comfortably under the ~45s single-call cap

# Budget (seconds) from bridge_config.json — the SAME source the watcher reads
# (written by the app's Settings "leash length" slider). Falls back to 120s to
# match the watcher's own fallback. Don't reintroduce a competing hardcoded
# number; three of them had already drifted (skill 90 / watcher 120 / SPEC 60)
# before this was unified in 2026-07-03.
POLL_SECONDS=$(sed -n 's/.*"delegation_timeout_seconds"[[:space:]]*:[[:space:]]*\([0-9][0-9.]*\).*/\1/p' \
    "$BRIDGE/bridge_config.json" 2>/dev/null | head -n 1)
POLL_SECONDS=${POLL_SECONDS%%.*}
case "$POLL_SECONDS" in ''|*[!0-9]*|0) POLL_SECONDS=120 ;; esac

# Total elapsed is derived from request.txt's age so it survives across the
# separate bash calls (the watcher removes request.txt only when it takes our
# request; while we wait, it sits there and its mtime is our clock).
now=$(date +%s)
mtime=$(stat -c %Y "$BRIDGE/request.txt" 2>/dev/null || stat -f %m "$BRIDGE/request.txt" 2>/dev/null || echo "$now")
elapsed=$(( now - mtime ))
first_chunk=0; [ "$elapsed" -lt "$CHUNK" ] && first_chunk=1

for i in $(seq 1 "$CHUNK"); do
    if [ -f "$BRIDGE/response.txt" ] && [ ! -f "$BRIDGE/processing.lock" ]; then
        FIRST=$(head -n 1 "$BRIDGE/response.txt")
        if [ "$FIRST" = "# id: $REQ_ID" ]; then
            echo "=== DONE ==="
            tail -n +2 "$BRIDGE/response.txt"
            echo "done" > "$BRIDGE/consumed.txt"   # acknowledge → watcher clears it
            exit 0
        fi
        # id mismatch = a LEFTOVER from an earlier request (a slow prior
        # inference finishing late). Ignore it, do NOT write consumed.txt for
        # someone else's answer, and keep polling for OUR id.
    fi
    # Sandboxed liveness (see Step 1): no processing.lock within the first ~10s
    # means the watcher isn't picking requests up. Only meaningful on chunk 1.
    if [ "$first_chunk" = 1 ] && [ "$i" -eq 10 ] \
       && [ ! -f "$BRIDGE/processing.lock" ] && [ ! -f "$BRIDGE/response.txt" ]; then
        echo "=== WATCHER-DOWN: no processing.lock in 10s — watcher isn't picking up requests ==="
        exit 0
    fi
    sleep 1
done

# Not answered this chunk — decide whether to keep waiting.
now=$(date +%s); elapsed=$(( now - mtime ))
if [ "$elapsed" -ge "$POLL_SECONDS" ]; then
    echo "=== TIMEOUT after ~${elapsed}s (budget ${POLL_SECONDS}s) — handle the task in the cloud ==="
else
    echo "=== WAITING (~${elapsed}s of ${POLL_SECONDS}s) — RE-RUN this poll chunk ==="
fi
```

Outcomes: **`DONE`** → the text after the `=== DONE ===` line is the model's
answer; go to Step 5. **`WATCHER-DOWN`** or **`TIMEOUT`** → handle the task
yourself in the cloud; do not retry the local model on the same prompt.

If no matching response within `$POLL_SECONDS`, fall back to handling the
task yourself. Do not retry the local model on the same prompt.

*(History: prior to 2026-07-03 this step polled for a hardcoded 90s, a
number that had already drifted from start_local_ai.sh's own hardcoded
120s Ollama-request timeout and from a third number (60s) claimed in
protocol/SPEC.md — none of the three had ever been connected to the
Settings app's delegation-timeout slider, which was UI-only. Now all
three agree by reading `bridge_config.json`, written by the app whenever
that slider moves. Don't reintroduce a hardcoded number here.)*

**Sandboxed liveness recap:** `processing.lock` appearing within ~10s of
writing `request.txt` confirms the watcher is alive and picked up the
request — that's the true signal in a Cowork/sandboxed context, replacing
the curl/pgrep check from Step 1. If it never appears, the watcher is down
or the bridge folder isn't the one the watcher is actually watching; surface
that to the user rather than waiting out the full `$POLL_SECONDS`.

---

## Step 5 — Evaluate and use the result

- **Looks good**: use it, note *(handled locally via <model name>)*
- **Minor issues**: fix them yourself, use the corrected version
- **Clearly wrong**: discard, handle yourself — do not retry the local model

If a category of failure repeats across multiple sessions, add it to the
active model's tuning file under "Observed weaknesses → mitigations."
The tuning file is the long-term knowledge store; this orchestrator is
not.

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
