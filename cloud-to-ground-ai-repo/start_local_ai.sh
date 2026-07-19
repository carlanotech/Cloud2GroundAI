#!/bin/bash
# start_local_ai.sh — Local AI delegation bridge for Claude/Cowork
#
# v0.2 protocol changes (2026-06-20):
#   1. Race fix: when consumed.txt is observed, response.txt and consumed.txt
#      are removed BEFORE the loop checks for the next request.txt. Eliminates
#      the window where a new request could be answered with the previous
#      response.
#   2. Request IDs: an optional first line of request.txt of the form
#      `# id: <uuid>` is preserved and echoed back as the first line of
#      response.txt, also as `# id: <uuid>`. Requests without an id line
#      are still accepted (backward compatible). The skill side is what
#      enforces id matching; the watcher just round-trips the field.
#
# v0.2.1 tuning changes (2026-06-20, afternoon):
#   3. Model-specific prompt wrapping. For Granite Code models, the prompt
#      is wrapped in the IBM-recommended "Question:/Answer:" template per
#      https://www.ibm.com/docs/en/watsonx/saas?topic=models-prompting-granite-code
#      Other models pass through unchanged.
#   4. Ollama generation options pinned to IBM-recommended values for
#      Granite Code: temperature=0 (greedy), repeat_penalty=1.05,
#      num_predict=900, stop=["<|endoftext|>"]. Same payload for any
#      model — Ollama ignores stop sequences a model doesn't emit.
#
# v0.2.2 tuning changes (2026-06-20, evening):
#   5. Output post-processing strips markdown fences and a short natural-
#      language preamble before the first code-keyword line, since the IBM
#      Q/A template encourages Granite to answer in prose first.
#
# v0.2.3 tuning changes (2026-06-22):
#   6. Expected-start anchoring. An optional "# start: <token>" request line
#      (after the optional id line) declares the token the answer should
#      begin with; if absent, a "Start with `X`" instruction in the prompt
#      is auto-detected. The preamble stripper now anchors on this token in
#      addition to the code keywords, allowing leading indentation. This
#      fixes pattern-completion output (e.g. `    "pump_2": {...}`) whose
#      first line is an indented quoted key the keyword-only anchor missed.
#      Backward compatible: requests without the line behave as before.
#
# Split-location design (unchanged):
#   - Watcher script:  ~/Library/Application Support/claude_bridge/start_local_ai.sh
#     (out of ~/Documents/ so the LaunchAgent can run it without macOS TCC
#      blocking launchd-spawned bash.)
#   - Bridge folder:   ~/Documents/claude_bridge/_bridge/
#     (Cowork refuses to mount ~/Library/Application Support/ — protected
#      location — but it can mount ~/Documents/claude_bridge, so request and
#      response files live there.)
#
# Why Python does all file I/O:
#   launchd-spawned bash lacks TCC write access to ~/Documents — every rm and
#   touch fails with "Operation not permitted". Homebrew Python retains the
#   Documents grant from prior interactive use, so all file operations go
#   through Python instead of bash.
#
# Manual run:  bash "$HOME/Library/Application Support/claude_bridge/start_local_ai.sh"
# Auto-start:  installed via install_autostart.sh
#
# Requirements: brew install ollama

MODEL="granite-code:8b"
BRIDGE="$HOME/Documents/claude_bridge/_bridge"

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

# ── Ensure Ollama is running ──────────────────────────────────────────────────
if ! pgrep -x "ollama" > /dev/null; then
    echo "→ Starting Ollama..."
    ollama serve &>/dev/null &
    sleep 3
else
    echo "✓ Ollama is already running"
fi

if ! ollama list | grep -q "$MODEL"; then
    echo "→ Pulling $MODEL (one-time)..."
    ollama pull "$MODEL"
fi
echo "✓ Model $MODEL is ready"

# ── Set up bridge folder ──────────────────────────────────────────────────────
mkdir -p "$BRIDGE"

# Startup cleanup via Python (bash rm fails under launchd TCC restrictions)
python3 - "$BRIDGE" << 'STARTUP_PY'
import sys, os, glob
bridge = sys.argv[1]
for name in ["request.txt", "response.txt", "consumed.txt"]:
    try:
        os.remove(os.path.join(bridge, name))
    except FileNotFoundError:
        pass
    except Exception as e:
        print(f"  startup cleanup warning ({name}): {e}")
for lockfile in glob.glob(os.path.join(bridge, "*.lock")):
    try:
        os.remove(lockfile)
    except Exception as e:
        print(f"  startup lock cleanup warning: {e}")
STARTUP_PY

