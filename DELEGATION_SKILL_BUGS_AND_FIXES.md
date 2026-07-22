# Delegation Skill Test Failures — Bug Analysis & Fix Plan

**Date:** 2026-07-19
**Status:** RESOLVED — all three bugs closed as of skill/SKILL-MLX.md v2.1.0–v2.3.0 (2026-07-19), reconciled 2026-07-20. Kept as historical record of the original investigation; not an active tracker. Also relocated out of Cloud2Ground/Cloud2Ground/ (the Xcode app's source/resources folder — Xcode's synchronized-group build phase would otherwise bundle this planning doc into the shipped app) to the outer repo root, alongside the other dated handoff docs.
**Context:** Testing the mlx-delegate skill (SKILL_MLX_v2.md) revealed three critical bugs preventing any delegation from working.

## Resolution summary (2026-07-20)

- **Bug #1 (missing `bridge_delegate`)** — CLOSED. The script exists at
  `skill/bridge_delegate` (confirmed present, byte-identical between the
  outer and inner-repo bundled copies as of this reconciliation) and has
  been the skill's documented "only supported way to drive the bridge"
  since v0.4.0 (2026-07-13).
- **Bug #2 (status schema mismatch)** — CLOSED, but via **Option B**
  ("migrate entirely to MLX"), not this doc's recommended Option A
  (dual-schema support). SKILL-MLX.md v2.1.0 (2026-07-18) dropped Ollama
  schema support entirely: `bridge_delegate`'s `cmd_status()` only
  understands `status`/`last_heartbeat` now. This matches the broader
  2026-07-19 decision to retire Ollama from the delegation bridge
  entirely (see PROJECT_STATE doc) rather than support both backends
  long-term. Note: a *different* last_seen/last_heartbeat field-name bug
  was found and fixed 2026-07-20 in `BridgeSmokeTest.swift` — the app's
  own Swift-side heartbeat probe (separate from `bridge_delegate`'s
  bash-side one this doc is about) had regressed to reading the old
  `last_seen` field name, silently degrading its liveness check.
- **Bug #3 (garbled output + timeouts)** — CLOSED. Garbled
  Python/JS-hybrid output was root-caused to the 2B model specifically
  and fixed by defaulting to 8B (SKILL-MLX.md v2.1.0). The false-timeout
  symptom (154s report against a 120s budget) was fixed by
  `bridge_delegate`'s `cmd_poll()` no longer firing TIMEOUT purely on
  elapsed time — it now checks whether `processing.lock` is still held
  and reports WAITING instead (SKILL-MLX.md v2.3.0, 2026-07-19).

The rest of this document is preserved as-written for the original
investigation's detail (repro steps, schema tables, fix-plan phases) —
not updated line-by-line to match the resolutions above.

---

## Summary

The delegation skill failed end-to-end testing with three distinct failures:

1. ❌ **Missing `bridge_delegate` script** — packaging bug, blocking
2. ❌ **Status schema mismatch** — runtime bug, causes false DEAD reports
3. ❌ **Garbled output + timeouts** — reliability bug, degrades quality

All three must be fixed before the skill can be used in production.

---

## Bug #1: Missing `bridge_delegate` Script (BLOCKING)

### Problem

The skill documentation (`SKILL_MLX_v2.md`) explicitly states:

> "`bridge_delegate` (shipped alongside this file) is the **only** supported way to drive the bridge. Do **not** hand-roll `request.txt` / `response.txt` / `consumed.txt` handling."

The skill references this script throughout:

```bash
bash "$BD" status
bash "$BD" send
bash "$BD" poll
bash "$BD" run
```

**But this script does not exist anywhere in the project.**

### Impact

**Blocking.** No one can use the skill without this helper. Every delegation attempt fails immediately.

### Root Cause

The skill document is aspirational documentation for a future state. The actual tooling was never built.

### Fix Required

Write the missing `bridge_delegate` helper script (~150-200 lines of bash) that implements:

