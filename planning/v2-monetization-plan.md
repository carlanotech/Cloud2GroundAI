# Cloud2GroundAI — v2.0 Monetization Plan

**Status:** draft, 2026-07-08. Resolves SE action `ACT-007` (pick paid
distribution mechanism for v2.0).
**Target:** free preview ends 2026-11-30; paid v2.0 launches ~2026-12-01.
**Guiding preference (Andrew):** someone else manages the billing and tax and
takes a small cut — i.e. a Merchant of Record, not a build-it-yourself Stripe
integration.

---

## 1. The model

Source stays **Apache-2.0 and open**. We are not selling exclusive access to
the code — anyone can compile it. We sell the **maintained, signed binary**,
the **skill update channel** (kept current as Claude and the models evolve),
**support**, and premium features. The subscription funds ongoing maintenance.

Implication that shapes everything below: keep license enforcement **light**.
Don't invest in heavy DRM you can't enforce against someone building from
source. The paid value is *"someone keeps this current and supports it,"* not a
lock on the ability to launch the app.

## 2. How we take the money

**Not the Mac App Store.** The app installs Ollama, registers a LaunchAgent,
and writes into `~/Library` and `~/.claude` — all forbidden under App Store
sandboxing. So we stay outside the App Store (notarized DMG, as today) and
collect payment ourselves.

**Merchant of Record (recommended): Lemon Squeezy.** The MoR becomes the legal
seller, so they run checkout, recurring billing, **and global sales-tax / VAT
compliance** — for roughly **5% + 50¢** per transaction. That fee is the price
of never touching worldwide tax remittance, which is the right trade for a solo
operator.

Why Lemon Squeezy over Paddle: it has **native license-key management**
(generate / validate / deactivate) built in — exactly what a licensed desktop
app needs, saving real engineering — and setup is fast (live in ~an hour vs
Paddle's vetting queue). Reach for **Paddle** only if billing later gets
complex (usage-based, intricate trials). Verify current fees/terms at signup.

> Decision to confirm: **Lemon Squeezy** as the MoR. (Fallback: Paddle.)

## 3. What's free vs paid (needs Andrew's call)

The free public preview keeps basic delegation working. The paid tier should add
value, not gate core function. A proposed starting split — to be decided:

| | Free | Paid (subscription) |
|---|---|---|
| Local delegation (one model) | ✓ | ✓ |
| Automatic skill updates (kept current as models change) | limited / manual | ✓ |
| Larger / additional model slots | — | ✓ |
| Priority support | — | ✓ |
| Future premium features | — | ✓ |

Open pricing questions:
- Monthly, annual, or both? (Annual with a discount usually lifts retention.)
- Price point(s)? (Anchor to "less than the cloud tokens it saves you.")
- Free trial length, or does the whole v1 preview period serve as the trial?
- What happens to existing free-preview users at cutover — grandfather a
  perpetual free tier, or offer them a launch discount to convert?

## 4. Engineering work in the app (v2.0)

Lightweight licensing module:
- A **Settings → Account / License** panel: "sign in / enter license key."
- Validate the key against the Lemon Squeezy API; **cache the result with an
  offline grace period** so the app still works offline (matches the product's
  offline ethos) and survives brief network gaps.
- Periodic re-check; handle renewal, expiry, and deactivation gracefully
  (never hard-lock a user mid-session on a transient failure).
- Gate the paid features behind an active subscription; leave the free tier
  fully functional.

Scope is modest — a screen, an API call, a cached token, and feature flags.
Design it so a lapsed subscription degrades to the free tier, not to a brick.

## 5. Setup & operations (non-code)

- Create the Lemon Squeezy account under **Carlano Technology Solutions LLC**;
  configure store, payout bank account, and tax settings (MoR handles remittance).
- Create the subscription product(s) and price(s); configure license-key
  issuance and webhooks.
- Legal: a simple **EULA / Terms** and **Privacy Policy** for the paid app, and
  a **refund policy** (the MoR provides templates and handles refund mechanics).
- Decide branding on the checkout page (logo, colors).

## 6. Timeline (lots of runway — no rush)

- **Jul–Sep:** confirm platform; decide tiering + pricing; open the Lemon
  Squeezy account and set up products (no code needed yet).
- **Sep–Oct:** build the in-app license module; test the full buy → key →
  validate → unlock flow end to end.
- **Oct–Nov:** small private beta of the paid flow; finalize legal docs; set
  the existing-user conversion offer.
- **Nov 30:** free preview window closes. **Dec 1:** v2.0 paid launch.

## 7. Decisions needed from Andrew (the short list)

1. Confirm **Lemon Squeezy** as the Merchant of Record.
2. The **free-vs-paid line** (see the table in §3).
3. **Pricing:** monthly / annual, and the number(s).
4. **Trial** approach.
5. **Existing preview users** at cutover: grandfather or discount-to-convert.

Everything else I can draft or scaffold from those five answers.
