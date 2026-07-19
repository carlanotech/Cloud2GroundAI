# Launch Decision & Anthropic Outreach Log

**Date:** 2026-07-13
**Owner:** Andrew Carlile / Carlano Technology Solutions LLC
**Subject:** Record of the pre-launch Anthropic outreach, the decision to ship the v1.0 free preview publicly, and a release-plan commitment to re-contact Anthropic before any subscription billing.

---

## 1. Purpose

This document records how Cloud2GroundAI (C2G) notified Anthropic before its public launch, what came back, how that was interpreted, and the resulting decision. It also updates the release plan with a firm commitment to re-open the conversation with Anthropic before the product begins charging money.

## 2. What was sent

**27 June 2026 — initial disclosure.**
A courtesy pre-launch email was sent to `usersafety@anthropic.com` (Anthropic's stated channel for "is my business/use case permitted under the Usage Policy" questions), with the positioning letter attached: `C2G_Anthropic_Legal_Positioning_Final_edited.docx`.

The letter describes, in full and accurately:

- What C2G is: a notarized macOS app (Apache 2.0) that installs a Cowork skill ("ollama-delegate") plus a local bridge watcher, letting Claude — running in the user's own Claude Desktop / CLI / Cowork install — delegate mechanical subtasks to a locally-installed IBM Granite model, with an offline Ground-mode chat fallback.
- Why it sits outside the February 2026 third-party-harness prohibition: **the C2G app never calls the Anthropic API, has no OAuth code path, and never touches Claude credentials or subscriptions.** All cloud inference happens inside the user's own, already-paid-for Claude client.
- The business model (Section 6): free Apache-2.0 preview now; a paid subscription later that funds ongoing maintenance of the skill/app — never access to Claude, which users always bring themselves.
- Four specific questions to Anthropic (Section 7) about commercial Cowork-skill distribution and any review process they'd recommend.

**27 June 2026 — Anthropic's response.**
A same-day automated acknowledgment from "Anthropic's Safeguards Team," templated: pointers to the Safeguards Center, the Help Center, and the account-appeals form, plus "our team will review your email and get back to you shortly." No engagement with the architecture or the Section 7 questions.

**13 July 2026 — follow-up.**
After ~16 days with no substantive reply, a follow-up was sent on the same thread. It clarified that this is a pre-launch architecture/policy question (not a safety incident, appeal, or banned-account matter), restated the core architecture, was candid about the future subscription and why clarity was being sought before investing, stated the intent to proceed in good faith if no response came, and asked to be redirected if `usersafety@` was the wrong team.

**13 July 2026 — Anthropic's response.**
Two automated replies: (1) "This conversation has been closed and is no longer monitored…" and (2) the same Safeguards Team template as before. The thread was auto-closed. No substantive engagement.

## 3. Interpretation

- `usersafety@anthropic.com` is an automated triage/appeals channel built for abuse reports and account issues. It templates and auto-closes; it is not staffed to give a developer a considered read on a commercial architecture.
- **An auto-closed ticket is not an objection.** No one at Anthropic reviewed the architecture and raised a concern; an automated queue simply closed. Absence of a substantive reply is neither approval nor objection.
- The good-faith disclosure bar the project set for itself has been met to the fullest extent this channel allows: the full product and business model were disclosed **twice**, in writing, with the architecture spelled out, through the channel Anthropic itself points to, with an explicit invitation to object before launch — and no objection was raised.

> Note: This is an internal good-faith record, not legal advice or legal clearance. It documents diligence and intent; it is not a determination that the product complies with any agreement. If/when the product begins charging, a review by an attorney familiar with software licensing and platform terms is advisable.

## 4. Decision

**Proceed with the Cloud2GroundAI v1.0 public preview.**

- **Launch date:** 2026-07-14 (the day after this record).
- **What ships:** the free, Apache-2.0 preview — Mac app v1.6, skill 0.4.0, watcher v0.2.9 — distributed as a notarized DMG via GitHub Releases, with the source public.
- **Basis for proceeding:** the preview is free; the app never touches the Anthropic API, credentials, or subscriptions; every user brings their own Claude; and the architecture and business model were disclosed to Anthropic in good faith with no objection raised.
- **Standing commitment:** C2G remains ready to modify, hold, or rework the release if Anthropic raises any concern at any time. The data-sovereignty commitments (no collection of user content, conversations, or files; feedback/telemetry opt-in and off by default) are unchanged.

## 5. Release-plan update — re-contact before any subscription charge

The paid subscription (v2.0) is the point at which money begins to change hands and is therefore the point that most warrants a second, better-aimed conversation with Anthropic.

**Commitment:** Before Cloud2GroundAI begins **any** subscription billing, Carlano Technology Solutions LLC will re-contact Anthropic — **target: September 2026** — through a channel more appropriate than the safety inbox (e.g. `sales@anthropic.com`, developer/partnership support via the Anthropic Console, or a named developer-relations contact if one can be found), using the commercial/partnership framing, and will allow a reasonable window for a response before charging.

- No subscription billing begins until that outreach has been made and a reasonable response window given.
- If Anthropic engages and requests changes, they will be made before charging.
- This is a firmer commitment than the free-preview standard precisely because the paid tier changes the stakes.

## 6. Go-live checklist for 2026-07-14

These are the concrete steps to take the product public. Repo-visibility changes and Releases are manual actions (website or `gh`); they are not done by this document.

1. **Pre-flight — land the `SkillInstaller` fix.** Add `"bridge_delegate"` to `topLevelFiles` in `SkillInstaller.swift` and rebuild the v1.6 DMG, so the flat-bundle install fallback cannot silently drop the v0.4.0 helper. **Do this before the public DMG is the one attached to the Release.** (Open item as of this writing.)
2. **Make the repo public.** `carlanotech/Cloud2GroundAI` → Settings → Danger Zone → Change visibility → Public. (Decide separately whether `carlano-site` goes public too.)
3. **Create the two GitHub Releases** with assets attached:
   - `skill-v0.4.0` → `ollama-delegate-0.4.0.zip`
   - `v1.6` → `Cloud2GroundAI_v1.6.dmg` + `.dmg.sha256` (+ User Guide PDF if desired)
4. **Verify the in-app updater** now resolves 0.4.0 once the repo is public and the `skill-v0.4.0` asset exists (the manifest's `payload_url` points at that Release asset; it 404s while private).
5. **Sanity check on a second machine** if possible: install the DMG, run Setup, confirm the deployed skill reads 0.4.0 and `bridge_delegate` is present.

## 7. Reference — versions shipped

| Component | Version |
|---|---|
| Mac app | 1.6 |
| ollama-delegate skill | 0.4.0 |
| Bridge watcher (`start_local_ai.sh`) | 0.2.9 |
| Bridge protocol | v0.2.5 + additive `status.json` heartbeat |

## 8. Contact of record

Andrew Carlile — carlanotech@pm.me — Carlano Technology Solutions LLC, Boulder, Colorado, USA.
