# Tuning: granite-code (IBM)

**Applies to:** `granite-code:3b`, `granite-code:8b`, `granite-code:20b`,
`granite-code:34b` and any future `granite-code:*` variant.

**Status:** Active default (as of 2026-06-20).

## Why this model

License-clean training provenance — IBM publishes training data sources
and licensing positions. This is the right default for customers in
government, defense, or regulated industries where "what was this model
trained on" is a procurement question. Also broad language coverage
(118 programming languages claimed) and strong docstring behaviour.

## Choosing a size

`granite-code` ships in four parameter sizes, each with **base** and
**instruct** variants. The bridge depends on instruction-following, so
**always use the instruct tag** (Ollama's bare `granite-code:8b` is the
instruct build; `granite-code:8b-base` is the foundation model — do not
delegate to a base variant, it will not honour the Q/A template).

All four sizes share the same watcher configuration below (IBM Q/A
template, greedy decoding, preamble stripper). Size only changes the
RAM/speed/capability trade — not how you prompt it. Pick by the host
machine, not by the task:

| Size | Disk (q4) | Min RAM | Round-trip (M-series) | Role |
|---|---|---|---|---|
| `3b`  | ~2 GB  | 16 GB | ~3–8 s   | Light/fast tier; low-RAM Macs; trivial one-liners |
| `8b`  | ~4.6 GB | 16 GB | ~10–25 s | **Default.** Best capability/speed balance on a laptop |
| `20b` | ~12 GB | 32 GB | ~30–90 s | High-RAM desktop only; fewer cloud review passes |
| `34b` | ~20 GB | 48 GB | minutes  | Workstation only; usually not worth it vs. cloud |

**Default is `8b`.** It's the sweet spot the whole pitch is built on:
fast enough that the latency tax is tolerable, small enough to run off
solar on an Air, capable enough that review-beats-rewrite holds most of
the time.

**Drop to `3b`** when the host is RAM-constrained (16 GB shared with
other apps), when you want the lightweight tier, or for genuinely
trivial mechanical work (one-liners, template fills, reformatting) where
8b's extra capability is wasted. Expect a lower first-pass hit rate —
lean harder on the structural-constraint and named-first-token
mitigations below, and review more carefully.

**Step up to `20b`/`34b` only on a high-RAM desktop or workstation**,
and only when the extra capability measurably cuts the cloud review
burden. Be honest about diminishing returns: at 20b+ the latency and
energy advantage that justifies local delegation erodes, and the
break-even shifts. Past ~20b on a laptop you're often better off just
routing the task to the cloud — the local round-trip costs more wall-clock
than the tokens it saves. The 20b/34b case is a high-memory machine where
the energy is still local and clean and you want to minimise cloud
round-trips, not raw speed.

**Context window.** Delegation prompts are gated under ~100 words by
`SKILL.md`, so the small-context tags are fine — `3b` (2K) and `8b` (4K)
default tags have ample headroom. The 125K-context tags exist but bring
no benefit to this workload and cost more RAM; don't pull them for the
bridge.

## Watcher configuration

**As of 2026-07-01, `model_families.json` (this directory) is what
`start_local_ai.sh` actually reads at request time — the values below are
documentation for humans/Claude, not the enforced ones.** If you change a
setting, change it in `model_families.json` first; update this section to
match. Do **not** add these to the prompt — the watcher handles it.

Note the match is on `granite-code` specifically, not `granite` broadly —
`granite4.1:*` is a separate family with its own entry (see
`granite4.1.md`) and does not get this wrapping.

**Prompt wrapping (mandatory):**

```
Question:
{prompt}

Answer:

```

This is the IBM-recommended template for Granite Code instruction-tuned
models. Without it, output quality and constraint compliance both degrade
noticeably.

**Ollama options:**

| Option | Value | Why |
|---|---|---|
| `temperature` | `0.0` | Greedy decoding — IBM recommends for instruction-following on code tasks. |
| `repeat_penalty` | `1.05` | Per IBM. Default 1.1 is too aggressive for code. |
| `num_predict` | `900` | Per IBM. Default 128 truncates real functions. |
| `stop` | `["<\|endoftext\|>"]` | Granite emits this token to mark end of answer; honour it. |

