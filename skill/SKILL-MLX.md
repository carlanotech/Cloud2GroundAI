---
name: mlx-delegate
version: 2.4.0
description: >
  Standing operating procedure for routing mechanical subtasks from a cloud
  AI assistant to a local Granite model running on MLX-Swift via the file-based
  bridge protocol. Use this skill whenever you are about to generate code,
  transform a file, write a script, or do any well-defined mechanical task.
  This is the MLX-native version: zero Ollama, pure Swift, Mac-optimized.
---

# Local AI Delegation — MLX Edition (v2.0)

## What changed from Ollama edition

**v2.0 (MLX-Swift backend):**
- ✅ **No Ollama dependency** — pure Swift binary (`c2g-mlx`)
- ✅ **Heartbeat is required** — `status.json` always present (no fallback)
- ✅ **Savings tracking** — new `savings.json` shows cost saved vs. Claude API
- ✅ **Temperature visible** — exposed in status.json
- ✅ **Model format changed** — `mlx-community/granite-3.3-8b-instruct-8bit` (not `granite4.1:8b`)
- ✅ **Backend indicator** — `"backend": "mlx-swift"` in status

**Protocol unchanged:** Same bridge files, same `bridge_delegate` helper.

---

## What this file is

This is the **orchestrator**. It defines:
- When to delegate vs. when to handle a task in the cloud
- The lifecycle of a delegation through the file-based bridge protocol
- How to recognize and work with the MLX watcher

**Model-specific tuning is in separate files** (to be created as needed).

---

## The protocol helper (unchanged from v0.4.0)

`bridge_delegate` (shipped alongside this file) is the **only** supported way
to drive the bridge. Do **not** hand-roll `request.txt` / `response.txt` /
`consumed.txt` handling.

Locate it:

```bash
BD=""
for d in /sessions/*/mnt/.claude/skills/mlx-delegate \
         "$HOME"/.claude/skills/mlx-delegate \
         /var/folders/*/T/claude-hostloop-plugins/*/skills/mlx-delegate; do
    [ -f "$d/bridge_delegate" ] && { BD="$d/bridge_delegate"; break; }
done
```

Run as `bash "$BD" <subcommand>`. Subcommands: `status`, `send`, `poll`, `run`.

---

## Step 1 — Check if the MLX watcher is active

```bash
bash "$BD" status
```

Expected outputs for MLX v2.0:

| Output | Exit | Meaning | Do |
|---|---|---|---|
| `ALIVE model=mlx-community/granite-3.3-8b-instruct-8bit …` | 0 | MLX watcher up and idle | Proceed to Step 2 |
| `BUSY model=mlx-community/granite-3.3-8b-instruct-8bit …` | 0 | Watcher up, processing | Wait or queue (send will work) |
| `DEAD …` | 3 | Heartbeat frozen | Watcher crashed; ask user to restart |
| `NO-HEARTBEAT …` | 4 | status.json missing | **MLX watcher always writes heartbeat** — this means watcher isn't running |
| `NO-BRIDGE …` | 4 | Bridge folder not found | Connect `~/claude_bridge` or handle in cloud |

**The watcher is a LaunchAgent (`com.cloud2ground.mlx-watcher-dev`), independent
of any GUI app or IDE.** Confirmed 2026-07-19: closing Xcode (which warned it
would "stop Cloud2Ground") killed only the debug-launched menu-bar GUI — the
watcher kept running with a fresh heartbeat. The bridge protocol talks to the
watcher through files, never through the GUI app. Don't assume the menu-bar
app or an IDE needs to be open for delegation to work, and don't relaunch
anything based on that assumption — run Step 1's `status` check first.

**Key difference from Ollama version:** `NO-HEARTBEAT` now definitively means
"watcher not running" (no pre-v0.4 fallback needed). The MLX watcher always
writes `status.json`.

**MLX status.json format:**

```json
{
  "status": "ready",
  "model": "mlx-community/granite-3.3-8b-instruct-8bit",
  "temperature": 0.2,
  "backend": "mlx-swift",
  "version": "2.0-phase1",
  "last_heartbeat": 1784432073
}
```

**When you see this status, also check savings** (new in v2.0):