echo "✓ Bridge ready at $BRIDGE"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Local AI delegation is ACTIVE"
echo "  Model: $MODEL  |  Protocol: v0.2.3 (IDs + IBM template + start-anchor)"
echo "  You can minimize this window — leave it running."
echo "  Press Ctrl+C to shut down."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ── Cleanup on exit ───────────────────────────────────────────────────────────
trap 'echo ""; echo "→ Shutting down...";
python3 - "$BRIDGE" << TRAP_PY
import sys, os, glob
bridge = sys.argv[1]
for f in glob.glob(os.path.join(bridge, "*")):
    try: os.remove(f)
    except: pass
TRAP_PY
echo "✓ Done."' EXIT INT TERM

# ── Main loop ─────────────────────────────────────────────────────────────────
loop_count=0

while true; do
    loop_count=$(( loop_count + 1 ))

    # ── Race-fix: cleanup pass FIRST, before looking at request.txt ───────────
    # If the client has acknowledged the previous response via consumed.txt,
    # remove response.txt and consumed.txt synchronously, in this same tick,
    # so they cannot leak into the next request cycle.
    python3 - "$BRIDGE" << 'CLEANUP_PY' 2>/dev/null
import sys, os
bridge = sys.argv[1]
consumed = os.path.join(bridge, "consumed.txt")
response = os.path.join(bridge, "response.txt")
if os.path.exists(consumed):
    for f in [response, consumed]:
        try: os.remove(f)
        except FileNotFoundError: pass
        except Exception as e: print(f"  cleanup warning ({f}): {e}")
CLEANUP_PY

    # Every 60 loops (~30s): check for stale locks via Python
    if [ $(( loop_count % 60 )) -eq 0 ]; then
        python3 - "$BRIDGE" << 'STALE_PY' 2>/dev/null
import sys, os, glob, time
bridge = sys.argv[1]
for lockfile in glob.glob(os.path.join(bridge, "*.lock")):
    try:
        if time.time() - os.path.getmtime(lockfile) > 300:
            os.remove(lockfile)
            print(f"  ✓ Cleaned stale lock: {os.path.basename(lockfile)}")
    except Exception:
        pass
STALE_PY
    fi

    # ── Process a new request ────────────────────────────────────────────────
    # Only if a request is present AND no stale response/consumed remain.
    # The cleanup pass above guarantees those are gone when consumed was set,
    # so the most common race ("client sets consumed and writes a new request
    # before the watcher cleans up") is closed.
    if [ -f "$BRIDGE/request.txt" ] \
       && [ ! -f "$BRIDGE/processing.lock" ] \
       && [ ! -f "$BRIDGE/response.txt" ]; then

        echo "→ Task received — running local inference..."

        python3 - "$BRIDGE" "$MODEL" << 'INFERENCE_PY'
import sys, json, re, urllib.request, os, glob, time

bridge, model = sys.argv[1], sys.argv[2]

# Clean up any stale lock files (safety net before taking lock)
for lockfile in glob.glob(os.path.join(bridge, "*.lock")):
    try:
        if time.time() - os.path.getmtime(lockfile) > 300:
            os.remove(lockfile)
    except Exception:
        pass

# Take the processing lock (write PID so crashes are diagnosable)
lock = os.path.join(bridge, "processing.lock")
try:
    with open(lock, "w") as f:
        f.write(str(os.getpid()))
except Exception as e:
    print(f"  ✗ Could not create lock: {e}")

# Read the request
request_file = os.path.join(bridge, "request.txt")
try:
    with open(request_file) as f:
        raw = f.read()
except Exception as e:
    print(f"  ✗ Could not read request: {e}")
    for f in [lock, request_file]:
        try: os.remove(f)
        except: pass
    sys.exit(1)

# Extract request ID if present.
# Convention: first line of the form "# id: <token>" — preserved and echoed.
# Any first line not matching this regex is treated as part of the prompt.
request_id = None
prompt = raw
m = re.match(r'^# id:\s*([A-Za-z0-9_\-]+)\s*\n', prompt)
if m:
    request_id = m.group(1)
    prompt = prompt[m.end():]

# Optional expected-start token (v0.2.3). Convention: a line of the form
# "# start: <token>" immediately after the optional id line. It names the
# token the answer should begin with (e.g. `"pump_` for a dict pattern,
# `import ` for a function). The preamble stripper below uses it to clean
# outputs whose first real line is NOT a code keyword — most importantly
# pattern-completion output (indented quoted keys), which the keyword-only
# anchor could never catch. Backslash-quoting/backticks around the token
# are tolerated. Backward compatible: absent line => behave as before.
explicit_start = None
sm = re.match(r'^# start:\s*(.+?)\s*\n', prompt)
if sm:
    explicit_start = sm.group(1)
    if len(explicit_start) >= 2 and explicit_start[0] == '`' and explicit_start[-1] == '`':
        explicit_start = explicit_start[1:-1]
    prompt = prompt[sm.end():]

