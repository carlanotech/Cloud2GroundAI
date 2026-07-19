# Ollama Delegate Skill — Session Debug Report

**Date:** 2026-07-11
**Session goal (from Andrew):** exercise the `ollama-delegate` skill end-to-end
on the Material Optimization project and capture what worked / what broke, so the
other Claude project (the one that owns `start_local_ai.sh` and the bridge) can
debug it. **The code outcome does not matter this session — the skill does.**

**One-line finding:** The bridge works for exactly **one** request per watcher
run. The health-check round-trip (`PONG`) succeeded; the very next request was
written to `request.txt` and then **never processed** — `response.txt` stayed
frozen on the previous `PONG`, and `request.txt` was never consumed. Strongly
suggests the host watcher **handles one request and then exits or stops polling**
rather than looping.

---

## Environment

| Item | Value |
|---|---|
| Assistant | Cloud Claude (Cowork mode), acting as orchestrator per `ollama-delegate/SKILL.md` |
| Active model tuning loaded | `models/granite-code.md` (assumed Granite; only real tuning file present) |
| Bridge folder (host) | `/Users/andrewcarlile/claude_bridge` — connected as a **separate** mounted folder |
| Bridge path (sandbox) | `/sessions/<id>/mnt/claude_bridge/_bridge` |
| Project folder | `.../Claude Work/Material Optimization` (separate mount) |
| Ollama reachable from sandbox? | No (expected — sandbox can't reach host `localhost:11434`; protocol is file-based) |

---

## Timeline of what I did

1. **Loaded the skill**, ran the Step-1 bridge check. `BRIDGE` came back empty and
   `localhost:11434` unreachable → skill's "Outcome C." Cause: the `claude_bridge`
   folder was not mounted (only `Material Optimization` was).

2. **Connected the bridge folder.** Andrew pointed the folder picker at
   `/Users/andrewcarlile/claude_bridge`. After that
   `.../mnt/claude_bridge/_bridge` was visible. On connect the `_bridge` folder
   was **empty** (no stale `request.txt`/`response.txt`/`processing.lock`).

3. **Health-check round-trip — PASSED.**
   - Wrote `request.txt` with `# id: t-085e0ee87198`, prompt "Reply with exactly
     one word: PONG".
   - Polled; `response.txt` came back with matching id and body `PONG`.
   - **Conclusion at this point:** watcher is up, bridge is live. ✅

4. **First real delegation — NOT PROCESSED.**
   - Task: a trivial, self-contained helper `axes_equal(values, rel_tol)`
     (well within Granite's wheelhouse; prompt < 100 words; see full prompt in
     `_bridge/request.txt`, id `t-83a0d0c97c34`).
   - Wrote `request.txt` at **09:29:45**.
   - Polled repeatedly through **09:34:51** (5+ minutes). `response.txt` never
     updated — it still held the **old** `PONG` (`# id: t-085e0ee87198`,
     mtime **09:24:22**). `request.txt` was **never removed**.

### Evidence (bridge state during the hang)

```
$ ls -la _bridge/
-rw-------  762  2026-07-11_09:29:45  request.txt      <- new request, still sitting
-rw-------   25  2026-07-11_09:24:22  response.txt     <- old PONG, never overwritten

$ head -1 _bridge/request.txt
# id: t-83a0d0c97c34                                   <- the request I want answered

$ cat _bridge/response.txt
# id: t-085e0ee87198
PONG                                                   <- stale, from the health check
```

The watcher, per `BRIDGE_NOTES.md`, is supposed to (a) see `request.txt`,
(b) send it to Ollama, (c) overwrite `response.txt` with the matching id, and
(d) remove `request.txt`. Steps (b)–(d) never happened for the second request.

---

## Primary hypothesis for the host side to check

**The watcher processes a single request and then stops looping.** Things worth
checking in `start_local_ai.sh` (host side — I can't see it from the sandbox):

- Is the main body a `while true; do ... done` loop, or a one-shot that runs,
  answers one request, and returns? A one-shot launched once per terminal
  invocation would explain "first request works, nothing after."
- Does it exit (or `break`) after writing the first `response.txt`? A missing
  loop-back, or an `exit 0` on the success path, would produce exactly this.
- Did the process die after the first request? Check whether
  `pgrep -f start_local_ai.sh` still returns a PID *now* (after the PONG). If
  it's gone, the script terminated post-PONG.
- Is it watching by a mechanism that only fires once (e.g. a single `fswatch`
  event consumed, or an `inotifywait` without a loop) rather than re-arming?
- Ollama itself: if the first call warmed/loaded the model and a **second**
  `ollama run`/API call is hanging (model reload, OOM, timeout), the watcher
  could be blocked inside the Ollama call rather than exited. Check Ollama logs
  and whether `ollama ps` shows a stuck run.

**Quick host-side triage:**
1. After a fresh PONG, run `pgrep -fl start_local_ai.sh` — alive or gone?
2. Tail the watcher's stdout/stderr while I send a 2nd request — does it log
   "saw request" a second time?
3. `ollama ps` / Ollama server log during the 2nd request — stuck call?

---

## Secondary friction points (client/orchestrator side — lower priority)

These didn't cause the failure but are worth noting for the skill's robustness:

1. **90 s poll vs. 45 s bash cap.** The skill's Step-4 template polls up to 90 s
   in a single shell command. This Cowork sandbox caps a single `bash` call at
   **45 s**, so the skill's poll loop times out mid-wait and the shell reports a
   failure even though the request was written fine. Mitigation I used: split
   "write request" and "poll response" into separate shell calls and poll in
   ≤40 s chunks. The skill's SPEC/SKILL could recommend chunked polling for
   sandboxes with a per-command timeout.

2. **Sandbox can't delete bridge files** (already documented as issue #4 in
   `BRIDGE_NOTES.md`). Confirmed still true — cleanup must remain the watcher's
   job; the orchestrator only writes `request.txt` and polls by id.

3. **My own id-matching bug (my mistake, not the skill's).** In one poll attempt
   I reconstructed the id with `sed 's/# id: //'` and then re-prepended `t-`,
   producing `t-t-83a0d0c97c34`, which of course never matched. Fixed by
   comparing against the exact first line. Flagging only so it's not mistaken for
   a watcher symptom.

4. **Bridge not auto-discovered.** As in the 2026-07-08 notes, the `claude_bridge`
   folder must be explicitly connected each session; it is not found just because
   it exists on the Mac. Not a bug — just the recurring first-step friction.

---

## What this means for the skill test

- **Protocol layer (file handoff + id echo): working.** The PONG proves the
  request/response/id-match path is correct end to end.
- **Watcher loop / lifecycle: the suspect.** Single-request-then-stop is the
  behavior to reproduce and fix host-side.
- **Orchestrator (me): fine**, modulo the 45 s poll-chunking adaptation, which is
  worth folding into the skill for sandboxed clients.

## Reproduction for the host-side debugger

1. Start `start_local_ai.sh`.
2. From the bridge folder, drop a `request.txt`:
   ```
   # id: t-test-001
   Reply with exactly one word: PONG
   ```
   → expect `response.txt` with `# id: t-test-001` / `PONG`. (Works.)
3. Without restarting the watcher, drop a **second** `request.txt`:
   ```
   # id: t-test-002
   Reply with exactly one word: PONG
   ```
   → **observed:** `response.txt` stays on `t-test-001`; `request.txt` for
   `t-test-002` is never consumed. Watch whether the watcher logs a second
   "saw request" event and whether its PID is still alive.

---

*Left in place for the host-side debugger:* `_bridge/request.txt` still holds the
unprocessed `t-83a0d0c97c34` request as live evidence. Sending a fresh request
(or restarting the watcher) will overwrite it.