```bash
cat ~/claude_bridge/savings.json
```

Example:

```json
{
  "total_requests": 42,
  "total_input_tokens": 3421,
  "total_output_tokens": 12450,
  "estimated_cost_saved_usd": 0.196893,
  "last_updated": 1784432073,
  "version": "2.0-phase1"
}
```

**Tell the user about their savings occasionally!** E.g., after completing a
delegation: *"Handled locally via Granite 8B (MLX). You've saved $0.20 in
API costs so far today."*

---

## Step 2 — Identify the active model

The model name is in the `status` output from Step 1.

**Current MLX models available:**

| Model | Size | Speed | Quality | Default |
|-------|------|-------|---------|---------|
| `granite-3.3-8b-instruct-8bit` | 8 GB | ~5-10s | Excellent | ✅ Yes |
| `granite-3.3-2b-instruct-8bit` | 2.5 GB | ~2-5s | Good | Fast mode |

**Default for v2.0: 8B model** (better quality, speed doesn't matter since
processing is async while user works with Claude).

---

## Model-Specific Tuning

### Granite 3.3-8B (Default, Recommended)

**Strengths:**
- **Complex algorithms** — handles multi-step logic, recursion, edge cases
- **Detailed explanations** — produces tutorial-quality documentation
- **Code comments** — writes comprehensive inline documentation
- **Error handling** — anticipates edge cases without being told
- **Type safety** — includes type hints, generics, proper signatures

**Best for:**
- Production code that needs to be correct
- Functions with non-trivial logic
- Algorithm implementations with explanation
- Code that handles edge cases
- Documentation and docstrings
- Anything where quality > speed

**Prompt style:**
- Natural language works well
- Can handle implicit requirements
- Understands context from brief descriptions
- Example: "Write a binary search with edge case handling" → produces complete, correct code

**Known limitations:**
- Slightly slower (~5-10s) but user isn't waiting (async)
- Larger model means first load takes longer (~30s on cold start)
- **Will sometimes invent plausible-looking behavior instead of leaving a
  case unhandled — even when the spec explicitly rules it out.** Confirmed
  2026-07-19: asked for a diff that "compares per shared axis" (spec's exact
  words), it still invented a `master: None` result for an axis present on
  only one side — a case the spec's own sentence already excluded. This is
  not an ambiguous-spec failure like the ones below; re-read generated code
  against the spec's explicit sentences, not just for obviously wrong output.

**Example delegations that work well:**
```bash
# Algorithm with explanation
"Write a Python function to implement quicksort with detailed comments explaining the partition logic"

# Edge case handling
"Write a bash script to safely delete files matching a pattern, with dry-run mode and error handling"

# Complex transformation
"Write a jq filter that flattens nested JSON and renames keys according to this mapping: [example]"
```

---

### Granite 3.3-2B (Fast Mode, Optional)

**Strengths:**
- **Simple functions** — straightforward input→output transformations
- **One-liners** — bash/Python/jq commands
- **Quick iterations** — when you need fast feedback
- **Pattern-based tasks** — fill-in-the-blank, template expansion

**Best for:**
- Trivial helper functions
- String manipulation
- Simple regex
- Config file snippets
- When you need answer NOW (though 8B is only 5-10s anyway)

**Prompt style:**
- Be more explicit than with 8B
- Spell out edge cases you want handled
- Provide example input/output when possible
- Example: "Write a function that reverses a string. Input: str, Output: reversed str. Handle empty string."

**Known limitations:**
- Less sophisticated reasoning
- May miss edge cases unless explicitly told
- Shorter, less detailed explanations
- Simpler variable naming

**When to use 2B instead of 8B:**
- Honestly? Almost never. 8B is better and speed doesn't matter.
- Only if you're iterating rapidly and want instant feedback
- User can switch by setting `C2G_MLX_MODEL=mlx-community/granite-3.3-2b-instruct-8bit`

**Example delegations:**
```bash
# Simple function
"Write a Python function that adds two numbers"

# One-liner
"Write a bash command to count files in a directory"

# Basic transformation
"Convert this JSON to YAML" (with example pasted)
```

---

## Choosing Which Model Gets the Task