prompt = prompt.strip()

# If no explicit start token was provided, auto-detect a "Start with `X`"
# instruction in the prompt itself. The documented Granite prompt patterns
# all end with such a line, so this gives the stripper an anchor for free,
# with zero changes required on the skill side.
if not explicit_start:
    auto = re.search(r'[Ss]tart with\s*`([^`]+)`', prompt)
    if auto:
        explicit_start = auto.group(1)

# IBM-recommended prompt template for Granite Code models.
# See: https://www.ibm.com/docs/en/watsonx/saas?topic=models-prompting-granite-code
# The "Question:/Answer:" structure matches the format Granite was
# instruction-tuned against. Wrapping here (watcher-side) means the client
# can keep sending free-form prompts; the watcher adapts them per-model.
# Note: this wrapping is tuned for Granite Code. If/when we add a watcher
# for a non-Granite model, the wrapping needs to move into a per-model
# strategy (see models/<name>.md). For now, "MODEL=granite-*" → IBM template;
# any other model → raw prompt.
if model.startswith("granite"):
    wrapped_prompt = f"Question:\n{prompt}\n\nAnswer:\n\n"
else:
    wrapped_prompt = prompt

# IBM-recommended Ollama options for Granite Code models:
#   greedy decoding (temperature=0), repetition penalty 1.05, stop on
#   the model's <|endoftext|> token, allow up to 900 output tokens.
ollama_options = {
    "temperature": 0.0,
    "repeat_penalty": 1.05,
    "num_predict": 900,
    "stop": ["<|endoftext|>"],
}

# Run inference
payload = json.dumps({
    "model": model,
    "prompt": wrapped_prompt,
    "stream": False,
    "options": ollama_options,
}).encode()
req = urllib.request.Request(
    "http://localhost:11434/api/generate",
    data=payload,
    headers={"Content-Type": "application/json"},
)
try:
    with urllib.request.urlopen(req, timeout=120) as resp:
        result = json.load(resp)["response"]
    result = re.sub(r'^```[a-zA-Z]*\n?', '', result, flags=re.MULTILINE)
    result = re.sub(r'\n?```\s*$', '', result, flags=re.MULTILINE)
    result = result.strip()
    # Strip natural-language preamble before the first real answer line.
    # Granite's IBM Q/A template often produces "Here's the code:" or
    # "Below is the function:" before the actual answer. We find the first
    # line that looks like the start of the answer and drop everything above
    # it. Two kinds of anchor, whichever matches earliest:
    #   1. A code keyword at the start of a line (import/def/class/...).
    #   2. The request's expected-start token (explicit `# start:` line or a
    #      `Start with `X`` instruction), allowing leading indentation. This
    #      is what catches pattern-completion output like `    "pump_2": ...`,
    #      whose first line is an indented quoted key, not a code keyword.
    # If neither is found, leave result unchanged.
    code_anchor_re = re.compile(
        r'^(import |from |def |class |#!/|@|async def |if __name__)',
        re.MULTILINE,
    )
    candidate_starts = []
    cm = code_anchor_re.search(result)
    if cm is not None:
        candidate_starts.append(cm.start())
    if explicit_start:
        # Anchor on the declared token at the start of a line, tolerating
        # indentation so the matched line keeps its leading whitespace.
        em = re.search(r'^[ \t]*' + re.escape(explicit_start), result, re.MULTILINE)
        if em is not None:
            candidate_starts.append(em.start())
    if candidate_starts:
        anchor_start = min(candidate_starts)
        if anchor_start > 0:
            preamble = result[:anchor_start].strip()
            if preamble:
                # Only strip if the preamble doesn't itself contain a code
                # block — protects against false positives where the first
                # anchor token is inside an example string or docstring.
                if not re.search(r'\n\s{4,}', preamble) and len(preamble) < 400:
                    result = result[anchor_start:].rstrip()
    print(f"  ✓ Done ({len(result)} chars) id={request_id or 'none'}")
except Exception as e:
    result = f"ERROR: {e}"
    print(f"  ✗ Inference error: {e}")

# Write response with id echoed back on first line if it was provided.
response_file = os.path.join(bridge, "response.txt")
try:
    with open(response_file, "w") as f:
        if request_id is not None:
            f.write(f"# id: {request_id}\n")
        f.write(result)
except Exception as e:
    print(f"  ✗ Could not write response: {e}")

# Remove request and lock
for f in [request_file, lock]:
    try: os.remove(f)
    except: pass
INFERENCE_PY

    fi

    sleep 0.5
done
