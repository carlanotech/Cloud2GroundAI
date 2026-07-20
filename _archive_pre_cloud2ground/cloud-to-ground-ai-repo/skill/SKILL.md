---
name: ollama-delegate
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
BRIDGE=$(ls -d /sessions/*/mnt/claude_bridge/_bridge 2>/dev/null | head -1)
if [ -z "$BRIDGE" ] && [ -d "$HOME/Documents/claude_bridge/_bridge" ]; then
    BRIDGE="$HOME/Documents/claude_bridge/_bridge"
fi

if [ -n "$BRIDGE" ]; then
    OLLAMA_OK=$(curl -sf --max-time 2 http://localhost:11434/api/tags > /dev/null 2>&1 && echo yes || echo no)
    WATCHER_OK=$(pgrep -f "start_local_ai.sh" > /dev/null 2>&1 && echo yes || echo no)
fi
```

**Outcome A — fully ready** (`BRIDGE` set, both `OLLAMA_OK` and `WATCHER_OK` = yes):
proceed to Step 2.

**Outcome B — bridge folder exists but Ollama or watcher is down**:
ask the user to start it before proceeding (see prior guidance in
`SKILL.md` history; the exact terminal command is system-specific).

**Outcome C — bridge folder not found**:
handle everything yourself, no mention needed.

---

## Step 2 — Identify the active local model and load its tuning file

```bash
# Ask Ollama which model is currently loaded / configured for the bridge
ACTIVE_MODEL=$(curl -sf http://localhost:11434/api/tags 2>/dev/null \
    | python3 -c "import sys, json; \
        models = json.load(sys.stdin).get('models', []); \
        print(models[0]['name'] if models else '')" 2>/dev/null)
```

Then load the matching tuning file:

| Active model prefix | Tuning file |
|---|---|
| `granite-code:*`    | `models/granite-code.md` |
| `granite3-*`        | `models/granite3.md` (if present) |
| `claude-*` (local)  | `models/claude-cli.md` (if present) |
| anything else       | `models/_generic.md` (fallback) |

If the matching file does not exist, fall back to `models/_generic.md`
and add a note in the response that the model is untuned.

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
# Generate a unique id (protocol v0.2+; watcher echoes it back)
REQ_ID="t-$(python3 -c 'import uuid; print(uuid.uuid4().hex[:12])')"

# Wait until bridge is idle
for i in $(seq 1 15); do
    [ ! -f "$BRIDGE/request.txt" ] \
        && [ ! -f "$BRIDGE/response.txt" ] \
        && [ ! -f "$BRIDGE/processing.lock" ] \
        && break
    sleep 1
done

# Compose the prompt (apply the model's tuning rules)
{
  echo "# id: $REQ_ID"
  cat << 'PROMPT'
<your prompt here, structured per the active model's tuning file>
PROMPT
} > "$BRIDGE/request.txt"

# Poll up to 90s; verify id echo before accepting
for i in $(seq 1 90); do
    if [ -f "$BRIDGE/response.txt" ] && [ ! -f "$BRIDGE/processing.lock" ]; then
        FIRST=$(head -n 1 "$BRIDGE/response.txt")
        if [ "$FIRST" = "# id: $REQ_ID" ]; then
            RESPONSE=$(tail -n +2 "$BRIDGE/response.txt")
            echo "done" > "$BRIDGE/consumed.txt"
            break
        else
            # Stale or mismatched id; do not use
            echo "done" > "$BRIDGE/consumed.txt"
            RESPONSE=""
            break
        fi
    fi
    sleep 1
done
```

If no matching response after 90s, fall back to handling the task yourself.
Do not retry the local model on the same prompt.

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
2. Update the watcher's `MODEL=` line and restart it.
3. Copy `models/_template.md` to `models/<model-name>.md`.
4. Run a handful of delegation tests against the new model and fill in
   the tuning file. Start from the generic guidance in `_generic.md`.
5. Add the prefix → file mapping to the table in Step 2 above.

The orchestrator does not need to change. New model = new file.