**Default strategy: Always use whichever model is running** (shown in status).

The user sets the model when starting the watcher. You don't choose; you use
what's active.

**If 8B is active:** Delegate freely. It handles everything in the routing table.

**If 2B is active:** Still delegate! Just be slightly more explicit in prompts.
Add example input/output for edge cases.

**User wants to switch models:**
They stop the watcher and restart with different `C2G_MLX_MODEL` env var.
Not something you control from the skill.

---

## Step 3 — Decide whether to delegate

**Same routing rules as v0.4.0** (unchanged):

Two hard tests:
1. **Prompt length:** Can you write it in <100 words?
2. **Verbatim test:** Would you use output verbatim or need to edit?

If either fails → keep in cloud.

Routing table:

| Task type | Route | Why |
|---|---|---|
| Helper function from clear spec | **Local** | Short prompt, pattern output |
| Docstrings on pasted code | **Local** | Additive, mechanical |
| One-liner (bash/Python/jq) | **Local** | Tiny prompt, directly usable |
| Unit test stubs | **Local** | Mechanical, pattern-based |
| Regex or config snippet | **Local** | Well-defined, verifiable |
| **Complex algorithm explanation** | **Local (8B)** | **NEW:** 8B handles this well |
| Prose with technical accuracy | **Cloud** | Rework cost negates savings |
| Refactor with vague goal | **Cloud** | Requires judgment |
| Debug non-obvious error | **Cloud** | Requires reasoning |
| Cross-file or multi-step | **Cloud** | No conversation context |
| Domain-specific reasoning | **Cloud** | Accuracy critical |
| Prompt >100 words | **Cloud** | Break-even exceeded |

**New with 8B:** More tasks are delegatable. The 8B model handles:
- Algorithm explanations with examples
- Edge case documentation
- Complex code comments
- Multi-step transformations

These would have been borderline with 2B but are solid with 8B.

---

## Prompt-writing checklist (avoid known failure modes)

**The model is reliable on sharply-bounded, single-shape functions and
degrades as soon as it has to *infer* something the prompt didn't state
outright.** Confirmed on a real project (2026-07-19, 4 delegations): two of
three broken outputs traced back to the prompt leaving a decision implicit,
not to the model reasoning badly. Before sending a prompt, check it against
this list:

- **Any argument or value that can take more than one shape:** state the
  exact discriminator condition to branch on. Don't describe the shapes and
  trust the model to infer how to tell them apart — `isinstance(x, dict)`
  will not distinguish "a dict that means one value" from "a dict that means
  several," and the model will pick one branch for both.
- **Any numeric output field with a naming hint** (`_pct`, `_ms`, etc.):
  state the scaling/units explicitly even if the name seems self-evident.
  Don't assume `_pct` implies `×100` — say so.
- **"What happens if X is missing/absent":** answer it directly in the
  prompt. Don't leave it implied by the rest of the spec.
- **Validation/reasonableness checks:** state the default for
  unrecognized or edge-case input explicitly (flag it vs. silently accept
  it). Whatever this project's default should be, name it — don't let the
  model pick.

If a task needs several of these spelled out, that's a signal it's closer to
the >100-word cloud line than it looks — see Step 3.

---

## Step 4 — For long or multi-part prompts, confirm understanding first

Applies when the prompt is pushing toward the 100-word cloud/local line
(roughly 40+ words) or bundles several sub-tasks into one request. Short,
single-purpose prompts — the common case, if Step 3's chunking did its job —
skip straight to Step 5; this adds a round-trip, so it's not worth it for
anything already bite-sized.

Send a cheap probe before the real prompt, using the same primitives as
everything else here:

```bash
PROBE='In one sentence, restate what you are being asked to build, and name
anything ambiguous or missing. Do not write code yet.'
REQ_ID=$(printf '%s' "$PROBE" | bash "$BD" send)
bash "$BD" poll "$REQ_ID"
```

Evaluate the restatement:

| Restatement says | Do |
|---|---|
| Matches your intent, no gaps flagged | Proceed to Step 5 with the full prompt |
| Missing a detail you can supply | Add it to the real prompt and send once — no need to re-probe |
| Flags a real ambiguity needing judgment | Handle in cloud — same signal as a failed Step 3 verbatim test |
| Restatement is generic or off-target | Small model isn't tracking this one — handle in cloud |

