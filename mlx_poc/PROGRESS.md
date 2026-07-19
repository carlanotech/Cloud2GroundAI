# mlx_poc — progress & handoff

**Goal:** prove the Cloud2Ground bridge loop (Claude → `_bridge` → local Granite
→ `_bridge` → Claude) runs on **MLX-Swift with no Ollama**. This is a throwaway
proof of concept — just the connection, no DMG/packaging.

Last updated: 2026-07-15 (during step-by-step walkthrough).

---

## Status at a glance

| Stage | What | State |
|---|---|---|
| Env check | arm64 + full Xcode 26.6, selected correctly | ✅ done |
| Stage 0 | Apple's stock `llm-tool` runs | ⏭️ skipped (see note) |
| Stage 1a | `c2g-mlx` **compiles** | ✅ done — `Build complete!` |
| Stage 1b | `c2g-mlx` **runs / generates** | ❌ blocked — metallib not found |
| Stage 2 | Full bridge loop via `watch_mlx.sh` + `bridge_test.sh` | ⏸️ not started |

**We are one runtime issue away from a working local model.** The code is
correct and compiled; it just can't find the Metal shader library when run as a
plain command-line binary.

---

## Confirmed facts (don't re-litigate these)

- **Machine:** Apple Silicon (`arm64`), macOS with **Xcode 26.6** selected at
  `/Applications/Xcode.app/Contents/Developer`. MLX is fully supported here.
- **The MLX package universe resolves cleanly** on this machine. Pinned/resolved
  versions:
  - `mlx-swift-lm` → **3.31.4**
  - `mlx-swift` → **0.31.6**
  - `swift-transformers` → **1.3.3**
  - `swift-huggingface` → **0.9.0**
  - `swift-jinja` → **2.4.1**
- **Our API is correct.** `swift build -c release` succeeded (~238 s). That means
  the previously-unverified 3.x macro API in `main.swift` is right:
  `#huggingFaceLoadModelContainer(configuration:)`, `ChatSession(container)`,
  `session.respond(to:)`, `ModelConfiguration(id:)`. **No source fixups needed.**
- **Model downloaded:** `mlx-community/granite-3.3-2b-instruct-8bit` is cached
  locally (pulled during the Stage-0 attempt).

### Note on skipping Stage 0
Apple's `llm-tool` is **not** exposed as a SwiftPM executable product
(`swift run llm-tool` → "no executable product named 'llm-tool'"), and `mlx-run`
tripped on an ambiguous build destination ("My Mac" vs "Any Mac"). Rather than
debug Apple's Xcode-only tool, we pivoted straight to building **our own**
`c2g-mlx`, which *is* a proper SwiftPM product. That succeeded, so Stage 0 is
unnecessary.

---

## The current blocker (Stage 1b)

Running the built binary:

```bash
echo "Write a Python function that reverses a string." | .build/release/c2g-mlx
```

fails at model load with:

```
MLX error: Failed to load the default metallib. library not found ... stream.cpp:115
```

**Why:** per mlx-swift's own troubleshooting, Metal shaders live in a bundle
called `mlx-swift_Cmlx.bundle`, and a *command-line* binary can only find them if
`DYLD_FRAMEWORK_PATH` points at the build directory. (Xcode sets this
automatically; the shell does not. Apple's `mlx-run` script does exactly this —
`export DYLD_FRAMEWORK_PATH=<build-dir>` — for their Xcode-built tools.)

**Tried, did NOT work:**
```bash
export DYLD_FRAMEWORK_PATH="$PWD/.build/release/PackageFrameworks:$PWD/.build/release"
```
So the SwiftPM build put the bundle somewhere other than `.build/release/`. We
need to locate it.

---

## NEXT STEPS (start here when back)

Run from inside `mlx_poc/c2g-mlx`:

1. **Locate the shader bundle / metallib:**
   ```bash
   find .build -name '*.metallib'
   find .build -name 'mlx-swift_Cmlx.bundle'
   ```
   Paste the paths to Claude.

2. **Point `DYLD_FRAMEWORK_PATH` at the directory that contains
   `mlx-swift_Cmlx.bundle`** (whatever the find shows — likely something under
   `.build/release/` or `.build/arm64-apple-macosx/release/`), then retry:
   ```bash
   export DYLD_FRAMEWORK_PATH="<dir-containing-the-bundle>"
   echo "Write a Python function that reverses a string." | .build/release/c2g-mlx
   ```
   Fallback if that still fails: copy the bundle next to the binary, or run via a
   small wrapper — Claude will advise based on the find output.

3. **Once it generates text:** Claude patches `watch_mlx.sh` to `export` the
   working `DYLD_FRAMEWORK_PATH` before it calls the binary (the watcher hits the
   same issue otherwise).

4. **Stage 2 — full loop:**
   - Terminal A: `./watch_mlx.sh`
   - Terminal B: `./bridge_test.sh`
   - Success = Granite's answer comes back id-matched through `_bridge`, and
     `pgrep ollama` returns nothing.

---

## Files in this folder

- `c2g-mlx/Package.swift` — SwiftPM package (pins listed above).
- `c2g-mlx/Sources/c2g-mlx/main.swift` — the CLI: prompt in (stdin or `--file`),
  Granite completion out on stdout. **Compiles & is confirmed correct.**
- `watch_mlx.sh` — minimal bridge watcher calling `c2g-mlx` (needs the
  `DYLD_FRAMEWORK_PATH` line added once we know the path — step 3 above).
- `bridge_test.sh` — simulates the Claude/cloud side for end-to-end testing.
- `README.md` — the original staged plan (Stage 0/1/2) and troubleshooting.
- `PROGRESS.md` — this file.

## Key commands reference

```bash
# build
cd ~/Library/CloudStorage/ProtonDrive-acarlile@pm.me-folder/Carlano/Cloud2GroundAI/mlx_poc/c2g-mlx
swift build -c release

# run once (needs DYLD_FRAMEWORK_PATH set correctly first)
echo "your prompt" | .build/release/c2g-mlx

# swap model
export C2G_MLX_MODEL=mlx-community/granite-3.3-8b-instruct-8bit
```
