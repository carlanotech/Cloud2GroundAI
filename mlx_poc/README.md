# mlx_poc — replace Ollama with MLX-Swift (proof of concept)

Goal: prove the **Claude → bridge → Granite → bridge → Claude** loop runs on
MLX-Swift with **no Ollama anywhere**. Not a product, not a DMG — just the
connection, cheap to run and easy to throw away.

Everything here is self-contained in `mlx_poc/`. Nothing in the existing
project is touched: the production `start_local_ai.sh`, the skill, and the
bridge protocol are all untouched. This watcher speaks the exact same protocol,
so it's a drop-in for testing.

## What's in here

- `c2g-mlx/` — a tiny Swift Package: a CLI that loads a Granite MLX model from
  Hugging Face and generates a completion. This is "our engine wrapper" — the
  thing that replaces the Ollama daemon.
- `watch_mlx.sh` — minimal bridge watcher that calls `c2g-mlx` instead of
  curl-to-Ollama. Same request/response protocol as the real watcher.
- `bridge_test.sh` — simulates the cloud (Claude) side so you can test the full
  loop yourself without the skill.

## Requirements

- Apple Silicon Mac (M-series). MLX is Apple-Silicon only — that's the
  deliberate commitment we discussed.
- macOS 14+.
- **Full Xcode** (not just Command Line Tools) — MLX needs the Metal toolchain.
  After installing, run: `sudo xcode-select -s /Applications/Xcode.app` then
  `xcodebuild -version` to confirm.
- ~10 GB free (model weights + build artifacts). The 2B-8bit model is ~2.5 GB.
- Network on first run (downloads weights from Hugging Face; public, no token).

---

## Stage 0 — prove MLX + Granite run on this machine (zero custom code)

This uses the **stock** `llm-tool` from Apple's examples. If this generates
text, the machine is capable and the model is Ollama-free reachable. This is
the real go/no-go gate.

```bash
cd ~   # or wherever you keep scratch clones
git clone https://github.com/ml-explore/mlx-swift-examples
cd mlx-swift-examples
./mlx-run llm-tool \
  --model mlx-community/granite-3.3-2b-instruct-8bit \
  --prompt "Write a bash one-liner that counts lines in all .txt files."
```

First run downloads the model (a few minutes). Expect generated text. If you
get Metal / GPU errors, see mlx-swift troubleshooting linked from their README —
usually it's Xcode not selected (see Requirements).

**Keep this clone around** — its `Tools/llm-tool` source is the canonical,
known-working reference for the exact MLX API, which we use to fix `c2g-mlx` if
a symbol name drifted (see bottom).

---

## Stage 1 — build our own CLI, `c2g-mlx`

```bash
cd "<this folder>/c2g-mlx"
swift build -c release            # first build resolves + compiles MLX; slow
```

Test it directly (bypassing the bridge):

```bash
echo "Write a Python function that reverses a string." \
  | .build/release/c2g-mlx
```

- Prompt comes from stdin, or from `--file <path>`.
- Model defaults to `mlx-community/granite-3.3-2b-instruct-8bit`; override with
  `C2G_MLX_MODEL=... `.
- The completion prints to **stdout**; progress/errors go to **stderr**.

If it generates a sensible function, our wrapper works. Leave the binary where
it is (`.build/release/c2g-mlx`) — its Metal shader bundle sits next to it.

---

## Stage 2 — run the full bridge loop (still no Ollama)

Terminal A — start the watcher:

```bash
cd "<this folder>"
chmod +x watch_mlx.sh bridge_test.sh    # once
./watch_mlx.sh
```

It should print "ready — waiting for requests". Leave it running.

Terminal B — play the role of Claude and send a request:

```bash
cd "<this folder>"
./bridge_test.sh
# or: ./bridge_test.sh "Write a jq filter that extracts .name from each array element."
```

You should see the request go out and Granite's answer come back, id-matched,
through the same `_bridge` folder the real system uses. That's the whole thesis
proven: cloud side wrote a request, a local MLX model answered it, Ollama never
ran.

Sanity check that Ollama really is out of the loop: `pgrep ollama` should return
nothing while this works.

### Optional — point the real skill at it

The delegation skill checks for a watcher by looking for a `start_local_ai.sh`
process. This POC watcher has a different name, so the skill won't auto-detect
it. Two easy options when you want the real Claude side instead of
`bridge_test.sh`:

1. Just use `bridge_test.sh` — it exercises the identical protocol.
2. Or symlink/rename so the process name matches, and (later) port the
   heartbeat `status.json` writer from the production watcher so the skill's
   readiness check passes. Not needed to prove the loop.

---

## If `c2g-mlx` doesn't compile first try

The `mlx-swift-lm` 3.x API is new and macro-based, and I wrote `main.swift`
without a compiler in front of me. The most likely snags and fixes:

- **`#huggingFaceLoadModelContainer` or `MLXHuggingFace` not found** — the macro
  package name or product name may differ. Open the Stage-0 clone's
  `Tools/llm-tool/LLMTool.swift` and copy exactly how it loads a model
  (`loadModel` / `ModelFactory` / `loadModelContainer`) and the imports it uses,
  then mirror that here.
- **`ChatSession` / `respond(to:)` differ** — same fix: use whatever `llm-tool`
  calls to generate. The one-shot pattern we want is "load container → run one
  generation → print string".
- **`ModelConfiguration(id:)` renamed** — check `MLXLMCommon`; it may be
  `ModelConfiguration(id:)` or a registry lookup. Passing the raw HF id string
  is the goal.
- **Version resolution fails** — bump/relax the pins in `Package.swift` to match
  whatever the Stage-0 clone resolved (`swift package resolve` there and copy
  the versions).

These are 10-15 minute fixes with `llm-tool` open beside it — the architecture
and the loop don't change, only the exact call names.

## Model notes

- Test with **2B** (`granite-3.3-2b-instruct-8bit`) — fast, low memory.
- Move to **8B** (`granite-3.3-8b-instruct-8bit`) once the loop is solid; just
  set `C2G_MLX_MODEL`. No re-pull mechanism needed — MLX fetches on first use.
- Sampling (temperature etc.) is left at defaults in this POC. The production
  watcher pins Granite to temperature 0.2; we can plumb `GenerateParameters`
  into `c2g-mlx` once the loop works — noted, not done, to keep the POC minimal.

## What this deliberately skips (port later, only if the POC passes)

Heartbeat `status.json`, the savings ledger (token counts), `model_families`
per-model options, markdown-fence stripping, stale-lock GC. All present in the
production watcher; none needed to answer "does MLX-Swift work as our engine?"