**Output post-processing:**

The watcher strips, in order:
1. Markdown code fences (``` and ```python etc.)
2. Natural-language preamble before the first `import`/`from`/`def`/
   `class`/`#!/`/`@`/`async def`/`if __name__` line, if the preamble is
   short (<400 chars, no indented blocks). This is necessary because the
   IBM Q/A template *encourages* Granite to give a natural-language
   answer, and we want the code-only payload.
3. Trailing whitespace.

## Observed strengths

- Correct code on well-specified tasks.
- Follows positive format instructions when phrased as numbered
  behavioural requirements.
- Handles bash, Python, simple Flask routes, JSON object construction
  cleanly.
- Fast on Apple Silicon (~10–25s round-trip for small tasks at 8B).
- Picks reasonable Python idioms (`sorted(set(...))`, `or fallback`,
  list comprehensions) when not over-constrained.

## Observed weaknesses → mitigations

### Looser on negative/exclusion constraints

Granite will sometimes ignore "don't," "no," "only" instructions on the
first pass. Observed examples:
- Asked for "return only the function" → preamble appeared anyway.
- Asked for "stdlib only" → imported third-party `netifaces`.
- Asked for "function and imports only" → stray `print(get_lan_ips())`
  at the end.

**Mitigation 1 — name the expected first token.** "Start with `def `"
or "Start with `import `" is the single highest-leverage trick. Granite
respects this almost always; it gives the model a clear anchor.

**Mitigation 2 — list forbidden opening phrases explicitly.** Don't say
"no prose." Say `No "Here's", "Here is", "This is", "Below is", "The
following" sentences.` Naming the actual patterns reduces (but does not
eliminate) preamble leakage. The watcher's preamble stripper handles
what survives.

**Mitigation 3 — put critical constraints under "Requirements (ALL must
be present):" with numbered items.** This phrasing lands consistently;
"please make sure to" does not.

### Quietly drops requirements it doesn't prioritise

Granite optimises for "code that runs" over "code that exactly satisfies
the constraint list." Observed: missing `set -e` in bash, missing type
hints in Python, missing error handling.

**Mitigation — make critical constraints structurally explicit:**

```
Requirements (ALL must be present):
1. Begins with `import socket` on line 1.
2. Uses only the Python standard library.
3. Includes the type hints exactly as shown.
```

Numbered, present-tense, with "must" or "ALL" lands consistently.

### "Describe the field" vs. "write the field" trap

When prompted to produce structured data (JSON, YAML), if you describe a
field as `"text": a SHALL statement requiring X`, Granite will copy the
description verbatim instead of writing the actual SHALL statement.

**Mitigation — show the verbatim opening:**

```
"text": "The instrument SHALL <verb> <object> ..."
```

or explicitly say "write the actual content here."

### Doesn't anticipate platform gotchas

Wrote `sudo python app.py` without noticing sudo strips `PATH` and
breaks venv resolution on macOS. Wrote `socket.gethostname()` LAN-IP
detection without knowing that returns `Mac.local → 127.0.0.1` on
macOS. Knowledge limit of a 7–8B model; mitigation is the senior-engineer
review pass, not better prompting.

### Assumes odd / canonical inputs

Centre-outward scan ordering written for odd N silently under-emitted
for even N. Granite reaches for the most-common case and doesn't
volunteer edge cases.

**Mitigation:** when even/odd or signed/unsigned or both directions
matter, name BOTH cases explicitly in the prompt.

## Recommended prompts

**Pattern completion (best Granite mode):**

```
Here is one row of a config dict:

    "pump_1": {"enable_addr": 0, "feedback_coil": 0, "label": "Pump 1"},

Continue the pattern for pump_2, pump_3, valve_1, valve_2, valve_3 — same
structure, addresses 1–5, labels "Pump 2", "Pump 3", "Valve 1", etc.

Output ONLY the dict entries (lines starting with `"pump_` or `"valve_`).
No surrounding dict braces. No comments. No prose. Start with `"pump_`.
```

**Single function:**

```
Write a Python function `parse_modbus_log(line)` that takes a string of the
form "2026-06-19 14:32:01 R Coil[3] = True" and returns
{"timestamp": "2026-06-19 14:32:01", "op": "R", "type": "Coil",
 "address": 3, "value": True}.

