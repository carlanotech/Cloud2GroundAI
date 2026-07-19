# Ground-chat output folder — design note

**Date:** 2026-07-13 (overnight)
**Status:** proposal for Andrew's review — no code written yet
**Idea (Andrew):** point the Ground-mode local-AI chat window at a folder so the local model can put files it creates there.

---

## Is this crazy?

No — it's a good idea and a natural fit. Right now Ground mode is a conversation with local Granite when you're offline; useful, but everything the model produces is trapped in the chat. Letting its output land in a real folder turns Ground mode from "talk to a local model" into "get actual work product out of a local model with no internet" — which is exactly the off-grid, data-sovereignty story the product already sells. Claude/Cowork can already write to folders on the cloud side; this gives the offline side the same everyday usefulness. It reinforces, rather than complicates, the "your content stays on your machine" positioning.

The one thing to get right is **safety**: a local model must never be able to write wherever it wants. Handled below, it's very manageable.

## The core design tension

Local Granite has no tools — it only emits text. So "the model creates a file" really means "the app recognizes something in the model's text and writes it out." There are three levels of autonomy; I recommend starting at level 2.

1. **User-initiated save (simplest).** Every assistant message / code block gets a "Save…" affordance. The user clicks; the app writes it to the output folder. Secure by construction (a human chose to save), trivial to build. Good fallback, but clunky for multi-file output.
2. **Model-suggested, user-confirmed (recommended v1).** Prompt Granite in Ground mode to wrap any file it produces in a delimited block, e.g.:

   ```
   <<<FILE: helper.py>>>
   ...content...
   <<<END FILE>>>
   ```

   The app detects these blocks and renders a small card: *"Granite wants to save helper.py (1.2 KB) → [Save] [Save all] [Discard]."* On Save, it writes to the output folder with a sanitized name. Smooth for one or many files, and the human is still in the loop on every write. This mirrors the delimited-block convention the delegation skill already uses, so it's on-brand and predictable.
3. **Fully autonomous (not recommended for v1).** The model writes files with no confirmation. A local model hallucinating a bad filename or dumping twenty files is a footgun, and silent writes undercut trust. Keep a human in the loop until there's strong demand and strong guardrails.

## Safety rules (non-negotiable for any version)

- **One folder, chosen explicitly by the user.** A folder picker (`NSOpenPanel`) in Settings or the Ground window. Nothing is ever written outside it.
- **Confine every write to that folder.** Reject or relativize any filename containing `/`, `..`, a leading `~`, or an absolute path. Strip control characters. Empty/garbage name → a safe fallback (`ground-output-<timestamp>.txt`).
- **No silent overwrite.** If the target exists, confirm, or auto-suffix (`helper (2).py`). Never clobber.
- **Bounds.** Cap per-file size and files-per-save (e.g. 5 MB / 20 files) so a runaway generation can't flood the disk.
- **Sandbox reality (resolved 2026-07-14).** Checked `Cloud2Ground.entitlements`: **App Sandbox is currently OFF** (`com.apple.security.app-sandbox = false`, per the notarized-DMG dev path). So v1 can write to the user's chosen folder with a **plain path** — no security-scoped bookmark needed right now. **BUT** if ACT-007 later picks Mac App Store distribution, the sandbox turns on and this feature must switch to a security-scoped bookmark (capture from `NSOpenPanel`, persist, `startAccessingSecurityScopedResource()` / `stopAccessing…` around each write) or writes will silently fail. Build the write path so swapping in a bookmark later is a localized change.

## UX sketch

- **Settings → Ground:** "Chat output folder" row with the chosen path, a "Choose…" button, and "Reveal in Finder." Sensible default offered on first use (e.g. `~/Documents/Cloud2Ground`), created on demand.
- **Ground window header:** show the active output folder as a subtle chip with a Finder-reveal affordance, so the user always knows where files go.
- **In-chat:** file cards (level 2) with Save / Save all / Discard; a toast on success ("Saved helper.py → Cloud2Ground"). Any fenced code block also gets a quiet "Save…" (level 1) as a fallback.
- **Empty state / offline framing:** "Files you save here stay on your Mac — no internet, no upload." Ties the feature back to the product's core promise.

## Suggested v1 scope (smallest genuinely-useful cut)

1. Folder picker + persisted security-scoped bookmark (Settings + Ground header).
2. A Ground-mode system preamble instructing Granite to wrap files in the `<<<FILE: name>>> … <<<END FILE>>>` convention.
3. Parser that extracts those blocks (and, as a fallback, fenced code blocks) and renders Save / Save all cards.
4. Sanitized, confined, non-clobbering writes with the bounds above.

Defer: autonomous writing, folder trees / subdirectories, editing existing files, and any "the model reads files back" capability (that's a bigger surface with its own safety story).

## Why it fits the roadmap

- Makes the offline Ground mode a real productivity surface, not just a novelty chat.
- Strengthens the data-sovereignty pitch (work product created and stored entirely locally).
- Low blast radius if scoped to user-confirmed writes in one chosen folder.
- Reuses the delegation skill's delimited-block idiom, so the whole system feels coherent.

## Decisions (Andrew, 2026-07-14)

- **Folder:** the user always picks it explicitly — **no default** directory. (Defaults could land somewhere awkward depending on the Mac's settings.) First use prompts a folder pick; nothing is written until one is chosen.
- **Scope:** the v1 above is the whole feature. Likely won't need more than that — just normal bug-fixing as it's used. No folder trees, no autonomous writing, no read-back for now.
- **Save model:** **confirm each save** (level 2). **Auto-save is explicitly deferred to a future release** — and flagged as risky: auto-writing into a cloud-synced folder (e.g. ProtonDrive) can hit the same "Operation not permitted" wall we kept hitting this cycle, so it needs its own handling before it ships.
- **Sandbox:** currently OFF (see above) — plain paths for v1; revisit if App Store distribution is chosen.

*Green-lit for a future build. When we pick it up: I'll turn the v1 scope into reviewable Swift — folder picker (plain path now, bookmark-ready), the `<<<FILE>>>` block parser, and the confirm-each Save/Save-all cards. Build-and-test before shipping, as always.*
