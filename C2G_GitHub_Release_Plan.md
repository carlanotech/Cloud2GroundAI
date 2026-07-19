# Cloud2GroundAI — GitHub Release Plan

**Prepared:** June 2026
**Owner:** Andrew Carlile / Carlano Technology Solutions LLC
**Decisions baked into this plan:**

- **Private repo first.** Push privately, finish it, make public later.
- **Fill in all stub files** so every README link resolves before public launch.
- **Name is settled: "Cloud2GroundAI."** Remove the placeholder TODO.
- **Public launch is gated on Anthropic outreach** (legal positioning doc sent + acknowledged) given the Feb-2026 harness-ban context.

---

## Where the project actually stands

**Real and shippable today:**

- `c2g README.md` — strong, but references ~11 files that don't exist yet
- `skill/SKILL.md` — the routing orchestrator (the actual IP)
- `skill/models/` — `granite4.1.md` (487 lines, shipping model), `granite-code.md` (475 lines, legacy), `_generic.md`, `_template.md`, `model_families.json`, `README.md`
- `start_local_ai.sh` — working 455-line bash watcher, versioned protocol (v0.2.5)
- `ollama-delegate.skill` — packaged skill (zip)
- `CASE_STUDY_gethostname.md`, `whylocal.md`, `MODEL_TUNING.md` — supporting docs
- `C2G_Development_Roadmap.md`, `C2G_Anthropic_Legal_Positioning.docx` — internal/strategy

**The gap — files the README links to that don't exist yet:**

`LICENSE`, `NOTICE`, `CONTRIBUTING.md`, `NAMING.md`, `CHANGELOG.md`,
`protocol/SPEC.md`, `docs/faq.md`, `server/python-mcp/` (the MCP implementation),
`recommended-models.json`, `marketplace.json`, `.github/workflows/ci.yml`

If pushed public as-is, the repo would be full of broken links. That's why
"fill in the stubs first, stay private until done" is the right call.

---

## Two honest scope calls to make as you go

