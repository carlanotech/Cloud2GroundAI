//
//  LocalOllamaClient.swift
//  Cloud to Ground AI — v0.2
//
//  HTTP client to a locally-running Ollama instance at 127.0.0.1:11434.
//  Used by the Ground chat for inference. Non-streaming for v0.2; streaming
//  is a v1.1 enhancement (set "stream": true in the request body and parse
//  chunked JSON responses).
//
//  Implements L2-AI-001 (local model conversational capability) — the
//  client side of the call. The actual model capability is provided by
//  granite4.1 running inside Ollama.
//

import Foundation

enum OllamaError: LocalizedError {
    case notReachable
    case badStatus(Int)
    case decodingFailed
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .notReachable:
            return "Could not reach Ollama at 127.0.0.1:11434. Is the service running?"
        case .badStatus(let code):
            return "Ollama returned HTTP \(code)."
        case .decodingFailed:
            return "Could not decode Ollama's response."
        case .emptyResponse:
            return "Ollama returned an empty response."
        }
    }
}

enum LocalOllamaClient {

    /// Send a chat request to Ollama and return the assistant's text.
    ///
    /// - Parameters:
    ///   - model: e.g. "granite4.1:8b"
    ///   - history: full message history per Ollama's format: [{role, content}, ...]
    /// - Returns: the assistant's response content as plain text
    static func chat(model: String,
                     history: [[String: String]]) async throws -> String {
        guard let url = URL(string: "http://127.0.0.1:11434/api/chat") else {
            throw OllamaError.notReachable
        }

        let body: [String: Any] = [
            "model": model,
            "messages": history,
            "stream": false,
        ]

        let bodyData: Data
        do {
            bodyData = try JSONSerialization.data(withJSONObject: body, options: [])
        } catch {
            throw OllamaError.decodingFailed
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = bodyData
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Generous — granite can take 30-90s for substantial responses.
        req.timeoutInterval = 120

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw OllamaError.notReachable
        }

        guard let http = response as? HTTPURLResponse else {
            throw OllamaError.notReachable
        }
        guard http.statusCode == 200 else {
            throw OllamaError.badStatus(http.statusCode)
        }

        // Ollama non-streaming response shape:
        //   { "model": "...", "message": { "role": "assistant", "content": "..." }, "done": true, ... }
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let message = json["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            throw OllamaError.decodingFailed
        }

        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { throw OllamaError.emptyResponse }
        return content
    }
}
