// c2g-mlx — minimal local inference CLI for the Cloud2Ground bridge.
//
// Two modes:
//   one-shot (default):  read a prompt (`--file <path>` or stdin), load the
//     model, generate ONE completion, print it, exit. Used directly (see
//     granite_helper.sh) and is what watch_mlx_v2.sh used before resident
//     mode existed.
//   --resident: load the model ONCE, then loop reading requests from stdin
//     and writing responses to stdout until stdin closes. Each request gets
//     a FRESH ChatSession — the loaded model/weights are reused (that's the
//     expensive ~3.7s part), but conversation state is NOT carried between
//     requests. This matters: the delegation bridge's requests are
//     independent one-off tasks, not turns in a conversation — reusing one
//     ChatSession across them would let task N's answer be contaminated by
//     tasks 1..N-1's unrelated prompts. (A future persistent-chat feature
//     that DOES want continuity should reuse one ChatSession across
//     `respond()` calls instead — a deliberately different code path.)
//
// Resident-mode wire protocol (line-based, so it works over a plain named
// pipe with no length-prefixing): a request is one or more lines followed by
// a line that is exactly `<<<C2G_MLX_REQUEST_END>>>`. A response is the
// completion text followed by a line that is exactly
// `<<<C2G_MLX_RESPONSE_END>>>`. The caller (watch_mlx_v2.sh) is responsible
// for keeping its write end of the request pipe open for the whole resident
// session — closing it between requests would deliver a spurious EOF here
// and end the loop after just one request.
//
// No Ollama. No daemon library. First run downloads the weights to the
// Hugging Face cache (~/.cache/huggingface or ~/Documents/huggingface
// depending on the downloader); subsequent runs are offline-capable.
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

// watch_mlx_v2.sh exports this and reports it in status.json — main.swift
// must actually read it (2026-07-19 fix: this used to silently fall back to
// the library's own default of 0.6, not the documented 0.2).
let temperature = Float(ProcessInfo.processInfo.environment["C2G_MLX_TEMPERATURE"] ?? "") ?? 0.2

let requestEndMarker = "<<<C2G_MLX_REQUEST_END>>>"
let responseEndMarker = "<<<C2G_MLX_RESPONSE_END>>>"

func log(_ s: String) {
    FileHandle.standardError.write((s + "\n").data(using: .utf8)!)
    fflush(stderr)
}

func makeGenerateParameters() -> GenerateParameters {
    // topP/maxTokens per MLX_PRODUCTION_PLAN.md Phase 1.1's documented recommendation.
    GenerateParameters(maxTokens: 4096, temperature: temperature, topP: 0.9)
}

// ── One-shot mode ────────────────────────────────────────────────────────────
func readOneShotPrompt() -> String {
    let args = CommandLine.arguments
    if let i = args.firstIndex(of: "--file"), i + 1 < args.count {
        return (try? String(contentsOfFile: args[i + 1], encoding: .utf8)) ?? ""
    }
    let data = FileHandle.standardInput.readDataToEndOfFile()
    return String(data: data, encoding: .utf8) ?? ""
}

func runOneShot() async throws {
    let prompt = readOneShotPrompt().trimmingCharacters(in: .whitespacesAndNewlines)
    guard !prompt.isEmpty else {
        log("c2g-mlx: empty prompt")
        exit(2)
    }

    let t0 = Date()
    log("c2g-mlx: loading \(modelId) …")
    let container = try await #huggingFaceLoadModelContainer(
        configuration: ModelConfiguration(id: modelId)
    )
    let session = ChatSession(container, generateParameters: makeGenerateParameters())
    let output = try await session.respond(to: prompt)
    log("c2g-mlx: done (\(output.count) chars) in \(String(format: "%.2f", Date().timeIntervalSince(t0)))s")

    // Completion ONLY on stdout.
    print(output)
}

// ── Resident mode ────────────────────────────────────────────────────────────
// Reads one line at a time until `requestEndMarker`; blank at EOF (nil from
// readLine()) means the caller closed its write end — time to shut down.
func readResidentRequest() -> String? {
    var lines: [String] = []
    while let line = readLine(strippingNewline: true) {
        if line == requestEndMarker {
            return lines.joined(separator: "\n")
        }
        lines.append(line)
    }
    return nil // EOF — caller closed the pipe, shut down gracefully
}

func runResident() async throws {
    let t0 = Date()
    log("c2g-mlx: resident mode — loading \(modelId) …")
    let container = try await #huggingFaceLoadModelContainer(
        configuration: ModelConfiguration(id: modelId)
    )
    log("c2g-mlx: model resident, ready for requests (load took \(String(format: "%.2f", Date().timeIntervalSince(t0)))s)")

    while let prompt = readResidentRequest() {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            print(responseEndMarker)
            fflush(stdout)
            continue
        }

        let reqStart = Date()
        do {
            // Fresh session per request — see the file header comment for why
            // this must NOT be reused across requests in this mode.
            let session = ChatSession(container, generateParameters: makeGenerateParameters())
            let output = try await session.respond(to: trimmed)
            log("c2g-mlx: resident request done (\(output.count) chars) in \(String(format: "%.2f", Date().timeIntervalSince(reqStart)))s")
            print(output)
        } catch {
            // Don't let one bad request kill the warm process — every
            // subsequent request would then pay a full reload.
            log("c2g-mlx: resident request failed: \(error)")
            print("ERROR: \(error)")
        }
        print(responseEndMarker)
        fflush(stdout)
    }
    log("c2g-mlx: resident mode — stdin closed, shutting down")
}

// ── Dispatch ─────────────────────────────────────────────────────────────────
if CommandLine.arguments.contains("--resident") {
    try await runResident()
} else {
    try await runOneShot()
}