**Why restate-and-flag instead of a confidence score:** asking Granite to
rate its own confidence (e.g. "1–5, how sure are you?") isn't reliable —
small models tend to answer "confident" regardless of whether they actually
are. Asking it to restate the task in its own words gives *you* something
concrete to judge, instead of trusting its self-assessment.

This costs one extra request against the delegation budget and counts toward
`savings.json`'s `total_requests` like any other call — worth it only when
the prompt is long enough that a misfire would cost more than the probe.

---

## Step 5 — Send the request and wait for response

**Exactly same as v0.4.0:**

One-shot:
```bash
PROMPT='<your prompt>'
printf '%s' "$PROMPT" | bash "$BD" run
```

Explicit send + poll:
```bash
REQ_ID=$(printf '%s' "$PROMPT" | bash "$BD" send)
bash "$BD" poll "$REQ_ID"
# Re-run poll until terminal marker
```

Outcomes: `=== DONE ===`, `=== WAITING … ===`, `=== TIMEOUT … ===`, `=== WATCHER-DOWN … ===`

**`TIMEOUT` now means genuinely dead, not just "over budget"** (fixed
2026-07-19): if `processing.lock` is still present when the budget is hit,
`poll` reports `WAITING`, not `TIMEOUT` — a slow-but-alive job (long
pattern-completion generations especially) keeps getting polled instead of
being reported as a failure it isn't. Re-poll on `WAITING` same as always.

---

## Step 6 — Evaluate, smoke-test, and use the result

1. **Read it** for obvious wrongness
2. **Smoke-test code before using it:**
   - For functions: test on known input/output pairs
   - For configs: validate syntax
   - For commands: dry-run first
3. **If the code serializes a `dict`/JSON output built from a `set()` (or
   anything else without guaranteed order) into a file meant to be diffed,
   checked into git, or compared run-to-run: verify the output is
   deterministic, not just correct.** Confirmed 2026-07-19: a generator
   iterated a Python `set()` for property order — hash-randomized per
   process — and reordered every material's properties on every rerun with
   zero actual value changes. Harmless on its own, but this whole
   evaluation step leans on diffs meaning something; a non-deterministic
   generator buries real regressions in reorder noise until one actually
   matters. Fix is the same either way: iterate a stable, declared order,
   never raw set/dict order.
4. **Then:**
   - Looks good → use it, note *(handled locally via Granite 8B on MLX)*
   - Minor issues → fix and use
   - Clearly wrong → discard, handle in cloud

**Include savings in your response:**

After completing a delegation, optionally mention:
```
*(Handled locally via Granite 8B. Total API cost saved today: $X.XX)*
```

Pull from `~/claude_bridge/savings.json` → `estimated_cost_saved_usd`

---

## The economic argument (unchanged)

Writing is expensive. Reviewing is cheap.

| Approach | Cloud tokens |
|---|---|
| Cloud writes from scratch | 1.0× |
| Local writes, cloud ships verbatim | ~0.1× |
| Local writes, cloud patches one bug | ~0.3× |
| Local writes, cloud rewrites entirely | ~1.1× |

Three of four outcomes save tokens. As long as local output is right or
partially right most of the time, delegation wins.

**With 8B:** The "partially right" case is even rarer. The 8B model gets it
fully right more often than 2B did.

**A session can legitimately delegate nothing, and that's the routing table
working, not a shortfall.** Confirmed 2026-07-19: a full multi-hour session
(investigation, cross-file reconciliation logic, a non-determinism bug, an
engineering judgment call) delegated zero tasks — every one of them was
explicitly a "keep in cloud" case per Step 3's routing table. Don't delegate
something just to have a delegation count; a 0% rate on a session shaped like
that is the table doing its job.

---

## MLX-specific notes

### Temperature

The MLX watcher runs at **temperature 0.2** by default (visible in status.json).
This is optimal for code generation (deterministic, focused).

Lower = more deterministic (0.0-0.3)  
Higher = more creative (0.7-1.0)

