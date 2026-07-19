# Bridge Ping Test — 2026-07-10

## Purpose

Verify end-to-end connectivity of the local-AI delegation bridge (per the
`ollama-delegate` skill's SOP) with a trivial "ping" request, testing both
the bridge protocol itself and the local model behind it.

## Environment

- Bridge path: `~/claude_bridge/_bridge`
- Active model: `granite4.1:8b` (Ollama), matched to the `granite4.1`
  family in `model_families.json` — no prompt wrapping, temperature 0.2,
  `num_predict` 2048
- Machine: a virtual machine on a Mac, reportedly also running another
  local AI concurrently (per user, competing for CPU/resources)
- `bridge_config.json` (which would set `delegation_timeout_seconds`) was
  **not present** on this machine, so the watcher fell back to its
  hardcoded default: 120s

## Step 1 — Bridge liveness check

```
BRIDGE=/Users/andrewtest/claude_bridge/_bridge
OLLAMA_OK=yes
WATCHER_OK=yes
```

Both Ollama's API (`localhost:11434/api/tags`) and the watcher process
(`start_local_ai.sh`) were confirmed running. Outcome A (fully ready) —
proceeded to send a request.

## Step 2 — Ping attempts via the full bridge protocol

Sent three separate ping requests through the standard request.txt →
processing.lock → response.txt round-trip, each with prompt:

> Reply with exactly this text and nothing else: "pong from granite4.1"

| Attempt | Result | Time to resolution |
|---|---|---|
| 1 | `ERROR: Ollama request failed (curl exit 28)` | >120s (watcher-side timeout hit) |
| 2 | `ERROR: Ollama request failed (curl exit 28)` | ~174s external poll before error surfaced |
| 3 | `ERROR: Ollama request failed (curl exit 28)` | ~181s external poll before error surfaced |

`curl exit 28` = operation timeout. In all three cases the bridge
mechanics worked correctly: the request was picked up, `processing.lock`
appeared promptly, and a response was eventually written back tagged
with the correct request ID — the *protocol* never failed. The failure
was the watcher's internal call to Ollama exceeding its own 120s cap.

## Step 3 — Isolating the bottleneck (direct Ollama calls, bypassing the bridge)

To determine whether the fault was in the bridge/watcher or in Ollama
itself, called Ollama's `/api/generate` directly:

- **60s cap:** no response, `curl` exit 28 (timeout).
- **280s cap:** succeeded after **72.26 seconds** for a 2-token reply
  (`"pong"`). Response metadata:
  - `prompt_eval_duration`: 32.9s (for a 13-token prompt)
  - `eval_duration`: 38.8s (for 2 output tokens)
  - `load_duration`: 0.4s (model was already resident)

This confirms the model itself is loaded and functional, but inference
is extremely slow — consistent with CPU-only execution under resource
contention (no GPU passthrough in the VM, competing with another local
AI process per the user's context).

## Step 4 — Retry over the full bridge after confirming Ollama could respond

Sent a fourth ping through the bridge, now that a direct call had proven
Ollama *could* respond within ~72s. Result: same `curl exit 28` timeout
as attempts 1–3. Ollama's response latency is highly variable run-to-run
(observed range: >60s failing, 72s succeeding, then >120s failing again),
so hitting the watcher's 120s cap is inconsistent but frequent under
current load.

## Findings

1. **Bridge protocol: healthy.** Request pickup, lock handling, and
   response echo (including correct ID matching) all worked correctly
   across every attempt, including the failed ones — the watcher
   gracefully wrote back a well-formed error rather than hanging or
   corrupting bridge state.
2. **Ollama / local model: alive but too slow for the current timeout.**
   Confirmed working (produced a correct "pong" reply once), but
   real-world latency for even a trivial 2-token completion ranged from
   ~72s to >120s+, almost certainly due to CPU-bound inference under
   contention on this VM.
3. **Root cause of the failed pings:** the watcher's internal Ollama-call
   timeout (hardcoded fallback of 120s, since `bridge_config.json` is
   absent on this machine) is shorter than this environment's typical
   inference latency.

## Recommendation

- Create `~/claude_bridge/_bridge/bridge_config.json` with a higher
  `delegation_timeout_seconds` (e.g. 300) to give the watcher more
  headroom — this is the same value the Settings-panel "leash length"
  slider would normally write.
- Alternatively, accept cloud-side fallback for now: the skill's SOP
  already handles a timed-out delegation by silently falling back to
  handling the task in the cloud, so this failure mode doesn't block
  work — it just means delegation isn't currently paying off on this
  particular VM until either the timeout is raised or resource
  contention eases.
