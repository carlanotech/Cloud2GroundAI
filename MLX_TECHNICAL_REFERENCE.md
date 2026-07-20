# MLX-Swift Technical Reference

**Purpose:** Deep technical documentation for maintaining and extending the MLX-based Cloud2Ground system.

**Audience:** Future developers (including yourself in 6 months when you've forgotten the details)

---

## Table of Contents

1. [Build Process](#build-process)
2. [Metal Shader Compilation](#metal-shader-compilation)
3. [MLX-Swift API Reference](#mlx-swift-api-reference)
4. [Bridge Protocol Specification](#bridge-protocol-specification)
5. [File Formats](#file-formats)
6. [Environment Variables](#environment-variables)
7. [Troubleshooting](#troubleshooting)
8. [Common Tasks](#common-tasks)

---

## Build Process

### Full Build from Scratch

```bash
cd ~/Library/CloudStorage/ProtonDrive-acarlile@pm.me-folder/Carlano/Cloud2GroundAI/mlx_poc/c2g-mlx

# 1. Clean previous builds (optional)
swift package clean

# 2. Resolve dependencies (will take ~1 min first time)
swift package resolve

# 3. Build release binary (~4 min first time, ~30s incremental)
swift build -c release

# 4. Compile Metal shaders
cd ../
./BUILD_METALLIB.sh

# 5. Verify
.build/arm64-apple-macosx/release/c2g-mlx --help
```

### Incremental Build (code changes only)

```bash
cd c2g-mlx
swift build -c release
# Metal shaders don't need recompilation unless mlx-swift version changes
```

### Dependency Updates

```bash
# Update all dependencies to latest compatible versions
swift package update

# After updating, MUST rebuild Metal shaders
swift build -c release
cd ../
./BUILD_METALLIB.sh
```

---

## Metal Shader Compilation

### Why This Is Needed

SwiftPM compiles Metal shaders automatically for **app bundles** (iOS/macOS apps) but NOT for **command-line executables**. MLX requires compiled Metal shaders (`mlx.metallib`) to run GPU operations.

### The Build Pipeline

```
┌─────────────────────────────────────────────────────────────┐
│ Step 1: Compile each .metal source to .air (intermediate)  │
└──────────────────────┬──────────────────────────────────────┘
                       │
        ┌──────────────┴──────────────┐
        │                             │
        ▼                             ▼
   file1.metal                   file2.metal
        │                             │
        │ xcrun metal -c              │ xcrun metal -c
        ▼                             ▼
   file1.air                     file2.air
        │                             │
        └──────────────┬──────────────┘
                       │
┌──────────────────────┴──────────────────────────────────────┐
│ Step 2: Link all .air files into one .metallib library     │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       │ xcrun metallib
                       ▼
                  mlx.metallib (3 MB)
                       │
┌──────────────────────┴──────────────────────────────────────┐
│ Step 3: Copy to binary directory                           │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
      .build/arm64-apple-macosx/release/mlx.metallib
```

### Manual Compilation Steps

```bash
# Navigate to Metal source directory
cd c2g-mlx/.build/checkouts/mlx-swift/Source/Cmlx/mlx-generated/metal/

# Create temp directory
mkdir -p /tmp/mlx_metal_build

# Compile all .metal files in root
for f in *.metal; do
    xcrun -sdk macosx metal -c "$f" -o "/tmp/mlx_metal_build/${f%.metal}.air"
done

# Compile steel attention kernels
for f in steel/attn/kernels/*.metal; do
    xcrun -sdk macosx metal -c "$f" -o "/tmp/mlx_metal_build/$(basename ${f%.metal}).air"
done

# Link into library
xcrun -sdk macosx metallib /tmp/mlx_metal_build/*.air -o /tmp/mlx.metallib

# Copy to build directory
cp /tmp/mlx.metallib ../../../../../../.build/arm64-apple-macosx/release/mlx.metallib

# Cleanup
rm -rf /tmp/mlx_metal_build
```

### Automated Script: `BUILD_METALLIB.sh`

Location: `mlx_poc/BUILD_METALLIB.sh`

```bash
#!/usr/bin/env bash
# Automates the Metal shader compilation process
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
METAL_SRC="$SCRIPT_DIR/c2g-mlx/.build/checkouts/mlx-swift/Source/Cmlx/mlx-generated/metal"
BUILD_DIR="$SCRIPT_DIR/c2g-mlx/.build/arm64-apple-macosx/release"
TMP_DIR="/tmp/mlx_metal_build_$$"

echo "→ Compiling Metal shaders..."
mkdir -p "$TMP_DIR"
cd "$METAL_SRC"

for f in *.metal steel/attn/kernels/*.metal; do
    [ -f "$f" ] || continue
    echo "  - $(basename "$f")"
    xcrun -sdk macosx metal -c "$f" -o "$TMP_DIR/$(basename "${f%.metal}").air"
done

echo "→ Creating mlx.metallib..."
xcrun -sdk macosx metallib "$TMP_DIR"/*.air -o "$TMP_DIR/mlx.metallib"

cp "$TMP_DIR/mlx.metallib" "$BUILD_DIR/mlx.metallib"
rm -rf "$TMP_DIR"

echo "✓ Metal library ready at: $BUILD_DIR/mlx.metallib"
ls -lh "$BUILD_DIR/mlx.metallib"
```

### Verifying Metal Library

```bash
# Check if it exists
ls -lh .build/arm64-apple-macosx/release/mlx.metallib

# Should show ~3.0 MB file

# Test that binary can find it
echo "test" | .build/arm64-apple-macosx/release/c2g-mlx
# Should NOT error with "Failed to load the default metallib"
```

### What's Inside mlx.metallib?

The Metal library contains compiled GPU kernels for:

- Matrix operations (GEMM, GEMV)
- Attention mechanisms (scaled dot-product attention, steel attention)
- Quantization (int4, int8, float16)
- Normalization (layer norm, RMS norm)
- Element-wise operations (unary, binary, ternary)
- Reductions (sum, max, arg_max)
- Special functions (RoPE, random number generation)
- FFT operations
- Convolutions

Each kernel is optimized for Apple Silicon GPU architecture.

---

## MLX-Swift API Reference

### Package Dependencies

From `c2g-mlx/Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/ml-explore/mlx-swift-lm", 
             .upToNextMajor(from: "3.31.3")),
    .package(url: "https://github.com/huggingface/swift-huggingface", 
             from: "0.9.0"),
    .package(url: "https://github.com/huggingface/swift-transformers", 
             from: "1.3.0"),
]

targets: [
    .executableTarget(
        name: "c2g-mlx",
        dependencies: [
            .product(name: "MLXLLM", package: "mlx-swift-lm"),
            .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
            .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
            .product(name: "HuggingFace", package: "swift-huggingface"),
            .product(name: "Tokenizers", package: "swift-transformers"),
        ]
    )
]
```

### Core Imports

```swift
import MLXLLM                  // Main LLM interface
import MLXLMCommon             // Model configuration, chat templates
import MLXHuggingFace          // Hugging Face integration + macros
import HuggingFace             // Model downloading
import Tokenizers              // Tokenization
import Foundation              // Standard library
```

### Loading a Model (3.x API)

```swift
// Model configuration
let modelID = "mlx-community/granite-3.3-2b-instruct-8bit"
let config = ModelConfiguration(id: modelID)

// Load model container using macro
#huggingFaceLoadModelContainer(configuration: config) { container in
    // container is ModelContainer
    // Contains: model, tokenizer, processor, configuration
    
    // Create chat session
    let session = ChatSession(container: container)
    
    // Generate response
    let prompt = "Write a Python function that reverses a string."
    for try await text in session.respond(to: prompt) {
        print(text, terminator: "")
    }
}
```

### Key Types

```swift
// Model configuration
struct ModelConfiguration {
    let id: String              // Hugging Face model ID
    // Other fields auto-populated from model config
}

// Model container (holds everything needed for inference)
class ModelContainer {
    let model: any LanguageModel
    let tokenizer: Tokenizer
    let processor: any UserInputProcessor
    let configuration: ModelConfiguration
}

// Chat session (maintains conversation context)
class ChatSession {
    init(container: ModelContainer)
    
    func respond(to prompt: String) -> AsyncThrowingStream<String, Error>
    // Returns streaming response as async sequence
}
```

### Full Example (from `main.swift`)

```swift
import Foundation
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import HuggingFace
import Tokenizers

@main
struct C2GMLX {
    static func main() async throws {
        // 1. Parse arguments (--file or stdin)
        var prompt: String
        if CommandLine.arguments.contains("--file"),
           let idx = CommandLine.arguments.firstIndex(of: "--file"),
           idx + 1 < CommandLine.arguments.count {
            let path = CommandLine.arguments[idx + 1]
            prompt = try String(contentsOfFile: path, encoding: .utf8)
        } else {
            var input = ""
            while let line = readLine() {
                input += line + "\n"
            }
            prompt = input.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // 2. Get model ID from env or default
        let modelID = ProcessInfo.processInfo.environment["C2G_MLX_MODEL"]
            ?? "mlx-community/granite-3.3-2b-instruct-8bit"
        
        // 3. Log to stderr (so it doesn't mix with output)
        FileHandle.standardError.write(
            "c2g-mlx: loading \(modelID) …\n".data(using: .utf8)!
        )
        
        // 4. Load model and generate
        let config = ModelConfiguration(id: modelID)
        
        #huggingFaceLoadModelContainer(configuration: config) { container in
            let session = ChatSession(container: container)
            var output = ""
            
            for try await text in session.respond(to: prompt) {
                output += text
            }
            
            // 5. Write result to stdout
            print(output)
            
            // 6. Log completion to stderr
            FileHandle.standardError.write(
                "c2g-mlx: done (\(output.count) chars)\n".data(using: .utf8)!
            )
        }
    }
}
```

### Model Selection

Currently supported Granite models (from mlx-community on Hugging Face):

```bash
# 2B model (default, fast, good quality)
C2G_MLX_MODEL=mlx-community/granite-3.3-2b-instruct-8bit

# 8B model (better quality, slower, more memory)
C2G_MLX_MODEL=mlx-community/granite-3.3-8b-instruct-8bit

# Future: 20B, 34B, etc. as IBM releases them
```

Models are downloaded to: `~/.cache/huggingface/hub/`

### Sampling Parameters (Future Enhancement)

Currently using defaults. Can be customized via:

```swift
let params = GenerateParameters(
    temperature: 0.2,        // Lower = more deterministic
    topP: 0.9,              // Nucleus sampling
    maxTokens: 2048,        // Max generation length
    repetitionPenalty: 1.1  // Penalize repetition
)

for try await text in session.respond(to: prompt, parameters: params) {
    print(text, terminator: "")
}
```

---

## Bridge Protocol Specification

### Overview

Simple file-based IPC using atomic writes and lock files.

**Location:** `~/claude_bridge/_bridge/`

### File Types

| File | Purpose | Created By | Read By | Lifecycle |
|------|---------|-----------|---------|-----------|
| `request.txt` | Prompt + metadata | Cloud (Claude) | Local (watcher) | Created → read → deleted |
| `response.txt` | Answer + metadata | Local (watcher) | Cloud (Claude) | Created → read → marked consumed |
| `consumed.txt` | Ack from cloud | Cloud (Claude) | Local (watcher) | Created → triggers cleanup |
| `processing.lock` | Mutex for watcher | Local (watcher) | Local (watcher) | Created → work → deleted |
| `status.json` | Heartbeat (optional) | Local (watcher) | Cloud (Claude) | Updated periodically |

### Request Format

```
# id: <unique-request-id>
<prompt body line 1>
<prompt body line 2>
...
```

**Example:**
```
# id: t-1784415994-7473
Write a Python function that reverses a string.
```

**Rules:**
- First line MUST be `# id: <id>`
- ID format: `t-<timestamp>-<pid>` (but any alphanumeric + `-_` works)
- Prompt starts on line 2
- UTF-8 encoding
- No trailing metadata

### Response Format

```
# id: <same-id-from-request>
<response body line 1>
<response body line 2>
...
```

**Example:**
```
# id: t-1784415994-7473
Here's a Python function that reverses a string:

def reverse_string(s):
    return s[::-1]
```

**Rules:**
- First line MUST be `# id: <id>` matching the request
- Response starts on line 2
- UTF-8 encoding
- No fence stripping yet (TODO for production)

### Lock File Format

```
<watcher-process-id>
```

**Example:**
```
5162
```

Just contains the PID of the watcher process. Used to:
- Prevent multiple watchers from processing same request
- Detect stale locks (if PID doesn't exist)
- Show "busy" state in status

### Status File Format (Optional)

```json
{
  "status": "ready",
  "model": "mlx-community/granite-3.3-2b-instruct-8bit",
  "last_heartbeat": 1784415994,
  "version": "mlx-1.0-poc"
}
```

Used by delegation skill to check if watcher is alive.

### Protocol Flow

```
Cloud                          Bridge                          Local
  │                              │                              │
  │  1. Write request.txt        │                              │
  ├──────────────────────────────>                              │
  │                              │                              │
  │                              │  2. Detect request.txt       │
  │                              <──────────────────────────────┤
  │                              │                              │
  │                              │  3. Create processing.lock   │
  │                              <──────────────────────────────┤
  │                              │                              │
  │                              │  4. Read request.txt         │
  │                              <──────────────────────────────┤
  │                              │                              │
  │                              │  5. Run inference            │
  │                              │                         [GPU works]
  │                              │                              │
  │                              │  6. Write response.txt       │
  │                              <──────────────────────────────┤
  │                              │                              │
  │                              │  7. Delete request.txt       │
  │                              <──────────────────────────────┤
  │                              │                              │
  │                              │  8. Delete processing.lock   │
  │                              <──────────────────────────────┤
  │                              │                              │
  │  9. Read response.txt        │                              │
  <──────────────────────────────┤                              │
  │                              │                              │
  │  10. Write consumed.txt      │                              │
  ├──────────────────────────────>                              │
  │                              │                              │
  │                              │  11. Detect consumed.txt     │
  │                              <──────────────────────────────┤
  │                              │                              │
  │                              │  12. Delete response.txt     │
  │                              <──────────────────────────────┤
  │                              │                              │
  │                              │  13. Delete consumed.txt     │
  │                              <──────────────────────────────┤
  │                              │                              │
  │  [Ready for next request]    │                              │
```

### Error Handling

**If watcher crashes during processing:**
- `processing.lock` remains
- Contains dead PID
- Next watcher startup should clean stale locks
- TODO: Implement stale lock GC (check if PID exists)

**If cloud crashes after receiving response:**
- `consumed.txt` never created
- `response.txt` remains
- Watcher won't clear it until `consumed.txt` appears
- Cloud re-reads same response on restart (idempotent)

**If model fails:**
- Watcher writes error message as response
- Format: `ERROR: <description>`
- Cloud receives error as normal response
- User sees error message

---

## File Formats

### Model Cache Format

Location: `~/.cache/huggingface/hub/`

```
hub/
└── models--mlx-community--granite-3.3-2b-instruct-8bit/
    ├── refs/
    │   └── main                        (contains: snapshot hash)
    ├── snapshots/
    │   └── <hash>/
    │       ├── config.json             (model architecture config)
    │       ├── tokenizer.json          (tokenizer vocabulary + rules)
    │       ├── tokenizer_config.json   (tokenizer settings)
    │       ├── model-00001-of-00002.safetensors  (weights shard 1)
    │       ├── model-00002-of-00002.safetensors  (weights shard 2)
    │       └── model.safetensors.index.json      (shard mapping)
    └── blobs/
        └── <sha256-hashes>             (actual file contents)
```

**Sharded Models:**
Large models (8B+) are split into multiple `.safetensors` files.
The index file maps layer names to shards.

**Cache Size:**
- 2B-8bit: ~2.5 GB
- 8B-8bit: ~8 GB
- Can grow significantly if multiple models cached

**Clearing Cache:**
```bash
rm -rf ~/.cache/huggingface/hub/models--mlx-community--granite*
# Next run will re-download
```

### SafeTensors Format

MLX uses SafeTensors (not PyTorch `.bin` or `.pt` files).

**Advantages:**
- Safe (no arbitrary code execution)
- Fast (memory-mapped loading)
- Cross-platform (Rust-based, works everywhere)
- Lazy loading (don't need to load whole model into RAM)

**Structure:**
- Header: JSON metadata (tensor names, shapes, dtypes, offsets)
- Body: Raw tensor data (contiguous bytes)

**Reading (handled by MLX):**
```swift
// MLX automatically loads SafeTensors
// You don't need to parse them manually
```

---

## Environment Variables

### User-Facing Variables

| Variable | Purpose | Default | Example |
|----------|---------|---------|---------|
| `C2G_MLX_MODEL` | Model to load | `granite-3.3-2b-instruct-8bit` | `mlx-community/granite-3.3-8b-instruct-8bit` |
| `C2G_BRIDGE` | Bridge directory | `~/claude_bridge/_bridge` | `/custom/path/_bridge` |
| `C2G_MLX_BIN` | Override binary path | Auto-detected | `/usr/local/bin/c2g-mlx` |

### Internal Variables (Used by watcher)

| Variable | Set By | Used By | Purpose |
|----------|--------|---------|---------|
| `TMPDIR` | macOS | All processes | Temp file location |
| `HOME` | macOS | Watcher, HF downloader | User home directory |
| `PATH` | macOS | Shell | Find executables |

### Hugging Face Variables (Optional)

| Variable | Purpose | When Needed |
|----------|---------|-------------|
| `HF_TOKEN` | Authentication | For private/gated models (not needed for Granite) |
| `HF_HOME` | Override cache location | To use custom cache directory |

**Example:**
```bash
# Use custom cache location
export HF_HOME=/Volumes/External/huggingface
```

---

## Troubleshooting

### "Failed to load the default metallib"

**Symptom:**
```
MLX error: Failed to load the default metallib. library not found ...
```

**Cause:** `mlx.metallib` not found next to binary

**Fix:**
```bash
cd mlx_poc
./BUILD_METALLIB.sh
```

**Verify:**
```bash
ls -lh c2g-mlx/.build/arm64-apple-macosx/release/mlx.metallib
# Should show ~3.0 MB file
```

---

### "Model not found" or Download Hangs

**Symptom:**
- Hangs at "loading model..."
- Network errors
- 404 not found

**Common Causes:**
1. Typo in model ID
2. Model doesn't exist for MLX
3. Network connectivity issue
4. Disk full (cache can't write)

**Fix:**
```bash
# Check model exists on HF
open "https://huggingface.co/mlx-community/granite-3.3-2b-instruct-8bit"

# Check network
ping huggingface.co

# Check disk space
df -h ~/.cache

# Force re-download
rm -rf ~/.cache/huggingface/hub/models--mlx-community--granite*
```

---

### "No matching response within 180s"

**Symptom:**
`bridge_test.sh` times out waiting for response

**Debugging:**
```bash
# 1. Is watcher running?
ps aux | grep watch_mlx

# 2. Check watcher output
# (Look at terminal where watch_mlx.sh is running)

# 3. Check bridge directory
ls -la ~/claude_bridge/_bridge/

# 4. Check logs
tail -f ~/claude_bridge/_bridge/mlx.log

# 5. Check for locks
cat ~/claude_bridge/_bridge/processing.lock
# If exists: is that PID alive?
ps -p <pid>
```

**Common fixes:**
- Watcher not running → start it
- Model failed to load → check mlx.log
- Lock file stuck → remove manually if PID is dead
- Request file format wrong → check for `# id:` line

---

### "Build Failed" During swift build

**Symptom:**
Compilation errors, dependency resolution fails

**Common Causes:**
1. Wrong Swift version (need 5.9+)
2. Wrong Xcode version (need 15+)
3. Dependency version conflict
4. Network issue during resolution

**Fix:**
```bash
# Check Swift version
swift --version
# Should be 5.9 or later

# Check Xcode version
xcodebuild -version
# Should be 15.0 or later

# Select correct Xcode
sudo xcode-select -s /Applications/Xcode.app

# Clean and retry
swift package clean
swift package resolve
swift build -c release
```

---

### Metal Toolchain Missing

**Symptom:**
```
error: cannot execute tool 'metal' due to missing Metal Toolchain
```

**Fix:**
```bash
# Download Metal toolchain
xcodebuild -downloadComponent MetalToolchain

# Verify
xcrun -sdk macosx metal --version
```

---

### Watcher Picks Up Wrong Request

**Symptom:**
Response doesn't match request ID

**Cause:**
Multiple watchers running (old Ollama watcher + new MLX watcher)

**Fix:**
```bash
# Find all watchers
ps aux | grep -E '(watch_mlx|start_local_ai)'

# Kill old watcher
kill <old-watcher-pid>

# Clean bridge directory
rm -rf ~/claude_bridge/_bridge/*

# Restart MLX watcher only
cd mlx_poc
./watch_mlx.sh
```

---

### Out of Memory During Inference

**Symptom:**
- Process killed
- "Memory error" in logs
- System slow/swapping

**Cause:**
Model too large for available unified memory

**Fix:**
```bash
# Use smaller model
export C2G_MLX_MODEL=mlx-community/granite-3.3-2b-instruct-8bit

# Or: add more RAM (8B model needs ~16GB recommended)
```

---

## Common Tasks

### Switching Models

```bash
# Temporary (this session only)
export C2G_MLX_MODEL=mlx-community/granite-3.3-8b-instruct-8bit
./watch_mlx.sh

# Permanent (add to shell profile)
echo 'export C2G_MLX_MODEL=mlx-community/granite-3.3-8b-instruct-8bit' >> ~/.zshrc
```

### Testing a Prompt Directly

```bash
# From stdin
echo "Your prompt here" | .build/arm64-apple-macosx/release/c2g-mlx

# From file
.build/arm64-apple-macosx/release/c2g-mlx --file prompt.txt

# With different model
C2G_MLX_MODEL=mlx-community/granite-3.3-8b-instruct-8bit \
  echo "Your prompt" | .build/arm64-apple-macosx/release/c2g-mlx
```

### Updating MLX-Swift Dependency

```bash
cd c2g-mlx

# Update to latest compatible version
swift package update mlx-swift-lm

# Rebuild
swift build -c release

# IMPORTANT: Rebuild Metal shaders
cd ../
./BUILD_METALLIB.sh
```

### Creating a Standalone Release Package

```bash
# Create release directory
mkdir -p ~/Desktop/c2g-mlx-release

# Copy binary
cp c2g-mlx/.build/arm64-apple-macosx/release/c2g-mlx \
   ~/Desktop/c2g-mlx-release/

# Copy Metal library
cp c2g-mlx/.build/arm64-apple-macosx/release/mlx.metallib \
   ~/Desktop/c2g-mlx-release/

# Copy scripts
cp watch_mlx.sh bridge_test.sh BUILD_METALLIB.sh \
   ~/Desktop/c2g-mlx-release/

# Create README
cat > ~/Desktop/c2g-mlx-release/README.txt << EOF
Cloud2Ground MLX Release
========================

1. Copy c2g-mlx and mlx.metallib to /usr/local/bin/
2. Copy watch_mlx.sh to ~/Library/Application Support/claude_bridge/
3. Run: chmod +x ~/Library/Application Support/claude_bridge/watch_mlx.sh
4. Start watcher: ~/Library/Application Support/claude_bridge/watch_mlx.sh

Model will auto-download on first run (~2.5 GB).
EOF

# Create tarball
cd ~/Desktop
tar -czf c2g-mlx-release.tar.gz c2g-mlx-release/

echo "Release package: ~/Desktop/c2g-mlx-release.tar.gz"
```

### Benchmarking Performance

```bash
# Simple benchmark
time echo "Write a Python function to sort a list" | \
  .build/arm64-apple-macosx/release/c2g-mlx

# Multi-request benchmark
for i in {1..10}; do
  time ./bridge_test.sh "Request $i: Write code to reverse a string"
  sleep 2
done
```

### Monitoring Resource Usage

```bash
# While inference running, in another terminal:

# Watch memory usage
watch -n 1 'ps aux | grep c2g-mlx'

# Watch GPU usage (requires sudo)
sudo powermetrics --samplers gpu_power -i 1000

# Watch CPU temperature
sudo powermetrics --samplers smc -i 1000
```

---

## Advanced Topics

### Custom Model Quantization

MLX supports multiple quantization formats. Current models use 8-bit.

**Future: Experiment with different quantizations**
```bash
# 4-bit (smaller, faster, lower quality)
# 8-bit (current, balanced)
# 16-bit (larger, slower, higher quality)
# FP32 (huge, very slow, maximum quality)
```

Would require converting models with MLX Python tools.

### Streaming Responses (TODO)

Current implementation buffers full response. MLX supports streaming:

```swift
// In main.swift, change from:
var output = ""
for try await text in session.respond(to: prompt) {
    output += text
}
print(output)

// To:
for try await text in session.respond(to: prompt) {
    print(text, terminator: "")
    fflush(stdout)  // Force flush for streaming
}
```

Would need bridge protocol update to support partial responses.

### Multi-Model Support

Currently single model per watcher. Could extend to:

```swift
// Model registry
let models = [
    "granite-2b": ModelConfiguration(id: "mlx-community/granite-3.3-2b-instruct-8bit"),
    "granite-8b": ModelConfiguration(id: "mlx-community/granite-3.3-8b-instruct-8bit"),
]

// Request format: # model: granite-8b
// Select model based on request header
```

### Fine-Tuning for C2G

MLX supports fine-tuning. Could train Granite specifically on:
- Shell command generation
- Code explanation
- Debugging assistance
- Documentation writing

Would require collecting training data and using MLX Python tools.

---

*Document version: 1.0*  
*Last updated: 2026-07-18*  
*Maintainer: Andrew Carlile*