**1. The MCP server (`server/python-mcp/`) doesn't exist yet.** The README
presents it as the *recommended* path ("use the MCP server unless you have a
reason not to"). You have two choices and the plan supports either:

- **Option A — defer it.** Rewrite the README so the bash watcher is the
  shipping implementation and the MCP server is listed under "Roadmap / help
  wanted." Honest, shippable now, no Swift/Python MCP work required for v0.1.
- **Option B — build it before public launch.** More complete, but it's real
  new code. Recommend doing this *after* the private repo is up, as its own
  milestone — don't let it block getting the repo created.

This plan assumes **Option A for v0.1** and treats the MCP server as a
post-v0.1 milestone. Adjust if you'd rather build it first.

**2. The "Western-sourced / no-Chinese-software" framing.** It's a legitimate
ITAR/CMMC compliance angle. For public copy, consider leading with the neutral
version — "auditable provenance, Apache-2.0, US-headquartered vendors" — which
reaches the same regulated buyers and is harder to misread. Keep the explicit
framing if you want it; just make it a conscious choice. (Not a launch blocker
either way — flagged so it's deliberate.)

---

## Phase 0 — Get it on GitHub privately (do first, ~15 min)

The point is to get the existing work backed up and version-controlled
immediately, before any cleanup. Nothing here is public.

1. Create an **empty private repo**: `carlanotech/cloud-to-ground-ai`
   (private; don't add README/license/gitignore on creation).
2. Decide the repo root. Recommended: a **clean subfolder** containing only
   what ships — *not* the whole "Cloud2GroundAI" working folder (which
   holds the website, the legal docx, roadmap, etc. you may not want public
   later). See "What ships vs. what stays private" below.
3. Add a `.gitignore` (Python, macOS `.DS_Store`, `venv/`, the website folder).
4. Commit and push using the same `gh`-based flow that worked for the website.

**A reusable push script** (like `PUSH-ME.command`) pointed at the new repo
makes this one double-click. Claude can generate it.

---

## What ships vs. what stays private

| File / folder | Ships in repo? | Notes |
|---|---|---|
| `skill/` (SKILL.md, models/) | ✅ Yes | The core IP |
| `start_local_ai.sh` | ✅ Yes | The watcher |
| `README.md` | ✅ Yes | After cleanup (Phase 1) |
| `CASE_STUDY_gethostname.md` | ✅ Yes | Good credibility piece |
| `whylocal.md` | ✅ Yes | Good context |
| `ollama-delegate.skill` | ✅ Yes | Or rebuild from `skill/` at release time |
| `LICENSE`, `NOTICE`, `CONTRIBUTING.md` etc. | ✅ Yes | To be written (Phase 1) |
| `C2G_Development_Roadmap.md` | ⚠️ Your call | Internal strategy; many keep this private |
| `C2G_Anthropic_Legal_Positioning.docx` | ❌ No | Internal/legal — do not publish |
| `carlano-website/` | ❌ No | Separate repo (already `carlano-site`) |
| `MODEL_TUNING.md` | ⚠️ Check | Fold into `skill/models/` docs if redundant |

---

## Phase 1 — Fill in the stub files (private, the bulk of the work)

Each missing file, what it is, and the bar for "done." Roughly top-to-bottom
by importance.

### Legal / governance (quick, mostly boilerplate)

- **`LICENSE`** — Apache 2.0 full text. Standard, drop-in. Update copyright to
  "Carlano Technology Solutions LLC" (note: README currently says "Carlano LLC"
  — reconcile to the real legal name).
- **`NOTICE`** — Apache 2.0 NOTICE file: attribution for the project and any
  bundled third-party material.
- **`CONTRIBUTING.md`** — the contribution bar + the DCO sign-off requirement
  the README already promises ("Developer Certificate of Origin sign-off").
- **`CHANGELOG.md`** — start at `v0.1.0`; the watcher header already has a
  clean v0.2.x protocol history to seed it.

### The product spec (important — this is the "asset")

- **`protocol/SPEC.md`** — the README calls this *the* asset: the contract for
  handing one mechanical subtask from cloud to local. Extract it from the
  watcher's behavior (request.txt / response.txt / consumed.txt /
  processing.lock, the `# id:` echo, the v0.2.x changes). This already exists
  implicitly in `start_local_ai.sh` and `SKILL.md` — it just needs to be
  written up as a standalone versioned spec.

### Supporting docs

- **`docs/faq.md`** — README links here for "the audit-trail logic in detail."
  Cover: provenance/compliance reasoning, what data leaves the machine (none),
  why local output with occasional bugs still saves tokens (the table in
  SKILL.md), supported models.
- **`NAMING.md`** — README links it, but the name is now settled. Either write
  a short "name chosen: Cloud2GroundAI, here's why" note, or remove the
  README link entirely. (Simpler: remove the link.)

### Config files

- **`recommended-models.json`** — the README describes the update-nudge
  mechanism reading this. Define the schema (current recommended model +
  version + min Ollama version) and seed it with `granite4.1:8b`.
- **`marketplace.json`** — only needed for the Claude plugin marketplace track
  (Goal 2 in the roadmap). Can be deferred to the public/marketplace phase.

### CI (optional for v0.1)

- **`.github/workflows/ci.yml`** — the README has a CI badge. For a bash +
  skill repo, a light CI (shellcheck on the watcher, link-check on the
  markdown) is enough and makes the badge honest. Optional; can ship as
  "CI: pending" until then.

### README cleanup (do this last, once the above exist)

- Replace `# <!-- TODO: name -->` with **`# Cloud2GroundAI`**.
- Fix `Copyright 2026 Carlano LLC` → real legal name.
- If deferring the MCP server (Option A): rewrite the Quickstart and the
  "two implementations" section so the **bash watcher is the shipping path**
  and the MCP server is "Roadmap / contributions welcome."
- Verify every remaining link resolves (a link-check pass).

---

## Phase 2 — Pre-public review (private)

Before flipping the repo public:

- [ ] Every README link resolves (automated link check).
- [ ] No secrets, tokens, internal paths, or the legal docx in git history.
- [ ] License + NOTICE present and correct legal name throughout.
- [ ] `protocol/SPEC.md` matches actual watcher behavior.
- [ ] Decide MCP-server question (defer vs. build).
- [ ] Decide roadmap-doc question (publish vs. keep private).
- [ ] Compliance-framing language reviewed and deliberate.
- [ ] A fresh-eyes pass: clone the repo to a clean folder and follow the
      Quickstart exactly as a new user would. Fix whatever breaks.

## Phase 3 — Anthropic outreach (gates public launch)

Per the roadmap, this comes **before** public launch:

- [ ] Finish/send `C2G_Anthropic_Legal_Positioning.docx` to Anthropic.
- [ ] Get acknowledgement / feedback.
- [ ] Incorporate any requested changes.

The private OSS repo can be fully ready and waiting during this step.

## Phase 4 — Go public

- [ ] Flip repo to public.
- [ ] Tag `v0.1.0` release with release notes (GitHub Releases).
- [ ] Link the repo from the live site's Cloud-to-Ground page.
- [ ] (Optional) Community marketplace track: publish `marketplace.json` so
      users can `/plugin marketplace add ...`.

---

## Suggested order of attack (so nothing blocks getting backed up)

1. **Phase 0 now** — private repo, push what exists. (Removes the "it only
   lives in one folder" risk immediately.)
2. **Legal/governance files** — fast, mostly boilerplate. (Claude can draft.)
3. **`protocol/SPEC.md`** — the important one; extract from existing behavior.
4. **`docs/faq.md`, config JSON, README cleanup.**
5. **Phase 2 review.**
6. **Anthropic outreach** (parallel-safe — can run during 2–5).
7. **Go public + tag v0.1.0.**

---

## What Claude can draft for you

Most of Phase 1 is writing, which is cheap to delegate to Claude:
LICENSE/NOTICE (drop-in), CONTRIBUTING + DCO, CHANGELOG, `protocol/SPEC.md`
(from the watcher + skill), `docs/faq.md`, `recommended-models.json`,
`.gitignore`, the cleaned-up README, and the private-repo push script.
The MCP server (if you choose to build it) is the one real code lift and
should be its own focused effort.
