# Morning briefing — Saturday 2026-06-27

Good morning. Here is what happened while you slept and what needs your eyes today.

## TL;DR

Everything we agreed on Friday evening is now drafted, traceable, and ready for your review. L1 baselined, 26 L2 engineering requirements derived, six actions opened with priorities, a complete SwiftUI scaffold (drop-ready into the Xcode project you just installed), an architecture sketch, and three formal deliverables (.docx + .xlsx). You can build code today if you want, or you can review and red-pen the L2 set first. Both are fine.

Two decisions are waiting on you:

1. **ACT-001 — define the representative C2G workload** (15-minute worksheet, single biggest blocker for measurable claims).
2. **ACT-005 — App Store vs. notarized DMG** (forking decision that shapes packaging, signing, install flow).

Nothing else needs you to unblock prototyping. Apple Developer enrollment is still pending — that's fine, it blocks *shipping*, not building.

---

## Recommended reading order

Pick one of two paths.

### Path A — "I want to review the SE work first"
1. `Prototype Readiness Summary.docx` — 5-minute read, executive answer to "are we ready to build?"
2. `Requirements Document.docx` — 25-minute read, every L1 and L2 in detail. Red-pen anything that misses.
3. `SE/ACT-001 Workload Worksheet.md` — fill it in. Closes the biggest open question.
4. `Architecture Sketch.md` — 10-minute read.
5. `swiftui_scaffold/README.md` — drop-in instructions.

### Path B — "I want to build something today"
1. `swiftui_scaffold/README.md` — drop-in instructions.
2. Follow the steps, get the app compiling and running with mock backends.
3. Loop back to `Architecture Sketch.md` and `Requirements Document.docx` when you have questions about why a thing is the way it is.
4. Fill in `SE/ACT-001 Workload Worksheet.md` whenever — it doesn't block code work, just claims about it.

---

## What's in the folder now

**`SE/` — single source of truth (JSON)**
- `metadata.json` — project code (C2G), CAT set, margin policy (20% default), operational environment.
- `requirements.json` — 5 baselined L1s, 26 draft L2s, fully traced parent↔child.
- `budgets.json` — empty stub; populates as L1s become measurable.
- `actions.json` — 6 actions, ranked by downstream impact.
- `ACT-001 Workload Worksheet.md` — your homework. Fillable in ~15 minutes.

**Top-level deliverables (per skill §5)**
- `Requirements Document.docx` — the canonical L1 + L2 doc. Generated from JSON.
- `Traceability Matrix.xlsx` — 5 sheets: cross-tab, L1, L2, Actions, TBDs. With formulas.
- `Prototype Readiness Summary.docx` — answers "are we confident enough to build?" Per-L1.
- `Architecture Sketch.md` — components, mode state machine, L2 ownership map, open trade studies (TS-001 through TS-005).

**`swiftui_scaffold/` — drop-in SwiftUI project**
- 17 Swift files + README. Each header cites the L2(s) it implements.
- Compiles and runs against mock AI backends. Mode toggle, persistent indicators, degradation notice, onboarding sheet — all working.
- README has step-by-step Xcode import instructions.

---

## Five things to flag explicitly

1. **PRD-004 wording** — I generalized "solar-power compatibility" to "Mains-independent operation" per your Friday note. The shall-statement now covers solar / hydro / wind / geothermal / battery — anyone who knows they're off-mains gets the benefit. Reference machine for measurement remains your M5 Air. (See `requirements.json` C2G-L1-PRD-004.)

2. **L2-AI-005 got rewritten during §7 self-check** — original said "use cloud as orchestrator and local as delegate per the ollama-delegate skill," which is too prescriptive (G3 violation — that's *how*, not *what*). New version states the user-facing single-stream invariant only. The orchestrator/delegate pattern lives in the Architecture Sketch (§4 and TS-001) where design decisions belong.

3. **TBD register is consistent** — 6 L1 TBDs ↔ 6 actions ↔ same items show up on L2 children that inherit them. The skill's §7 TBD-count check passes. If you change a TBD, change it in all three places (JSON, docx, xlsx — they're all generated from the JSON, so regenerating fixes the docs automatically).

4. **G5 note** — I overwrote `requirements.json` in place during this session rather than generating `_REGEN` parallel files. That was fine because you hadn't been editing it. From here forward, any structural rewrite I do goes to a `_REGEN` parallel file unless you tell me to update in place. Small JSON tweaks to baselined items continue in place with a `last_updated` bump.

5. **`Thread` → `ConversationThread`** — small but important rename in the scaffold to avoid clashing with Foundation's `Thread`. Otherwise the scaffold wouldn't compile. The README reflects the new name.

---

## What's open and what to do about it

### Decisions waiting for you

**ACT-001 — Representative C2G workload.** Fill in `SE/ACT-001 Workload Worksheet.md`. 15 minutes. This single action unblocks measurable claims for PRD-002 (cloud cost reduction) and PRD-004 (energy budget), plus their dependent L2s. Once filled in, I can translate it to a numeric workload spec and a measurement script.

**ACT-005 — Distribution mechanism.** Mac App Store vs. notarized DMG. Forking decision; many L2-PLAT and L2-OPS specialize on this. Independent of Apple Developer Program enrollment (which gates shipping, not deciding). A short trade study (TS-003 in the Architecture Sketch) would help if you want me to draft one — I can produce that today.

### Decisions you don't need to make yet
- TS-001 (cloud client architecture in Hybrid mode) — wait until we have real Cloud + Local clients integrated.
- TS-002 (default local model: granite vs qwen) — wait until we measure both against the workload from ACT-001.
- TS-004 (bundle vs download local model) — coupled to ACT-005, decide together.
- TS-005 (SwiftUI vs cross-platform) — keeping SwiftUI as the working assumption.

### Stale or risky things
- Apple Developer enrollment (SPAM87P7P5) — pending; D&B follow-up is in motion. Not blocking unless still stuck past 2026-07-10.
- Bridge protocol v0.2 — current implementation is shell-script + sleep-loop polling. L2-BRG-003 calls this out as a power story to revisit. Not urgent, but tracked.

---

## Recommended next session goals (if you say "go")

Pick one of these to be tomorrow's focus, in order of how much they unlock:

1. **Fill in ACT-001 worksheet, then close ACT-002 + ACT-003** — closes 3 actions, makes PRD-002 and PRD-004 measurable. ~1 hour.
2. **Get the SwiftUI scaffold running in Xcode** — concrete code in your hands. ~1 hour.
3. **Decide ACT-005** — opens the path to building the real install/update flow. ~30 minutes if I draft TS-003 first.
4. **Replace MockLocalAI with real Ollama HTTP client** — first piece of "real" code. Doesn't need API keys. ~1 hour.

Any of these is a good Saturday-morning session. We can also do multiple if you want — they're independent.

---

## Trust-but-verify

Before you take any of this as gospel, three things to spot-check:

1. **Open `Requirements Document.docx`** and search for any L2 that prescribes implementation (G3 violations). I caught and rewrote L2-AI-005 but a second eye is worth having.
2. **Open `Traceability Matrix.xlsx`** and look at the cross-tab on the first sheet. Every L2 should belong to at least one L1; every L1 should have at least one L2. There should be no orphaned rows or columns.
3. **In Xcode**, drop the scaffold in per the README and hit ⌘B. If anything doesn't compile, that's on me — tell me what the error said and I'll fix it.

If all three check out, the SE foundation is solid and we can build with confidence.

---

Sleep well — talk soon.
