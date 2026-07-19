//
//  BridgeSmokeTest.swift
//  Cloud to Ground AI — v0.2 Setup Wizard support
//
//  The acceptance test for the whole bridge stack. Writes a real request
//  the way Cowork would, polls for the watcher's response, and reports
//  pass/fail with a short transcript.
//
//  This is the ONLY wizard step that proves Cowork → skill → bridge →
//  watcher → Ollama → response is wired correctly end-to-end. Without
//  this test, every other "✅" in the wizard is structural only.
//
//  Protocol (from start_local_ai.sh v0.2.4):
//    - Write request.txt with optional `# id: <uuid>` first line, then prompt.
//    - Watcher detects request.txt, runs inference, writes response.txt with
//      the id echoed back on its first line.
//    - Client reads response.txt and writes consumed.txt to signal it was
//      received. Watcher then cleans up response.txt + consumed.txt.
//
//  We deviate slightly: we never write consumed.txt because we just want
//  to read the response and let the watcher clean it up on the next loop.
//  This matches what Cowork's bridge integration actually does (the
//  cleanup happens lazily either way).
//

import Foundation

enum BridgeSmokeTest {

    /// Bridge folder where requests/responses round-trip.
    static var bridgeFolderURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Documents/claude_bridge/_bridge")
    }

    struct Result {
        let passed: Bool
        let transcript: String
        let durationSeconds: Double
        let detail: String  // user-facing summary line
    }

    /// Run the smoke test. Default prompt is intentionally trivial so the
    /// success criterion is just "the watcher answered with something
    /// non-empty in under timeoutSeconds." We don't grade the content.
    static func run(prompt: String = "Reply with the single word: OK",
                    timeoutSeconds: Double = 60.0) async -> Result {
        let start = Date()
        var transcript = ""
        func log(_ line: String) {
            transcript += line + "\n"
        }

        let requestID = UUID().uuidString
        log("→ smoke test id=\(requestID)")
        log("   prompt: \(prompt)")

        let fm = FileManager.default

        // Ensure bridge folder exists.
        do {
            if !fm.fileExists(atPath: bridgeFolderURL.path) {
                try fm.createDirectory(at: bridgeFolderURL,
                                       withIntermediateDirectories: true)
            }
        } catch {
            log("✗ failed to create bridge folder: \(error.localizedDescription)")
            return Result(passed: false,
                          transcript: transcript,
                          durationSeconds: Date().timeIntervalSince(start),
                          detail: "Could not create \(bridgeFolderURL.path).")
        }

        let requestURL = bridgeFolderURL.appending(path: "request.txt")
        let responseURL = bridgeFolderURL.appending(path: "response.txt")

        // Clear any stale files so we don't read a previous answer.
        for url in [requestURL, responseURL] {
            try? fm.removeItem(at: url)
        }

        // Write the request.
        let body = "# id: \(requestID)\n\(prompt)\n"
        do {
            try body.write(to: requestURL, atomically: true, encoding: .utf8)
            log("✓ wrote request.txt (\(body.count) bytes)")
        } catch {
            log("✗ could not write request.txt: \(error.localizedDescription)")
            return Result(passed: false,
                          transcript: transcript,
                          durationSeconds: Date().timeIntervalSince(start),
                          detail: "Could not write request.txt.")
        }

        // Poll for response.txt every 500ms up to timeout.
        let deadline = start.addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard fm.fileExists(atPath: responseURL.path) else { continue }
            // Read it.
            guard let raw = try? String(contentsOf: responseURL, encoding: .utf8)
            else { continue }

            // Validate id round-trip.
            let lines = raw.split(separator: "\n", omittingEmptySubsequences: false)
            let firstLine = lines.first.map(String.init) ?? ""
            let expectedHeader = "# id: \(requestID)"

            if firstLine.trimmingCharacters(in: .whitespaces) != expectedHeader {
                log("✗ response.txt first line did not echo our id")
                log("   expected: \(expectedHeader)")
                log("   got:      \(firstLine)")
                return Result(passed: false,
                              transcript: transcript,
                              durationSeconds: Date().timeIntervalSince(start),
                              detail: "Watcher returned a stale or mismatched response.")
            }

            let answer = lines.dropFirst().joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            log("✓ response.txt arrived (\(raw.count) bytes)")
            log("   answer: \(answer.prefix(200))\(answer.count > 200 ? "…" : "")")

            guard !answer.isEmpty else {
                return Result(passed: false,
                              transcript: transcript,
                              durationSeconds: Date().timeIntervalSince(start),
                              detail: "Watcher responded but the answer was empty.")
            }

            return Result(passed: true,
                          transcript: transcript,
                          durationSeconds: Date().timeIntervalSince(start),
                          detail: "Bridge round-trip OK (\(Int(Date().timeIntervalSince(start)))s).")
        }

        // Timed out.
        log("✗ no response.txt within \(Int(timeoutSeconds))s")
        return Result(passed: false,
                      transcript: transcript,
                      durationSeconds: Date().timeIntervalSince(start),
                      detail: "Watcher did not respond within \(Int(timeoutSeconds))s — is start_local_ai.sh running?")
    }
}
