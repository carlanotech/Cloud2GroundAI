# Phase 1 Tools & Updates

**Version:** 2.0-phase1  
**Status:** In Progress  
**Goal:** Feature parity with Ollama watcher

---

## New Tools

### 1. `granite_helper.sh` — Quick CLI Helper

Ask Granite one-off questions to help you code:

```bash
./granite_helper.sh "How do I count tokens in Swift using MLX?"

# Or from a file
./granite_helper.sh < my_question.txt

# Or pipe
cat complex_question.md | ./granite_helper.sh
```

**Use this when:** You need a quick answer while coding

### 2. `granite_repl.sh` — Interactive REPL

Interactive session for exploring ideas:

```bash
./granite_repl.sh

granite> How do I write JSON in Swift?
[answer appears]

granite> Show me an example with error handling
[answer appears]

granite> exit
```

**Use this when:** You want to have a back-and-forth conversation

### 3. `watch_mlx_v2.sh` — Phase 1 Watcher

Updated watcher with new features:

**New Features:**
- ✅ **Heartbeat**: Writes `status.json` every 5 seconds
- ✅ **Token counting**: Tracks input/output tokens (approximate)
- ✅ **Savings ledger**: Tracks cost saved vs. Claude API
- ✅ **Configurable temperature**: Set via `C2G_MLX_TEMPERATURE`
- ✅ **Stale lock cleanup**: Cleans dead locks on startup
- ✅ **Markdown fence stripping**: Removes ```code``` fences (optional)

**Usage:**
```bash
./watch_mlx_v2.sh
```

**Configuration:**
```bash
# Temperature (0.0-1.0, default 0.2)
export C2G_MLX_TEMPERATURE=0.2

# Disable fence stripping
export C2G_STRIP_FENCES=false

# Custom model
export C2G_MLX_MODEL=mlx-community/granite-3.3-8b-instruct-8bit
```

---

## Setup

### Make Scripts Executable

```bash
cd ~/Library/CloudStorage/ProtonDrive-acarlile@pm.me-folder/Carlano/Cloud2GroundAI/mlx_poc

chmod +x granite_helper.sh
chmod +x granite_repl.sh
chmod +x watch_mlx_v2.sh
```

### Test Granite Helper

```bash
./granite_helper.sh "Write a Swift function that reverses a string"
```

Should get a response from Granite!

### Test Interactive REPL

```bash
./granite_repl.sh

granite> Explain how async/await works in Swift
[waits for answer]

granite> exit
```

### Test v2 Watcher

Terminal 1:
```bash
./watch_mlx_v2.sh
```

Terminal 2:
```bash
./bridge_test.sh "Test the new watcher features"
```

Check `~/claude_bridge/_bridge/status.json`:
```bash
cat ~/claude_bridge/_bridge/status.json
```

Should see:
```json
{
  "status": "ready",
  "model": "mlx-community/granite-3.3-2b-instruct-8bit",
  "temperature": 0.2,
  "backend": "mlx-swift",
  "version": "2.0-phase1",
  "last_heartbeat": 1784416000
}
```

Check savings ledger:
```bash
cat ~/claude_bridge/savings.json
```

Should see:
```json
{
  "total_requests": 1,
  "total_input_tokens": 45,
  "total_output_tokens": 120,
  "estimated_cost_saved_usd": 0.002,
  "last_updated": 1784416000,
  "version": "2.0-phase1"
}
```

---

## What's Next

### Remaining Phase 1 Tasks

- [ ] **Improve token counting** — Use actual MLX tokenizer instead of word approximation
- [ ] **Test with 8B model** — Compare quality
- [ ] **Daily dogfooding** — Use for real work
- [ ] **Fix any bugs** — Edge cases, error handling
- [ ] **Performance tuning** — Optimize if needed

### Using Granite to Help Build

You can now ask Granite to help you build the rest!

**Examples:**