For code tasks, keep it at 0.2.

### Speed doesn't matter

The user is working with Claude while Granite processes in the background.
Response time (5-10s for 8B) is irrelevant — the task is async.

**Don't apologize for "slow" responses.** There are no slow responses when
the user isn't waiting.

### Model switching (future)

Currently: 8B default, 2B available via env var.

Future enhancement: Skill could request "fast mode" for trivial tasks by
writing a special header in request.txt. Not implemented yet.

---

## Autonomous / overnight sessions

Notes specific to unattended runs (long delegation sessions, overnight
work), gathered 2026-07-19:

- **Bypass-permissions mode doesn't apply retroactively mid-session.**
  Toggling it partway through an existing session doesn't stop prompts from
  appearing — it only takes effect from a fresh session start. If a session
  is planned to run unattended, turn it on *before* starting, not after
  hitting the first prompt. (Workaround if you're already mid-session:
  start a new session continuing the same context — see the commit-often
  note below for why that's safe.)
- **Scoped Bash allowlist rules are fragile to invocation-style drift.**
  A prefix-wildcard rule like `Bash(python3 "<abs path>/foo/*)"` only
  matches that literal invocation string — `cd "$D" && python3 foo.py
  <relative args>` is a different string and won't match, triggering the
  exact prompt the rule was meant to avoid. Either commit to one exact
  invocation style for every command a scoped rule needs to match, or use
  session-level bypass-permissions for genuinely unattended work (with the
  timing caveat above).
- **Commit early, often, and atomically, with real message detail.** A
  fresh session with zero memory of the conversation should be able to pick
  up a project correctly from `git log` alone. Treat conversation memory as
  convenience, never as the only record of what happened or why — this is
  what makes a forced session restart (e.g. from the bypass-mode timing
  issue above) a non-event instead of a risk.
- **A ProtonDrive-synced (or any cloud-synced) folder can produce spurious
  sync-conflict duplicate files** if a script rewrites the same file
  repeatedly in a short window — e.g. rerunning a generator three times
  while testing produces `foo (#Edit conflict...).json` when sync races a
  write. Before touching either file, diff the duplicate against the real
  one; if byte-identical, it's pure sync-timing noise, not a real conflict —
  delete it and add the pattern to `.gitignore`.

---

## On debugging sessions that don't involve delegation

Same as v0.4.0:

- **Non-delegation is data** — capture why you didn't delegate
- **"Remove until it works" beats "add diagnostics"** — especially for SwiftUI lifecycle bugs

---

## History

**v2.4.0 (2026-07-19) — orchestrator-level lessons from the same session:**
- Source: `SKILL_LESSONS_2026-07-19.md`, written alongside the v2.3.0 session
  as a separate pass over what the session implied for the skill itself
- Step 1: documented that the MLX watcher LaunchAgent is independent of any
  GUI app or IDE — confirmed live that closing Xcode killed only the
  debug-launched menu-bar app, not the watcher
- Economic-argument section: noted that a session can legitimately delegate
  zero tasks when every task shape hits Step 3's own "keep in cloud" rows —
  that's the routing table working, not a gap to feel bad about
- Step 6: added a determinism check alongside correctness — any generator
  serializing a `dict`/JSON output built from a `set()` (unordered,
  hash-randomized per process) into a file meant to be diffed or
  version-controlled needs a stable declared iteration order, or every
  regeneration produces full-file diff noise that buries real regressions
- New **Autonomous / overnight sessions** section: bypass-permissions mode
  only takes effect from a fresh session start, not mid-session; scoped Bash
  allowlist rules only match one exact invocation string; commit early/often/
  atomically so a forced restart costs nothing; cloud-synced folders (e.g.
  ProtonDrive) can produce spurious sync-conflict duplicate files under rapid
  repeated writes — diff against the real file and gitignore the pattern if
  identical

**v2.3.0 (2026-07-19) — lessons from first real-project test session:**
- Source: Material Optimization project, 4 delegations, 3 correctly not
  shipped (caught at Step 6, not after)
- Fixed `bridge_delegate`'s `cmd_poll`: `TIMEOUT` was firing purely on
  elapsed time, without checking whether `processing.lock` was still
  present. A 10-test generation blew the 120s budget while genuinely still
  running, was reported as `TIMEOUT`, and completed correctly on the very
  next poll. Now: budget exceeded + `processing.lock` still present →
  `WAITING`, not `TIMEOUT`. Applied to all three deployed copies (outer
  `skill/`, bundled Cloud2Ground copy, and the live
  `~/.claude/skills/mlx-delegate/` copy orchestrators actually resolve)
- New **Prompt-writing checklist** section (between Step 3 and Step 4):
  name the exact shape-discriminator instead of describing shapes and
  trusting `isinstance`-style inference; state scaling/units on `_pct`-style
  fields explicitly; answer "what if X is missing" directly; state the
  default for unrecognized/edge-case input explicitly for validation tasks
- New known limitation on Granite 3.3-8B: will sometimes invent plausible
  extra behavior even when the spec's explicit wording already rules it
  out — not the same failure mode as an ambiguous spec, and the checklist
  above won't catch it; only re-reading against the spec's exact sentences
  will

**v2.2.0 (2026-07-19) — confirm-first for long prompts:**
- New Step 4: for prompts near the 100-word local/cloud line (or bundling
  multiple sub-tasks), send a cheap "restate the task and flag ambiguity"
  probe before the real request, using the same `bridge_delegate`
  `send`/`poll` primitives — no protocol or `bridge_delegate` changes needed
- Deliberately not a confidence score — small models self-report as
  confident regardless of accuracy; restating the task gives the
  orchestrator something concrete to judge instead
- Skip this step for short, single-purpose prompts (the common case when
  Step 3's chunking is doing its job) — the extra round-trip only pays for
  itself on prompts long/complex enough that a misfire is expensive

**v2.1.0 (2026-07-18) — MLX-only, no Ollama fallback:**
- Dropped the "backward compatibility with Ollama" path — v2.0 ships MLX-only
- `bridge_delegate`'s `cmd_status()` no longer parses the legacy seq/state/
  last_seen schema; it only understands the current status/last_heartbeat one
- Fixed: `cmd_status()` was misreading the current schema as `DEAD` because it
  only knew the old one — real bug, not a dead watcher
- Fixed: `savings.json`'s `estimated_cost_saved_usd` could render without a
  leading zero (`.013452`), invalid JSON — `bc` output quirk
- Fixed: `C2G_MLX_TEMPERATURE` was shown in `status.json` but never actually
  passed to the model — generation ran at library-default temperature 0.6,
  not the documented 0.2
- Added `topP: 0.9` and `maxTokens: 4096` to generation params per the
  production plan's Phase 1.1 spec (previously unset/unbounded)
- Ported markdown fence-stripping from the retired Ollama watcher — 8B output
  embeds fenced code blocks inside prose, which is a real display difference
  the mechanical delegation contract didn't previously handle
- Default model changed 2B → 8B: the 2B model reliably produced malformed
  code (JS/Python syntax mashups) on trivial prompts regardless of
  temperature; 8B did not

**v2.0.0 (2026-07-18) — MLX-Swift backend:**
- Removed Ollama dependency entirely
- Added savings tracking
- Made heartbeat mandatory
- Updated model naming convention
- Added backend indicator in status
- 8B model now default (quality over speed since async)
- Simplified Step 1 (no pre-v0.4 fallback needed)

**v0.4.0 (2026-07-13) — bridge_delegate helper introduced** (applies to both)

---

## Quick reference for common tasks

### Check watcher status
```bash
bash "$BD" status
```

### Check savings
```bash
cat ~/claude_bridge/savings.json
```

### Send a code generation task
```bash
PROMPT="Write a Python function that reverses a string with type hints and docstring"
printf '%s' "$PROMPT" | bash "$BD" run
```

### What to tell the user after a successful delegation
```
I've delegated this to your local Granite 8B model running on MLX-Swift.

[result appears]

*(Handled locally — you've saved $0.XX in API costs so far.)*
```

---

*MLX Edition — v2.4.0*  
*Maintained alongside MLX watcher v2.0-phase1*  
*Pure Swift • Zero Ollama • Mac-native*
