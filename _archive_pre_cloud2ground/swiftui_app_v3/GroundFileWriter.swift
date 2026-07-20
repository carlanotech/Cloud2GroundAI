//
//  GroundFileWriter.swift
//  Cloud to Ground AI — v1.7 (Ground-chat output folder)
//
//  The single guarded path for writing a model-offered file to disk.
//  Every non-negotiable safety rule from the design note lives here so the
//  UI layer can't accidentally bypass one:
//
//    * Writes are confined to the user-chosen folder. Filenames are reduced
//      to a last path component and re-checked to be inside the folder, so
//      "../../etc/x" or an absolute path can't escape.
//    * No silent overwrite. If the target exists, auto-suffix " (2)", " (3)"…
//      and we write with .withoutOverwriting so even a race can't clobber.
//    * Bounds. Per-file cap (5 MB) here; files-per-save cap (20) exposed for
//      the caller to enforce on a batch.
//
//  Sandbox: App Sandbox is currently OFF (see Cloud2Ground.entitlements),
//  so a plain path works. If ACT-007 later selects Mac App Store
//  distribution, the caller must pass a folder URL resolved from a
//  security-scoped bookmark and wrap each write in
//  startAccessingSecurityScopedResource()/stop…; this writer's body does
//  not otherwise change.
//
//  Design note reference: planning/Ground-chat output folder — design.md,
//  "Safety rules (non-negotiable for any version)".
//

import Foundation

enum GroundFileWriter {

    static let maxFileBytes = 5 * 1024 * 1024   // 5 MB per file
    static let maxFilesPerSave = 20              // per Save-all batch

    struct WriteResult {
        let finalURL: URL
        let renamed: Bool   // true if auto-suffixed to avoid an overwrite
    }

    enum WriteError: LocalizedError {
        case invalidFilename(String)
        case encodingFailed
        case tooLarge(name: String, bytes: Int)
        case folderUnavailable
        case outsideFolder

        var errorDescription: String? {
            switch self {
            case .invalidFilename(let n):
                return "Can't save “\(n)” — unsafe or empty filename."
            case .encodingFailed:
                return "Couldn't encode file contents as UTF-8."
            case .tooLarge(let name, let bytes):
                let mb = Double(bytes) / 1_048_576
                return String(format: "“%@” is %.1f MB — over the 5 MB per-file limit.", name, mb)
            case .folderUnavailable:
                return "The chosen output folder is missing or not a folder."
            case .outsideFolder:
                return "Refused to write outside the chosen folder."
            }
        }
    }

    /// Reduce an arbitrary model-supplied name to a safe leaf filename.
    /// Returns nil if nothing safe remains. Path separators, "." and ".."
    /// are rejected outright rather than silently rewritten.
    static func sanitizedFilename(_ raw: String) -> String? {
        let base = (raw as NSString).lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty || base == "." || base == ".." { return nil }
        if base.contains("/") || base.contains("\0") { return nil }
        return base
    }

    /// Compute a non-colliding URL in `folder` for `name`, adding
    /// " (2)", " (3)"… before the extension if needed.
    static func uniqueURL(for name: String, in folder: URL) -> URL {
        let fm = FileManager.default
        let first = folder.appending(path: name)
        if !fm.fileExists(atPath: first.path) { return first }

        let ext = (name as NSString).pathExtension
        let stem = (name as NSString).deletingPathExtension
        var n = 2
        while true {
            let candidateName = ext.isEmpty ? "\(stem) (\(n))" : "\(stem) (\(n)).\(ext)"
            let url = folder.appending(path: candidateName)
            if !fm.fileExists(atPath: url.path) { return url }
            n += 1
        }
    }

    /// Write one file into `folder`, enforcing every safety rule. Throws a
    /// WriteError the UI can surface verbatim; never overwrites.
    @discardableResult
    static func write(_ file: ParsedFile, toFolder folder: URL) throws -> WriteResult {
        guard let name = sanitizedFilename(file.filename) else {
            throw WriteError.invalidFilename(file.filename)
        }
        guard let data = file.contents.data(using: .utf8) else {
            throw WriteError.encodingFailed
        }
        guard data.count <= maxFileBytes else {
            throw WriteError.tooLarge(name: name, bytes: data.count)
        }

        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: folder.path, isDirectory: &isDir), isDir.boolValue else {
            throw WriteError.folderUnavailable
        }

        let target = uniqueURL(for: name, in: folder)

        // Confinement re-check: the resolved parent must be exactly the folder.
        let parent = target.deletingLastPathComponent().standardizedFileURL.path
        guard parent == folder.standardizedFileURL.path else {
            throw WriteError.outsideFolder
        }

        try data.write(to: target, options: .withoutOverwriting)
        return WriteResult(finalURL: target, renamed: target.lastPathComponent != name)
    }
}
