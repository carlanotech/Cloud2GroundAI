//
//  FileBlockParser.swift
//  Cloud to Ground AI — v1.7 (Ground-chat output folder)
//
//  Pure, side-effect-free parser for the "model-suggested file" idiom.
//  When Granite (Ground mode) is asked to produce a file, it wraps the
//  file in a delimited block:
//
//      <<<FILE: helper.py>>>
//      def helper(): ...
//      <<<END>>>
//
//  This parser extracts every complete block from a message and returns
//  (filename, contents) pairs. It does NOT touch the filesystem and does
//  NOT sanitize filenames — that is GroundFileWriter's job, kept separate
//  so this stays trivially unit-testable. An unterminated block (no
//  <<<END>>>) is ignored rather than partially saved.
//
//  Design note reference: planning/Ground-chat output folder — design.md,
//  "Model-suggested, user-confirmed (recommended v1)".
//

import Foundation

/// One file offered by the model. `id` is per-instance so SwiftUI ForEach
/// is stable within a render; equality for tests compares the real payload.
struct ParsedFile: Identifiable, Equatable {
    let id = UUID()
    let filename: String
    let contents: String

    static func == (lhs: ParsedFile, rhs: ParsedFile) -> Bool {
        lhs.filename == rhs.filename && lhs.contents == rhs.contents
    }
}

enum FileBlockParser {
    static let openPrefix = "<<<FILE:"
    static let openSuffix = ">>>"
    static let closeMarker = "<<<END>>>"

    /// Extract all complete <<<FILE: name>>> … <<<END>>> blocks, in order.
    /// Content between the markers is preserved verbatim (including blank
    /// lines and indentation). The marker lines themselves are dropped.
    static func parse(_ text: String) -> [ParsedFile] {
        var results: [ParsedFile] = []
        let lines = text.components(separatedBy: "\n")

        var i = 0
        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)

            let isOpener = trimmed.hasPrefix(openPrefix)
                && trimmed.hasSuffix(openSuffix)
                && trimmed.count > openPrefix.count + openSuffix.count

            if isOpener {
                let nameStart = trimmed.index(trimmed.startIndex, offsetBy: openPrefix.count)
                let nameEnd = trimmed.index(trimmed.endIndex, offsetBy: -openSuffix.count)
                let filename = String(trimmed[nameStart..<nameEnd])
                    .trimmingCharacters(in: .whitespaces)

                // Accumulate body lines until the close marker.
                var body: [String] = []
                var j = i + 1
                var closed = false
                while j < lines.count {
                    if lines[j].trimmingCharacters(in: .whitespaces) == closeMarker {
                        closed = true
                        break
                    }
                    body.append(lines[j])
                    j += 1
                }

                if closed && !filename.isEmpty {
                    results.append(ParsedFile(filename: filename,
                                              contents: body.joined(separator: "\n")))
                    i = j + 1
                    continue
                }
                // Unterminated or unnamed block: fall through, skip this line.
            }
            i += 1
        }
        return results
    }
}
