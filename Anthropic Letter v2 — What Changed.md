# Anthropic Letter — what changed in v2 vs the 20 June 2026 draft

Quick reference so you can spot the deltas before sending. The v2 docx is `C2G_Anthropic_Legal_Positioning_v2.docx`; the original draft (`C2G_Anthropic_Legal_Positioning.docx`) is unchanged on disk for comparison.

## Section 1 — Purpose

Unchanged in intent. Added a sentence acknowledging this is v2 of an earlier 20 June draft and that the architecture/business model have evolved since.

## Section 2 — Background on the harness ban

Unchanged. Still describes the February 2026 policy accurately.

## Section 3 — What C2G is

**This is the biggest change.** The original described C2G as a Cowork skill + watcher + bridge protocol. The v2 describes it accurately:
- A native macOS SwiftUI app
- Apache 2.0 licensed
- Three operating modes: Cloud, Hybrid, Ground
- v1.0: user provides their own Anthropic API key (pay-as-you-go)
- Local model: IBM Granite 4.1 via Ollama
- No server component; the only credential handled is the user's own API key, stored in macOS Keychain

Sub-section 3.1 ("How it works") is rewritten per-mode with explicit data-flow descriptions.

Sub-section 3.2 ("What it is not") is rebuilt around the new "no OAuth code path, no subscription tokens" argument rather than the original "we live inside Cowork" argument. The new framing is stronger because the underlying claim is structural (the product literally cannot touch subscriptions because it has no code for that) rather than positional.

## Section 4 — Third-party licensing

Updated:
- "IBM Granite Code" → "IBM Granite 4.1" (the specific model family chosen 27 June)
- Added: C2G is itself Apache 2.0 for v1.0
- Clarified: the Cowork plugin system / ollama-delegate skill is used by the C2G dev team for their own work but is not the distributed product
- Ollama and IBM references kept

## Section 5 — Key distinction

Rebuilt around three explicit points:
1. **Billing:** user pays Anthropic directly; C2G never sits in the billing path
2. **Credentials:** the product has no OAuth code path and no way to access subscriptions
3. **Token volume:** C2G reduces per-task cloud tokens via legitimate optimisation (delegating mechanical work to local), the same kind of optimisation a thoughtful developer would do by hand

New framing: C2G is "precisely the kind of commercial macOS app the Anthropic API exists for: a paying API customer building a product around the API." That's a much stronger position to be in than arguing absence of a harmful behaviour.

## Section 6 — Business model

Rewritten. Original said "freemium plugin/skill package, users pay for additional capabilities." v2 says:

- **v1.0:** Free public preview through 2026-11-30. Apache 2.0, notarized DMG via GitHub Releases. User provides their own API key.
- **v2.0:** Paid subscription release from 2026-12-01. Distribution mechanism chosen by 2026-10-15 (ACT-007 — App Store vs notarized DMG + Paddle).
- What we sell: the connection, the maintained skill, the auto-update channel
- What we don't sell: Claude (the user has their own key), Granite (open source on their machine)
- What we don't collect: user content, conversations, files. Data sovereignty as an L1 commitment. Only opt-in feedback and opt-in anonymized usage, off by default.

Also added the off-grid / off-mains / carbon-conscious positioning explicitly. Anthropic may find this a useful trust-and-safety alignment story.

## Section 7 — Request to Anthropic

Original asked three questions about plugin marketplace use. v2 asks four updated questions about commercial API consumption:

1. Whether the product requires partnership / registration / additional terms beyond the standard API customer agreement
2. Whether Anthropic has architecture concerns to address before the v1.0 launch (early July 2026)
3. Whether Anthropic wants to be acknowledged in the about / settings panel as the cloud AI provider, alongside IBM and Ollama
4. Whether there's a product / trust-and-safety review process Anthropic would recommend

Added: openness to partnership conversation around data-sovereignty and carbon-transparency angles.

## References section

Updated to point at granite4.1 specifically on Ollama, not granite-code.

## Tone

The v2 reads slightly more confident than the v1 — because the underlying position is structurally stronger (we're describing a commercial API customer building a product, not threading a needle around a Cowork plugin). The language is professional and respectful but no longer apologetic.

## Things deliberately NOT in v2

- Speculative business numbers (revenue, user counts)
- Anything that could be read as challenging Anthropic's enforcement decisions on OpenClaw / OpenCode — those were correct calls and we don't need to relitigate them
- Promises about specific Anthropic features or partnerships
- Any claim about competitive positioning relative to Anthropic products

## Suggested next steps before sending

1. Read it once end-to-end. Mark anything that doesn't match how you'd describe the product yourself.
2. Confirm the launch date claim — "early July 2026" is in there as a soft commitment; if that's too soon, change it.
3. Decide the recipient. The original draft was prepared for "Anthropic review" generally — typical entry points are developer.relations@anthropic.com or the trust-and-safety contact in your API console. If you have a direct contact from your previous Anthropic conversations, that's the cleanest path.
4. Optional: send a cover note (one paragraph email body) saying "Attached is a description of a commercial product we're launching that uses the Anthropic API. We wanted to make sure the architecture aligns with your terms before we go public. Happy to discuss." Keep it short.