Requirements (ALL must be present):
1. Standard library only.
2. Use a regex.
3. Cast "True"/"False" strings to Python bools.
4. Cast the address to int.

Format constraints (ALL must be present):
- Output begins with `import`.
- No "Here's", "Here is", "This is", "Below is", "The following" sentences.
- No prose before or after the code.
- No markdown fences.

Output ONLY the imports and the function. Start with `import`.
```

## Additional routing rules (on top of SKILL.md universals)

Do **not** delegate to granite-code if any of these is true:

- The task requires noticing a constraint the prompt doesn't make
  structurally explicit ("don't break X," "preserve Y").
- The output needs to be exactly N items (Granite often produces N±1).
- The task is in a less-common language (Python/JS/Bash safe;
  IDL/MATLAB/Fortran less so).
- You need verbatim API-correct code against a specific library version —
  Granite will confidently hallucinate APIs.
- The task requires reasoning about a platform-specific gotcha (macOS
  TCC, sudo PATH stripping, etc.). Granite doesn't anticipate these.

## Session log

### 2026-06-19 — first Granite delegations (NCAR + Carlano)

Three delegations on Carlano Nude Foods + two on NCAR STG.

Granite produced correct code on 3/5 delegations on first pass. Failures:
- `get_lan_ips()` imported third-party `netifaces`, used macOS-broken
  `gethostname()` approach, added stray `print()` — full rewrite needed.
- One requirements-DB JSON entry: copied the field description verbatim
  instead of writing the SHALL statement.

Score: 3 / 5 first-pass usable.

### 2026-06-20 — IBM template + greedy + preamble stripper

After reading IBM's official prompting docs, applied three changes to
the watcher:

1. Wrap prompt in `Question:/Answer:` template.
2. Ollama options pinned to IBM-recommended values (greedy, repeat
   1.05, max 900, stop on `<|endoftext|>`).
3. Strip natural-language preamble before the first code-anchor line.

Regression test: re-ran the same `get_lan_ips()` prompt that failed
yesterday across three watcher versions. Results:

| | v0.2 baseline | v0.2.1 IBM template | v0.2.2 + preamble strip |
|---|---|---|---|
| stdlib only | ❌ | ✅ | ✅ |
| no stray print | ❌ | ✅ | ✅ |
| `startswith()` prefix filter | ❌ | ❌ | ✅ |
| no preamble | ❌ | ❌ | ✅ |
| droppable into a file | NO | NO | YES (modulo macOS bug) |

Key finding: **the IBM Q/A template improves constraint compliance but
encourages preamble**, because Granite was instruction-tuned to give
natural-language answers. Forbidden-phrase lists in the prompt don't
suppress the preamble; the watcher must strip it. The two layers
together produce first-pass-usable output ~80% of the time. The
remaining ~20% are domain-knowledge limits (platform gotchas) that no
amount of prompting can fix.

### 2026-06-20 afternoon — COSMO `occulter_axial_position_mm()`

Real systems-engineering delegation against the COSMO Filtergraph
project. Prompt asked for a piecewise-linear interpolation across three
calibration points (530, 1075, 1450 nm) with clamping, NaN handling,
type hint, and docstring.

**Granite output:** clean, format-compliant (no preamble, started with
`import math`), used `math.isfinite()` for the NaN/inf check (cleaner
than a hand-written check). Hit all three calibration points exactly.
33s round-trip with v0.2.2 protocol — id echo matched first try.

**The science bug — and who caused it.** The interpolation was
**non-monotonic** at the 1075 nm junction. Tracing it back: the bug
was in my prompt's upper-band branch, not Granite's translation. I
wrote `return 7914.0 - (lam - 1075) * (7914 - 7838) / (1450 - 1075)`
which gives a downward slope from 7914 — but the physical curve climbs
from 7838 to 7914 across 1075 → 1450. Granite implemented exactly what
I asked. Claude caught the bug on review.

**This is the textbook outcome the case study predicts.** Granite did
the mechanical translation work locally; Claude caught the science
error on review at low cost. The bug was a prompting error, not a
Granite error. A reviewer with no physical-monotonicity intuition would
have shipped it; the senior-engineer review pass is what makes this
workflow safe.

Score: 0.9 / 1 first-pass usable (function works; one-line sign fix
during review). The Granite-side technical execution was perfect.

### 2026-06-20 evening — COSMO `check_lyot_aperture_fit()`

Second Granite delegation in the same systems-engineering review.
Asked for a sanity-check function: takes a pupil diameter and a Lyot
clear aperture, returns a dict describing whether the beam fits with
adequate margin. Specified 11 behavioural requirements (status
thresholds, 3 ValueError paths, dict-keys-in-order, exact type hints,
one-line docstring, one-line human-readable message).

**Granite output:** clean, correct logic, all status thresholds right,
all three ValueErrors covered, dict keys in exact order, format-
compliant (started with `def`, no preamble, no fences). Two minor
issues caught on review:
- Docstring was multi-line instead of one-line as requested.
- The `message` field was multi-line with embedded `\n` separators
  instead of the one-line format requested. Tightened during integration.

Both issues are formatting drift on tightly-specified format rules.
Granite *technically* satisfied the spec ("a human-readable string,"
no requirement that it be one line) but missed the "one-line" qualifier
from earlier in the constraint list. Pattern observation: **Granite
tracks the most-recent strong constraint per field and can lose earlier
weaker constraints on the same field.** Mitigation in future prompts:
put "one-line" inside the field description, not as a separate item.

Score: 0.9 / 1 first-pass usable. Function logic was perfect; both
issues were cosmetic format drift.

### Aggregate score across today (2026-06-20)

Three Granite delegations this session, all through the v0.2.2 stack:
- `get_lan_ips()` regression test → first-pass-usable code with no
  third-party imports (improvement over yesterday's failure)
- `occulter_axial_position_mm()` → perfect logic; non-monotonicity was
  Andrew/Claude's prompt-sign error, not Granite
- `check_lyot_aperture_fit()` → correct logic; cosmetic format drift
  on multi-line message

Net: **the v0.2.2 stack reliably delivers first-pass-usable code on
well-specified mechanical tasks.** Real bugs that show up are either
prompt errors (catchable on review) or cosmetic format drift (fixable
in seconds). The protocol-level fixes (ID echo, race fix, IBM template,
preamble strip) are doing their job.

### Why the remaining ~20% is not a problem

The macOS `gethostname()` bug Granite kept reproducing is a clean
illustration of the system's value, not its failure.

When Granite produced the buggy `get_lan_ips()`, the cloud assistant
(Claude) caught the bug in one short review pass and wrote a corrected
function. The cloud tokens spent on "spot the bug + write the fix"
were a small fraction of what would have been spent if Claude had
written the function from scratch — reviewing is roughly 4× cheaper
than writing.

So the math on a partially-wrong Granite output still favours
delegation: Granite ran locally on the M-series Air (zero cloud
inference), Claude paid a small token cost to review and patch, and
the net cost was well below "Claude writes the whole thing."

This means **the threshold for delegating to Granite is much lower
than the threshold for accepting Granite's output verbatim.** Even
delegations that need significant cleanup are usually net wins. The
only true loss case is a Granite output so wrong that the cloud
assistant has to throw it out and rewrite from scratch — and even
then the loss is roughly the cost of the review pass itself, not
catastrophic.

Practical guidance: **delegate freely, review carefully, and don't
treat Granite's bugs as a reason to stop delegating.** The bugs are
the cost of doing business, and the business case still works.

### 2026-06-22 — added size-ladder guidance (3b/8b/20b/34b)

Added the "Choosing a size" section above. Source is IBM/Ollama public
specs (sizes, context windows, base-vs-instruct), not new delegation
traces. **Empirical status: only `granite-code:8b` has real session
data** (the 2026-06-19/20 entries above). The 3b/20b/34b RAM, speed, and
hit-rate claims are projections from public specs and the general
small-model trend, not measured here.

TODO before relying on the ladder in the product:
- [ ] Run the existing regression prompts (`get_lan_ips()`,
      `parse_modbus_log()`, the COSMO functions) against `granite-code:3b`
      and record a first-pass hit rate vs. 8b. Confirm the "lower hit
      rate, lean on mitigations" claim.
- [ ] Time a real round-trip on 20b/34b on whatever high-RAM machine is
      available to confirm the "past ~20b just use cloud" break-even.
- [ ] Once 3b has ~5–10 traces, decide whether it deserves its own
      addendum or stays folded into this file.

### 2026-06-22 — regression re-test on 8b (post-Qwen removal)

Re-ran the three documented prompts (pattern-completion dict,
`parse_modbus_log()`, `get_lan_ips()`) through the exact v0.2.1 watcher
code path against `granite-code:8b`. Context: the project went all-IBM
this session — `qwen2.5-coder:7b` and `qwen3.6` were removed from the
machine and scrubbed from the docs, so `granite-code:8b` is now the only
installed model.

| Prompt | Time | First-pass | Finding |
|---|---|---|---|
| pattern_completion_dict | 30.9s | content ✅ / format ❌ | preamble leaked past the stripper |
| `parse_modbus_log` | 29.1s | ✅ verified PASS | exact spec dict; minor `[R|W]` char-class smell |
| `get_lan_ips` | 25.3s | ❌ needs cloud fix | broken link-local filter + gethostname approach |

Score: **2 / 3 effectively usable**, consistent with the ~80% model.

**New, actionable finding — preamble stripper has a blind spot.** The
stripper in `start_local_ai.sh` only fires when the output's first
code-y line matches the anchor regex (`import |from |def |class |#!/|@|
async def |if __name__`). Pattern-completion output starts with an
indented quoted key (`    "pump_2": {...}`) — no anchor — so the
`"Here is the continuation...:"` preamble was NOT stripped and would
need manual deletion. This is the worst case because pattern completion
is Granite's *best* mode (see "Recommended prompts"). Proposed fix:
when a request declares its expected start token (the prompt here said
`Start with \`"pump_\``), pass that token to the watcher and anchor the
stripper on it as well. Until then: pattern-completion outputs need a
manual preamble trim, OR add the expected-prefix to the anchor set.