```bash
# Ask how to use MLX tokenizer
./granite_helper.sh "How do I use the Tokenizer class in MLX-Swift to count tokens in a string?"

# Ask about Swift JSON
./granite_helper.sh "Show me how to read and update JSON in Swift with error handling"

# Interactive exploration
./granite_repl.sh
granite> How do I call a tokenizer's encode method in Swift?
granite> Show me the API for MLX-Swift's Tokenizer
granite> exit
```

---

## Features Comparison

| Feature | POC | v2.0 Phase 1 | Status |
|---------|-----|--------------|--------|
| Basic inference | ✅ | ✅ | Done |
| Bridge protocol | ✅ | ✅ | Done |
| Model loading | ✅ | ✅ | Done |
| **Heartbeat/status** | ❌ | ✅ | **NEW** |
| **Token counting** | ❌ | ✅ | **NEW** |
| **Savings tracking** | ❌ | ✅ | **NEW** |
| **Temperature config** | ❌ | ✅ | **NEW** |
| **Stale lock cleanup** | ❌ | ✅ | **NEW** |
| **Fence stripping** | ❌ | ✅ | **NEW** |
| Accurate tokenization | ❌ | 🔄 | In progress |
| Streaming responses | ❌ | ❌ | Future |

---

## Troubleshooting

### granite_helper.sh: command not found

```bash
chmod +x granite_helper.sh
./granite_helper.sh "test"
```

### granite_helper.sh: c2g-mlx binary not found

```bash
# Check binary exists
ls -lh c2g-mlx/.build/arm64-apple-macosx/release/c2g-mlx

# Or set path manually
export C2G_MLX_BIN=/path/to/c2g-mlx
./granite_helper.sh "test"
```

### REPL hangs on first query

First load is slow (model loading). Wait 10-15 seconds.

### Savings ledger shows $0.00

This is correct if you just started! Run a few requests to see it update.

### jq: command not found

Install jq (needed for JSON parsing):
```bash
brew install jq
```

---

## Example Session

```bash
# Terminal 1: Start v2 watcher
$ ./watch_mlx_v2.sh
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  C2G MLX watcher v2.0-phase1
  Bridge: /Users/you/claude_bridge/_bridge
  Model:  mlx-community/granite-3.3-2b-instruct-8bit
  Temp:   0.2
  Binary: /path/to/c2g-mlx
  Ctrl+C to stop.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✓ ready — waiting for requests

→ request id=test-123 — running MLX… (42 input tokens)
✓ done in 3s (287 chars, 95 tokens)
  💰 Total saved: $0.002

# Terminal 2: Send requests
$ ./bridge_test.sh "Write a Python function to sort a list"
→ sent id=test-123
  prompt: Write a Python function to sort a list

← response:
────────────────────────────────────────
[Granite's response]
────────────────────────────────────────

# Check savings
$ cat ~/claude_bridge/savings.json
{
  "total_requests": 1,
  "total_input_tokens": 42,
  "total_output_tokens": 95,
  "estimated_cost_saved_usd": 0.002,
  "last_updated": 1784416123,
  "version": "2.0-phase1"
}

# Use Granite to help build more features
$ ./granite_repl.sh
granite> How do I use MLX's Tokenizer to count tokens accurately?
[Granite explains...]
granite> exit
```

---

## Notes

### Token Counting Accuracy

Current implementation approximates: `words * 1.3 ≈ tokens`

This is **good enough** for showing savings but not exact.

**TODO:** Use actual MLX tokenizer:
```swift
let tokenizer = container.tokenizer
let tokens = tokenizer.encode(text: prompt)
let count = tokens.count
```

### Temperature

Default is 0.2 (matching production Ollama watcher).

- **Lower (0.0-0.3):** More deterministic, focused
- **Higher (0.7-1.0):** More creative, varied

For code generation, keep it low (0.2).

### Fence Stripping

Removes markdown code fences from responses.

**Example:**
```
Input from Granite:
```python
def hello():
    print("hi")
```

Output after stripping:
def hello():
    print("hi")
```

Enable/disable with `C2G_STRIP_FENCES=true/false`

---

*Version: 2.0-phase1*  
*Created: 2026-07-18*  
*Status: Ready to test*
