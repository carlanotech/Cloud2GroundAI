---
name: mlx-delegate
version: 2.0.0
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

## Step 4 — Send the request and wait for response

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

**Nothing changed here** — same helper, same protocol.

---

## Step 5 — Evaluate, smoke-test, and use the result

1. **Read it** for obvious wrongness
2. **Smoke-test code before using it:**
   - For functions: test on known input/output pairs
   - For configs: validate syntax
   - For commands: dry-run first
3. **Then:**
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

## On debugging sessions that don't involve delegation

Same as v0.4.0:

- **Non-delegation is data** — capture why you didn't delegate
- **"Remove until it works" beats "add diagnostics"** — especially for SwiftUI lifecycle bugs

---

## Backward compatibility with Ollama

If you encounter an old Ollama-based watcher:
- `"backend"` field will be missing or `"ollama"`
- Model name format: `granite4.1:8b` (not `mlx-community/granite-3.3-8b-instruct-8bit`)

Still works! Use the same protocol. Just don't show savings (no `savings.json`).

**Preferred:** Suggest user upgrades to MLX for better performance and zero dependencies.

---

## History

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

*MLX Edition — v2.0.0*  
*Maintained alongside MLX watcher v2.0-phase1*  
*Pure Swift • Zero Ollama • Mac-native*