**`get_lan_ips` detail.** On this network `socket.gethostname()` +
`getaddrinfo` resolved to the real LAN IP (192.168.0.61), so the macOS
`Mac.local → 127.0.0.1` trap did NOT bite — it's network-dependent, not
universal. But the output still shipped a genuine bug: the link-local
guard `sa[0] not in ["127.0.0.1", "169.254"]` compares a full IP string
against the literal `"169.254"`, which never matches, so `169.254.x.x`
addresses leak through. Needs `.startswith("169.254.")`. Textbook
"review is 4x cheaper than rewrite" case — caught on read.

**`parse_modbus_log` detail.** Format-perfect and functionally correct
(verified against the spec dict). Only nit: the op group `(?P<op>[R|W])`
is a character class that also matches a literal `|`; harmless for R/W
input but technically `(R|W)` was intended.

### 2026-06-22 — fix: preamble stripper now anchors on expected-start (v0.2.3)

Implemented the fix proposed in the entry above. `start_local_ai.sh`
now supports an optional `# start: <token>` request line and, failing
that, auto-detects a `Start with \`X\`` instruction in the prompt. The
preamble stripper anchors on that token (allowing leading indentation)
in addition to the code keywords, stripping to whichever match comes
first.

Re-ran all three prompts through the updated logic against 8b:
- **pattern_completion_dict** → preamble GONE. Output now begins
  directly at `    "pump_2": {...}`. ✅ first-pass usable, no manual trim.
- **parse_modbus_log** → byte-identical to prior run (no regression).
- **get_lan_ips** → byte-identical (no regression).

`bash -n` and `python -m py_compile` on the embedded inference block
both pass. Net effect: pattern completion — Granite's strongest mode —
is now first-pass-clean end to end, closing the one real defect the
re-test surfaced. The latent `get_lan_ips` link-local-filter bug is a
model output issue, not a watcher issue, and remains a review-catch.