- `status` — Check watcher health, parse status.json (see Bug #2 for schema requirements)
- `send` — Write request.txt with UUID header, echo the UUID
- `poll` — Wait for response.txt with matching UUID, handle timeout
- `run` — Combined send + poll (convenience wrapper)

### Expected Behavior

**`bash bridge_delegate status`**
- Read `~/claude_bridge/_bridge/status.json`
- Parse schema (see Bug #2 for dual-schema requirement)
- Check heartbeat freshness (< 10s old = ALIVE, else DEAD)
- Output format:
  - `ALIVE model=<name> backend=<mlx-swift|ollama> ...` (exit 0)
  - `BUSY model=<name> ...` (exit 0)
  - `DEAD model=<name> last_seen=<Xs ago>` (exit 3)
  - `NO-HEARTBEAT bridge=<path>` (exit 4)
  - `NO-BRIDGE` (exit 4)

**`bash bridge_delegate send`**
- Read prompt from stdin
- Generate UUID: `REQ_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')`
- Write `~/claude_bridge/_bridge/request.txt`:
  ```
  # id: <uuid>
  <prompt text>
  ```
- Echo UUID to stdout
- Exit 0

**`bash bridge_delegate poll <uuid>`**
- Read timeout from `~/claude_bridge/_bridge/bridge_config.json` (default 120s)
- Wait for `~/claude_bridge/_bridge/response.txt` with matching `# id: <uuid>` header
- Every 1s check:
  - Does response.txt exist with matching ID? → Output response body (strip id line), write `consumed.txt`, output `=== DONE ===`, exit 0
  - Has timeout elapsed? → Output `=== TIMEOUT after Xs ===`, exit 1
  - Is watcher still alive (re-check status)? → If dead, output `=== WATCHER-DOWN ===`, exit 2
- While waiting, output `=== WAITING ... ===` every 10s

**`bash bridge_delegate run`**
- Read prompt from stdin
- Call `send`, capture UUID
- Call `poll <uuid>`
- Pass through exit code

### Install Location

The skill expects to find `bridge_delegate` in one of these locations:

```bash
/sessions/*/mnt/.claude/skills/mlx-delegate/bridge_delegate
$HOME/.claude/skills/mlx-delegate/bridge_delegate
/var/folders/*/T/claude-hostloop-plugins/*/skills/mlx-delegate/bridge_delegate
```

**Recommended:** Create `$HOME/.claude/skills/mlx-delegate/bridge_delegate` as the default.

---

## Bug #2: Status Schema Mismatch (CRITICAL RUNTIME BUG)

### Problem

The skill documentation claims the MLX watcher writes this `status.json` schema:

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

But the **actual Ollama watcher** (`start_local_ai.sh` lines 220-230) writes this schema:

```json
{
  "model": "granite4.1:8b",
  "watcher_version": "0.2.10",
  "pid": 12345,
  "seq": 42,
  "last_seen": 1784432073,
  "state": "idle"
}
```

### Key Differences

| Field | MLX Schema | Ollama Schema |
|-------|------------|---------------|
| Status indicator | `"status": "ready"` | `"state": "idle"` |
| Heartbeat timestamp | `"last_heartbeat": <unix>` | `"last_seen": <unix>` |
| Backend identifier | `"backend": "mlx-swift"` | *(missing)* |
| Version field | `"version": "2.0-phase1"` | `"watcher_version": "0.2.10"` |
| Sequence counter | *(missing)* | `"seq": 42` |
| Process ID | *(missing)* | `"pid": 12345` |

### Impact

The `bridge_delegate` status parser (once written) will fail to recognize one schema or the other, causing:

- **False DEAD status** when a working watcher is running
- **Skill wrongly routes to cloud** even when local delegation is available
- **Silent failures** — delegation never happens, no error message

### Root Cause

There are **two watchers** in this codebase:

1. **`start_local_ai.sh`** — The Ollama watcher (v0.2.10, bash + Perl + Ollama)
   - Produces `seq`/`state`/`last_seen` schema
   - Located at `~/Library/Application Support/claude_bridge/start_local_ai.sh`
   - Currently installed and running

2. **`watch_mlx_v2.sh`** — The MLX watcher (v2.0-phase1, bash + c2g-mlx binary)
   - Should produce `status`/`last_heartbeat` schema (per PHASE1_TOOLS.md)
   - Located at `mlx_poc/watch_mlx_v2.sh`
   - **Not yet deployed** to replace the Ollama watcher

The skill doc is written for the **MLX watcher**, but tests ran against the **Ollama watcher**, explaining the schema mismatch.

### Fix Required

**Option A: Dual-schema support (RECOMMENDED)**

Make `bridge_delegate` handle **both** schemas during the migration period:

```bash
# Pseudo-code for status subcommand
if jq -e '.seq' "$STATUS_FILE" >/dev/null 2>&1; then
    # Ollama schema detected
    SEQ=$(jq -r '.seq' "$STATUS_FILE")
    STATE=$(jq -r '.state' "$STATUS_FILE")
    LAST_SEEN=$(jq -r '.last_seen' "$STATUS_FILE")
    MODEL=$(jq -r '.model' "$STATUS_FILE")
    BACKEND="ollama"
    
    # Check if seq is advancing (alive check)
    # Sample twice, 2s apart, verify seq incremented
    
elif jq -e '.status' "$STATUS_FILE" >/dev/null 2>&1; then
    # MLX schema detected
    STATUS=$(jq -r '.status' "$STATUS_FILE")
    LAST_HB=$(jq -r '.last_heartbeat' "$STATUS_FILE")
    MODEL=$(jq -r '.model' "$STATUS_FILE")
    BACKEND=$(jq -r '.backend // "mlx-swift"' "$STATUS_FILE")
    
    # Check if last_heartbeat is fresh (< 10s old)
    NOW=$(date +%s)
    AGE=$((NOW - LAST_HB))
    
else
    echo "NO-HEARTBEAT bridge=$BRIDGE_DIR"
    exit 4
fi
```

**Option B: Migrate entirely to MLX**

Deprecate the Ollama watcher, deploy `watch_mlx_v2.sh` as the only supported backend. Update `bridge_delegate` to expect only the MLX schema.

**Option C: Update skill doc to match Ollama**

Defeats the purpose of the MLX migration. Not recommended.

**Recommendation:** Option A. Support both schemas until MLX watcher is proven stable in production, then deprecate Ollama schema in v3.0.

### Heartbeat Freshness Logic

**Ollama schema (seq-based):**
- Sample `seq` at T0, wait 2s, sample again at T2
- If `seq` advanced (T2 > T0) → ALIVE
- If `seq` unchanged → DEAD (watcher loop frozen)
- If `state == "processing"` → BUSY

**MLX schema (timestamp-based):**
- Read `last_heartbeat`, compare to current time
- If age < 10s → ALIVE
- If age >= 10s → DEAD (watcher crashed or network partition)
- If `status == "processing"` → BUSY

---

## Bug #3: Garbled Output + Timeout (RELIABILITY)

### Problem

Two trivial test requests both failed:

**Test 1: "Sum 1 to 20"**
- Expected: Simple loop or formula, completes in <10s
- Actual: **154s timeout** (budget was 120s)
- Outcome: No response, skill falls back to cloud

**Test 2: (Unknown prompt)**
- Expected: Valid code output
- Actual: **Garbled Python/JavaScript hybrid syntax**
- Outcome: Not shippable verbatim, defeats economic argument

### Impact

The skill's economic argument assumes:

> "As long as local output is right or partially right most of the time, delegation wins."

**Test results:**
- 50% timeout (unusable)
- 50% garbled (requires full rewrite)
- 0% usable output

This destroys the value proposition. If local delegation is this unreliable, it's worse than just using cloud.

### Possible Root Causes

**Timeout (154s for trivial prompt):**
- Model didn't load properly (infinite hang on first request)
- `curl --max-time` not working (timeout not enforced)
- Model generating forever without stop tokens
- Ollama service deadlocked or crashed mid-request

**Garbled output (Python/JS syntax mix):**
- Wrong prompt template for the model being used
- Post-processing stripper too aggressive (or not aggressive enough)
- Model confusion from mixed training data
- Stop tokens misconfigured (model kept generating past answer)

### Fix Required

**Priority 1: Reproduce and debug**

Need raw data from a failed request:

1. **Which watcher is actually running?**
   ```bash
   ps aux | grep -E 'start_local_ai|watch_mlx'
   ```

2. **Which model is loaded?**
   ```bash
   cat ~/claude_bridge/_bridge/status.json
   # Or for Ollama:
   ollama list
   ```

3. **Inspect raw response.txt** before post-processing:
   ```bash
   # Before the watcher's preamble-stripper runs
   cat ~/claude_bridge/_bridge/.resp.$$
   ```

4. **Check model_families.json** is being read:
   ```bash
   cat ~/Library/Application\ Support/claude_bridge/model_families.json
   ```

5. **Test with minimal prompt:**
   ```bash
   echo "print hello" | bridge_delegate run
   ```
   Should complete in <10s with simple, correct code.

**Priority 2: Verify Ollama watcher config**

The Ollama watcher (`start_local_ai.sh`) uses sophisticated model-specific tuning:

- **Prompt wrapping:** IBM Q/A template for `granite-code`, plain for `granite4.1`
- **Ollama options:** temperature, num_predict, stop sequences
- **Post-processing:** Markdown fence stripping, preamble removal

These are driven by `model_families.json`. If this file is missing or malformed, the watcher falls back to neutral defaults, which may not work well for Granite models.

**Verify:**
```bash
ls -l ~/Library/Application\ Support/claude_bridge/model_families.json
cat ~/Library/Application\ Support/claude_bridge/model_families.json
```

**Priority 3: Test with MLX watcher**

The MLX watcher (`watch_mlx_v2.sh`) may have better reliability since it:
- Uses native Swift inference (no Ollama dependency)
- Has simpler prompt handling (less post-processing)
- Runs directly against MLX-Swift's ChatSession API

**Deploy and test:**
```bash
cd mlx_poc
./watch_mlx_v2.sh
# In another terminal:
./bridge_test.sh "Write a Python function to sum 1 to 20"
```

Compare quality and latency to Ollama watcher.

---

## Fix Plan Summary

### Phase 1: Unblock Delegation (Immediate)

**Task 1.1: Write `bridge_delegate` script**
- [ ] Implement `status` subcommand with dual-schema support (Ollama + MLX)
- [ ] Implement `send` subcommand (UUID generation, request.txt write)
- [ ] Implement `poll` subcommand (timeout handling, response.txt read, consumed.txt ack)
- [ ] Implement `run` subcommand (wrapper for send + poll)
- [ ] Install to `$HOME/.claude/skills/mlx-delegate/bridge_delegate`
- [ ] Make executable: `chmod +x bridge_delegate`

**Task 1.2: Test with Ollama watcher**
- [ ] Verify `status` correctly detects Ollama watcher (seq-based heartbeat)
- [ ] Run trivial delegation: `echo "print hello" | bridge_delegate run`
- [ ] Verify response completes in <10s with correct output

**Task 1.3: Document what was shipped**
- [ ] Update SKILL_MLX_v2.md to note `bridge_delegate` is now available
- [ ] Add installation instructions to README
- [ ] Document dual-schema support period (Ollama + MLX)

### Phase 2: Fix Reliability (Next)

**Task 2.1: Debug timeout issue**
- [ ] Reproduce "sum 1 to 20" timeout
- [ ] Capture raw request.txt and response.txt
- [ ] Check Ollama logs for errors
- [ ] Verify `bridge_config.json` timeout value is being read
- [ ] Test if issue is model-specific (try different model)

**Task 2.2: Debug garbled output**
- [ ] Reproduce garbled Python/JS output
- [ ] Inspect raw response before post-processing
- [ ] Verify `model_families.json` is being loaded
- [ ] Check if prompt template is correct for model
- [ ] Test if issue is preamble-stripper being too aggressive

**Task 2.3: Benchmark quality**
- [ ] Run 10 trivial delegations (helper functions, one-liners)
- [ ] Measure: success rate, average latency, output quality
- [ ] Compare Ollama watcher vs. MLX watcher
- [ ] Establish baseline for acceptable performance

### Phase 3: Migrate to MLX (Future)

**Task 3.1: Deploy MLX watcher**
- [ ] Install `watch_mlx_v2.sh` to `~/Library/Application Support/claude_bridge/`
- [ ] Update LaunchAgent plist to use MLX watcher instead of Ollama
- [ ] Verify MLX watcher writes correct status.json schema
- [ ] Test savings tracking (savings.json generation)

**Task 3.2: Dogfood for 1-2 weeks**
- [ ] Use MLX watcher for all delegations
- [ ] Track reliability, quality, latency
- [ ] Compare to Ollama watcher baseline
- [ ] Fix any MLX-specific bugs discovered

**Task 3.3: Deprecate Ollama support**
- [ ] Remove Ollama schema support from `bridge_delegate`
- [ ] Update skill doc to MLX-only
- [ ] Archive `start_local_ai.sh` as legacy
- [ ] Release as v3.0

---

## Testing Checklist

Before declaring delegation skill production-ready:

### Basic Functionality
- [ ] `bridge_delegate status` correctly reports ALIVE/BUSY/DEAD for Ollama watcher
- [ ] `bridge_delegate status` correctly reports ALIVE/BUSY/DEAD for MLX watcher
- [ ] `bridge_delegate send` writes request.txt with valid UUID
- [ ] `bridge_delegate poll` waits for response and acks with consumed.txt
- [ ] `bridge_delegate run` completes full round-trip in <10s for trivial prompt

### Edge Cases
- [ ] Status reports NO-BRIDGE when ~/claude_bridge missing
- [ ] Status reports NO-HEARTBEAT when status.json missing
- [ ] Status reports DEAD when watcher crashed (heartbeat stale)
- [ ] Poll reports TIMEOUT when watcher doesn't respond within budget
- [ ] Poll reports WATCHER-DOWN when watcher dies mid-request

### Quality & Reliability
- [ ] 10 trivial delegations: ≥80% success rate (correct output, no timeout)
- [ ] Average latency <15s for 2B model, <20s for 8B model
- [ ] No garbled output (mixed syntax, truncated code)
- [ ] Savings ledger tracks tokens accurately
- [ ] Cost savings ≥5× vs. cloud (when delegation succeeds)

### Integration
- [ ] Skill can locate `bridge_delegate` in all documented paths
- [ ] Claude Code can successfully delegate via skill
- [ ] Status panel shows correct watcher state
- [ ] GUI preferences write valid `bridge_config.json`

---

## Dependencies

### For `bridge_delegate`:
- `bash` (macOS default)
- `jq` (JSON parsing) — install via `brew install jq`
- `uuidgen` (macOS default)

### For Ollama watcher:
- `ollama` (Homebrew or GUI .app)
- `perl` (macOS default)
- JSON::PP (ships with macOS Perl)

### For MLX watcher:
- `c2g-mlx` binary (built from mlx_poc/c2g-mlx/)
- `mlx.metallib` (Metal shaders, built via BUILD_METALLIB.sh)
- No external dependencies beyond macOS SDK

---

## Success Criteria

The delegation skill is production-ready when:

1. ✅ `bridge_delegate` exists and works with both Ollama and MLX watchers
2. ✅ Trivial delegations succeed ≥80% of the time with correct output
3. ✅ Average latency is acceptable (<20s for 8B model)
4. ✅ No timeouts on simple prompts (≤50 words)
5. ✅ No garbled output (syntax errors, mixed languages)
6. ✅ Savings tracking is accurate (matches actual token usage)
7. ✅ Documentation matches reality (no aspirational claims)
8. ✅ End-to-end testing passes (Claude Code → skill → watcher → model → response)

---

## Open Questions

1. **Which watcher was actually running during the failed test?** (Ollama or MLX?)
2. **What were the exact prompts that timed out / produced garbled output?**
3. **Does `model_families.json` exist and is it valid?**
4. **Should we prioritize fixing Ollama watcher or migrating to MLX?**
5. **What's the acceptable failure rate for delegation?** (10%? 20%? 5%?)

---

## References

- **Skill doc:** `SKILL_MLX_v2.md`
- **Ollama watcher:** `start_local_ai.sh` (v0.2.10)
- **MLX watcher:** `mlx_poc/watch_mlx_v2.sh` (v2.0-phase1)
- **MLX docs:** `mlx_poc/PHASE1_TOOLS.md`
- **Bridge protocol:** `start_local_ai.sh` lines 1-50 (comments)
- **Status probes:** `BridgeProbe.swift` lines 164-180 (heartbeat logic)

---

**Next Action:** Write `bridge_delegate` script with dual-schema support (see Phase 1, Task 1.1).

---

*Document created: 2026-07-19*  
*Author: Claude (Anthropic) + Andrew Carlile*  
*Status: Ready for implementation*
