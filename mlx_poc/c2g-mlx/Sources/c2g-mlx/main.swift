// c2g-mlx — minimal local inference CLI for the Cloud2Ground bridge.
//
// What it does: read a prompt (from `--file <path>` or stdin), load a pinned
// Granite model in MLX format straight from the Hugging Face hub, generate a
// completion, print ONLY the completion to stdout. Progress/errors go to
// stderr so the watcher can capture stdout cleanly.
//
// No Ollama. No daemon. First run downloads the weights to the Hugging Face
// cache (~/.cache/huggingface or ~/Documents/huggingface depending on the
// downloader); subsequent runs are offline-capable.
//
// This targets the mlx-swift-lm 3.x quick-start API (the `#huggingFaceLoad...`
// macro + ChatSession). If a symbol name differs at compile time, the stock
// `llm-tool` in mlx-swift-examples is the canonical reference — copy the exact
// call it uses. See README "If it doesn't compile first try".

import Foundation
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import HuggingFace
import Tokenizers

// ── Config ──────────────────────────────────────────────────────────────────
// Model is overridable via env so the watcher / shell can swap it without a
// rebuild. Default: Granite 3.3 8B, 8-bit — the 2B fast-mode variant produced
// unreliable code output in testing (2026-07-18); 8B is correct out of the box.
let modelId = ProcessInfo.processInfo.environment["C2G_MLX_MODEL"]
    ?? "mlx-community/granite-3.3-8b-instruct-8bit"

// watch_mlx_v2.sh exports this and reports it in status.json, but until now
// nothing here actually read it — generation ran at GenerateParameters'
// default temperature (0.6), not the 0.2 the skill docs/status claim.
let temperature = Float(ProcessInfo.processInfo.environment["C2G_MLX_TEMPERATURE"] ?? "") ?? 0.2

// ── Read the prompt ─────────────────────────────────────────────────────────
func readPrompt() -> String {
    let args = CommandLine.arguments
    if let i = args.firstIndex(of: "--file"), i + 1 < args.count {
        return (try? String(contentsOfFile: args[i + 1], encoding: .utf8)) ?? ""
    }
    let data = FileHandle.standardInput.readDataToEndOfFile()
    return String(data: data, encoding: .utf8) ?? ""
}

func log(_ s: String) {
    FileHandle.standardError.write((s + "\n").data(using: .utf8)!)
}

let prompt = readPrompt().trimmingCharacters(in: .whitespacesAndNewlines)
guard !prompt.isEmpty else {
    log("c2g-mlx: empty prompt")
    exit(2)
}

// ── Load + generate ─────────────────────────────────────────────────────────
log("c2g-mlx: loading \(modelId) …")

let container = try await #huggingFaceLoadModelContainer(
    configuration: ModelConfiguration(id: modelId)
)

// ChatSession applies the model's chat template (correct for Granite instruct)
// and returns the full completion string. For a one-shot CLI we create a fresh
// session per invocation, so there is no history to manage.
// topP/maxTokens per MLX_PRODUCTION_PLAN.md Phase 1.1's documented recommendation.
let session = ChatSession(
    container,
    generateParameters: GenerateParameters(maxTokens: 4096, temperature: temperature, topP: 0.9)
)
let output = try await session.respond(to: prompt)

log("c2g-mlx: done (\(output.count) chars)")

// Completion ONLY on stdout.
print(output)
