# Tuning: granite4.1

**Applies to:** `granite4.1:*`

**Status:** active (since 2026-06-27). Most recent characterization
2026-07-13 (Material Optimization) — 7/7 first-pass usable, watcher 0.2.10.

## Why this model

IBM Granite 4.1 (2026 release, Apache 2.0 license, available via Ollama in
3B / 8B / 30B sizes). Chosen as the C2G v1.0 local model family because:

- Much larger practical context window than granite-code (32K–128K vs 8K)
- Native code support, tool use, and structured JSON output
- Single family across two tiers (8B / 30B) keeps skill-maintenance overhead
  manageable
- IBM benchmarks claim 8B "beats 32B" competitors
- Apache 2.0 license is consistent with C2G's own license and the values
  positioning (western-built, auditable, open-source friendly)

## Watcher configuration

**As of 2026-07-01, `model_families.json` (this directory) is what
`start_local_ai.sh` actually reads at request time — the table below is
documentation for humans/Claude, not the enforced values.** If you change
a setting, change it in `model_families.json` first; update this table to
match. Do not duplicate these values in prompts.

**Prompt wrapping:** none. granite4.1 follows instructions directly without
a Q/A wrapper. The watcher passes the request body to Ollama as-is.

**Ollama options:**

| Option | Value | Why |
|---|---|---|
| `temperature` | 0.2 | Code tasks dominate the workload; lower temperature reduces formatting and idiom drift. |
| `repeat_penalty` | 1.05 | Default is fine; granite4.1 is not prone to repetition loops. |
| `num_predict` | 2048 | Most function-generation responses fit; multi-function batches may need more. |
| `stop` | (none) | granite4.1 ends cleanly on its own. |

**Output post-processing:** the watcher strips markdown code fences
automatically. granite4.1 sometimes wraps single code outputs in triple
backticks even when instructed not to; the strip handles it.

## Observed strengths

- **Multi-function batches.** A single prompt asking for 8 independent
  functions (one paragraph spec each) was implemented cleanly with 7 of 8
  verbatim. Don't be afraid to batch independent function specs in one
  delegation if the prompt fits the context budget.
- **Formula-to-code translation.** Given an equation in textual form, the
  model writes a direct Python implementation that matches the symbols
  in the source.
- **Docstring discipline.** When asked for "one-line docstring with units"
  the model produces exactly that. It does not pad with examples or
  rationale.
- **Stop-on-completion.** Output ends at the natural end of the requested
  artifact; no rambling tail.

## Observed weaknesses → mitigations

### Implicit unit-convention bugs in numerical code

**What goes wrong.** When implementing a formula whose original form
assumed one unit convention (e.g. degree-returning `arccos`), the model
writes the equation symbol-for-symbol against Python's
default-radian-returning `math.acos` without noticing the mismatch.
Result: silently-wrong numerical output — code that runs cleanly but
produces a number ~57× off.

**Specific failure (2026-06-27 STRUVE thermal session):** asked for
`eclipse_fraction = (1/180°) × arccos(...)`. Granite implemented
`return (1/180) * math.acos(...)`, missing that `math.acos` returns
radians and the correct normaliser is `1/math.pi`.

**Mitigation:**

- In the prompt, **explicitly state the unit convention of every math
  function used**. Example:
  `"Use math.acos which returns radians (not degrees). Normalise by π
  not by 180."`
- For any delegation involving numerical code, require ≥3
  published-reference sanity-check cases as part of the cloud
  verification pass.

### Python local-variable / function name shadowing

**What goes wrong.** The model writes assignments that shadow function
names in the same scope. Example:
`beta_star = math.radians(beta_star(altitude_km, r_earth_km))` —
this immediately triggers `UnboundLocalError` because the local name
binding makes `beta_star` non-callable on the right-hand side.

**Mitigation:**

- In the prompt for code that calls a named function inline, **say
  explicitly: "Do not reuse function names as local variable names."**
- Cloud verification should compile-and-run any delegated code, not
  just read it.

### AppKit / Foundation lifecycle: over-applies `weak` references

**What goes wrong (Swift).** When given a hint that mentions weak
references, granite over-applies them to AppKit objects that require
strong ownership by the responsible class. Specific failures observed
2026-06-28 in a `MenuBarApp.swift` delegation:

- Declared `weak var statusItem: NSStatusItem?` — but
  `NSStatusBar.system.statusItem(withLength:)` does NOT retain its
  return value. The owning object must hold a strong reference or the
  status item deallocates immediately and the menu bar icon never
  appears.

The same failure mode likely applies to `NSWindow`, `NSWindowController`,
and `NSToolbar` — all of which require strong ownership for their
expected lifetime.

**Mitigation:**

- In the prompt, **be explicit about which references are strong and
  which are weak**, and reference the specific AppKit object class.
  Example: `"The statusItem property must be a STRONG reference
  (NSStatusBar does not retain the status item it returns)."`
- Code review for Swift delegations should always verify lifetime of
  AppKit objects against Apple's documentation before accepting.

### SwiftUI app-launch wiring with AppDelegate

**What goes wrong (Swift).** When asked for a SwiftUI `@main` app that
also uses an `NSApplicationDelegate`, granite produces either:

- A `@main` struct without `@NSApplicationDelegateAdaptor` — the
  delegate class is defined but never instantiated by SwiftUI, so the
  delegate methods never run.
- A trailing top-level statement like
  `NSApplication.shared.delegate = AppDelegate()` — not valid in a
  `@main` SwiftUI app, and creates an instance that immediately drops
  out of scope.

**Mitigation:**

- In the prompt, name the exact wiring pattern:
  `"Use @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
  inside the @main struct. Do NOT add any top-level statements
  outside of the struct."`
- Cloud verification: confirm `@NSApplicationDelegateAdaptor` is
  present and there are no top-level statements outside types.

### Missing framework imports (Swift) — especially `import Combine`

**What goes wrong.** Granite produces Swift code that uses `@Published`,
`ObservableObject`, `@ObservedObject`, or other Combine-defined symbols
without `import Combine`. SwiftUI sometimes re-exports these symbols, so
the file *might* compile depending on Xcode version and SDK — but on a
fresh project with no SwiftUI ambient context, the build fails with 5-8
errors per file referencing "missing import of defining module 'Combine'."

Observed 2026-06-28 in `BridgeStatus.swift` — 8 compile errors all
traced to a missing `import Combine`.

**Mitigation:**

- In any Swift delegation that uses `ObservableObject`, `@Published`,
  `@StateObject`, `@ObservedObject`, `@EnvironmentObject`, or any
  Combine publisher/subscriber, **state in the prompt: "Include
  `import Combine` even though SwiftUI may sometimes re-export these
  symbols."**
- Cloud verification should grep for `Published\|ObservableObject\|
  ObservedObject` in delegated Swift and confirm `import Combine` is
  present.

### SwiftUI structural work is above the comfort zone

**What goes wrong.** When asked for a SwiftUI view with multiple
`Section`s, computed properties for colors based on enum cases,
`LabeledContent` rows with conditional rendering (`if let` for
optionals), and a refresh button with async action, granite4.1:8b
takes 2+ minutes to produce a response and the output is typically
30-50% wrong (incorrect modifiers, missing platform-specific tweaks,
form-style mismatches, missing `import Combine`).

Observed 2026-06-29: a `StatusPanelView.swift` delegation was
abandoned after 2 minutes; cloud wrote the file directly in ~5 minutes
of focused work. Net: faster overall to skip the delegation.

**Mitigation:**

- **Keep SwiftUI structural work in the cloud.** Specifically:
  views with 3+ `Section`s, computed properties driving conditional
  rendering, `Form`/`LabeledContent` idioms, async `Task` actions on
  buttons, animation modifiers.
- Granite is still suitable for **leaf Swift views**: a single
  `LabeledContent` row component, a button with one action, a
  `Text` styling helper.
- **Routing policy refinement** for the `code_generation` task class:
  "Swift / SwiftUI" is not a monolithic category. Granite handles
  AppKit lifecycle boilerplate (status item, window controller stubs)
  reasonably with explicit guidance, but SwiftUI Form / Section /
  Combine structural work should stay in cloud.

### Stylistic drift on loop direction

**Minor.** Granite sometimes iterates a range in an unconventional
direction (e.g. `range(n, 0, -1)` for a factorial loop where
`range(2, n+1)` would be more idiomatic). Functionally correct, mildly
unusual. **No mitigation needed** unless a downstream reader is strict
about idiom.

### Shell string-parsing with `grep`/`sed` — recurring, two failure shapes

**What goes wrong.** Ask granite for a POSIX-sh helper that pulls a value
out of text with `grep`/`sed` and it produces the right *shape* but
reliably trips on the fiddly bits. Two distinct shapes seen twice each
(2026-07-13, `bridge_delegate` build — `json_num` and `json_str` both hit
these):

- **Line anchoring.** It anchors the pattern with `^` (optionally
  `^ *"key"`), silently assuming each field sits on its own line. Fails on
  single-line JSON like `{"seq":100,"state":"idle"}` where the key is
  mid-line. Fix: use `grep -o`/`grep -Eo` with no `^` anchor.
- **`\s` and other GNU-only regex.** It writes `\s` for whitespace, which
  is a GNU grep extension — on the **BSD grep that ships with macOS** `\s`
  matches a literal `s`, so the pattern silently never matches. Fix:
  POSIX classes, `[[:space:]]`.
- **Nested quotes.** In a double-quoted shell string it writes an inner
  `"` unescaped, breaking the shell quoting outright; and it assumes no
  space after the JSON colon (`"key":"v"`), so it misses `"key": "v"`.
- **Exit-code logic.** It puts `$?`/`[ $? -eq 0 ]` after a `grep | sed`
  pipe and checks `sed`'s exit (always 0 on empty input), so the "field
  absent → return 1" contract doesn't fire. Fix: capture into a var and
  test `[ -n "$v" ]`.

**Mitigation.**

- For any shell text-extraction delegation, **state the constraints in the
  prompt**: "use `grep -o` with no `^` anchor (input may be one line); use
  `[[:space:]]` not `\s` (must run on macOS BSD grep); allow optional
  whitespace after a `:`; detect absence by testing whether the captured
  value is empty, not via `$?` after a pipe."
- Cloud verification should **run the function on a single-line input and
  on an absent-key input**, not just read it — both failure shapes pass a
  read and only fail at runtime.
- These are cheap to correct but recur, so this is often a *patch*, not a
  *verbatim* — factor that into routing. Structured *writers* (e.g.
  `printf` a JSON line) granite does verbatim; it's the *parsers* that
  stumble.

## Recommended prompts

**Pattern A — single function from a textbook equation:**

```
Implement a Python function `<name>(<args>)` per this equation:

  <equation in text, with units explicit>

Use only the math module. Use math.acos / math.asin / math.atan which
all return radians. Include a one-line docstring stating units of the
return value.

Return only the function definition. No example usage, no main block,
no markdown fences, no explanation.
```

**Pattern B — multi-function batch:**

```
Implement these N Python functions for <domain>. Use only the math
module. Each function should have a one-line docstring with units.
Be explicit about radian vs degree returns. Do not reuse function
names as local variable names. Return only the Python code, no
markdown fences, no example usage.

1. <name>(<args>): <one-line spec referencing source equation>
2. <name>(<args>): ...
3. ...
```

(Batches of up to 8 well-specified functions have worked in a single
delegation. Larger batches risk truncation against the watcher's
`num_predict` budget; split if you're unsure.)

## Additional routing rules (on top of SKILL.md universals)

Do **not** delegate to this model if any of these is true:

- The output will be used in flight-critical or safety-critical code
  without a separate verification pass with real reference values.
- The task involves prose with strict factual precision (cite-by-cite
  scholarly content, regulatory text). Granite is fluent but its facts
  can be subtly off; keep these in cloud.
- The prompt depends on the model recognising library-version-specific
  API behaviour. Granite's training cutoff lags actual current APIs in
  rapidly-moving frameworks.

## On the response-time timeout

The bridge protocol currently waits up to 90 seconds for a response. AAC
2026-06-29 raised that different users will have different patience —
users on slower machines running the larger Granite tier will see
slower responses than reference timings, and users in a hurry want to
fall back to cloud sooner. **The user-facing timeout for delegation
abort should be a settings-panel slider** (default 60s, range 15s-300s).
When the timeout fires:

- Mark the delegation `abandoned_for_cloud` in the log
- Send the same prompt to Claude directly
- The user sees no failure — just a slightly longer first response

Tracked in the Architecture Sketch's v1.1 list as a roadmap item.

## Session log

### 2026-07-13 — Material Optimization (first granite4.1 delegations on watcher 0.2.10)

Bridge came back with the new `status.json` heartbeat (model `granite4.1:8b`,
watcher 0.2.10, state idle/processing, `last_seen` epoch). All delegations
driven with correct protocol (idle-wait → write request w/ id → chunked ≤35 s
poll → `consumed.txt` ack).

| # | Function | Result | Round-trip |
|---|---|---|---|
| 1 | `axes_equal` | correct, spec-faithful | 8 s |
| 2 | `rel_error` | correct | 3 s |
| 3 | `si_multiplier` | correct — shipped into `engd.py` | ~18 s |
| 4 | `render_physicalproperties` | correct — shipped into `export_sldmat.py` | 10 s |
| 5 | `render_parameter_value` | correct — shipped into `export_engd.py` | ~17 s |
| 6 | `bulk_modulus_from_E_nu` | correct — shipped into `masterdb.py` | 12 s |
| 7 | `shear_from_E_nu` | correct, sent back-to-back after #6 | 3 s |

**Score: 7/7 first-pass usable.** #6 and #7 verified numerically against
N-BK7's known values (G = 34.0 GPa, K = 46.49 GPa). #6 → #7 were consecutive
with no watcher restart — the multi-request path is solid when the client acks
with `consumed.txt` (the earlier "one-request-then-stops" symptom was a
missing-ack client bug, not the watcher).

Reinforces the existing strengths entries: single math/helper functions and
template/pattern completion (fixed-line XML block, build-lines-and-wrap) came
back exactly to spec, every response opened with `def` as asked, no preamble
leaked, no stray fences. Round-trips 3–18 s at 8B on Apple Silicon.

Consistent with the standing caution "does only what the spec says":
`axes_equal` did not filter `None` values because the prompt didn't ask it to
— a reminder to name every edge case (empty list, None, both directions) in
the prompt rather than a model fault.

**Next data to gather before promoting to full confidence:** a harder task
with real edge cases (does it anticipate them?), a longer pattern-completion
(10+ entries, to check for N±1 drift), and one deliberately under-specified
prompt (to observe preamble / negative-constraint behavior).

Filed entry in `SE/delegation_log.jsonl`.

### 2026-06-29 (evening) — C2G v0.2 Xcode integration + macOS platform debugging

After Steps 4 and 5 were written, Andrew dropped the code into Xcode and we
spent ~2 hours debugging why the menu bar leaf icon wasn't appearing. The
build itself was clean from Step 5's self-check; the failure was entirely
on the macOS / Xcode platform side. Four lessons worth carrying forward:

1. **Don't add `NSApp.setActivationPolicy(.accessory)` when `LSUIElement`
   is already set in Info.plist.** Doing both produces a race during
   `applicationDidFinishLaunching`: the status item gets created before
   the app is fully registered as an accessory with the window server,
   and Control Center silently refuses to place it in the menu bar. The
   diagnostic signature is a status item whose button frame is correct
   (e.g. `32 × 27`) but whose window frame is at `(0, 0, 32, 0)` — bottom
   left of the screen with zero height. If you see that, remove the
   `setActivationPolicy` call. LSUIElement alone is sufficient.

2. **`GENERATE_INFOPLIST_FILE = YES` + an explicit `Info.plist` file is
   fine** as long as the keys don't conflict. Modern Xcode (16+) treats
   most Info.plist keys as Build Settings (`INFOPLIST_KEY_*`) and merges
   them with the explicit file at build time. Fighting this — trying to
   manually edit a "stale" file — is a wild goose chase. Set the keys in
   Build Settings, accept that the file content can be sparse, move on.

3. **macOS Launch Services caches app metadata aggressively during heavy
   iteration.** When you've been rebuilding a menu-bar app and changing
   plist keys, Control Center can get permanently confused about whether
   your bundle ID is a menu bar agent. `lsregister -kill -r -domain ...`
   helps but not always. **A Mac restart resolves more of these than any
   amount of cache invalidation.** This is not a defeat; it is a known
   macOS quirk for development.

4. **Build timestamp checking is the diagnostic move that breaks
   stuck-build cycles.** Run `stat -f "Built: %Sm" <app>/Contents/Info.plist`
   in Terminal. If the time hasn't updated since your last edit, Xcode
   is silently not rebuilding — your `[C2G]` console output is from a
   cached binary, and every "fix" you've made hasn't actually been
   compiled yet. The fix in that case: nuke
   `~/Library/Developer/Xcode/DerivedData/<project>-<hash>/` entirely,
   then ⇧⌘K + ⌘B.

**Routing decision (this session): all cloud, no delegation.** Same
class as the previous Step 5 and Step 2b entries — diagnostic + macOS
platform reasoning. Granite would have either failed silently or made
things worse by suggesting more code edits when the actual fix was
deleting code (the `setActivationPolicy` line) and clearing a system
cache.

**Anti-pattern observed in my own behavior worth flagging:** when the
icon didn't appear, I added MORE code (debug prints, fixed-length
status item, deferred frame logging) trying to diagnose. Each addition
made the problem harder to see. The breakthrough came from REMOVING
code and reverting to the morning's known-good MenuBarApp.swift. **For
SwiftUI/AppKit lifecycle bugs, "remove until it works again" beats
"add diagnostic instrumentation" almost every time.** Capture as a
debugging rule for future sessions.

**No delegation_log.jsonl entry** — diagnostic + cloud edits, no local
model use.

### 2026-06-29 — C2G v0.2 step 5 (Settings + skill auto-update)

Built four files in cloud, no delegation: `Preferences.swift` (UserDefaults
wrapper, ObservableObject), `SkillUpdateManager.swift` (manifest fetch,
semver compare, payload download, .bak rollback), `SettingsView.swift`
(3-tab SwiftUI Form), `SettingsWindowController.swift` (window owner).

**Routing decision: all cloud, no delegation.** Same class of work as
step 2a (StatusPanelView) — SwiftUI Form with multiple Sections,
LabeledContent rows, computed conditional views inside an enum switch,
async actions on buttons, two ObservableObject sources. Plus, the
update-manager logic carries privacy and rollback invariants that
benefit from end-to-end cloud reasoning rather than per-function spec
delegation.

**One observation worth capturing:** the cumulative time-cost of these
Step 5 files (~25 minutes) is comparable to what a single granite4.1:8b
delegation would have taken with the patch-time overhead AFTER abandoning
it once. The routing rule "SwiftUI structural work above 2 sections →
cloud" continues to be the right call.

**No delegation_log.jsonl entry** — pattern matches the step 2b note:
the decision NOT to delegate is itself a data point.

### 2026-06-29 — C2G v0.2 menu bar app, step 2b (BridgeProbe fixes)

Status panel showed "Ollama: Not installed" and "Watcher: Stopped" despite
both being up. Cloud diagnosed three layered macOS-platform issues that
no model — local or cloud — could have spotted without external
diagnostic output from Andrew's actual machine:

1. **App Transport Security blocking `http://localhost:11434`.** New
   Xcode SwiftUI projects don't have an NSAllowsLocalNetworking key. The
   URLSession call to the Ollama API silently throws, code falls through
   to the "installed-but-not-running" check, which then hits issue #3
   below and reports "Not installed."
2. **App Sandbox ON by default blocking `Process.run()`.** New Xcode
   SwiftUI projects ship with `com.apple.security.app-sandbox = true` and
   block both pgrep enumeration of sibling processes and outbound HTTP
   to localhost (unless `network.client` is set, which it isn't by
   default).
3. **`which ollama` only finds Homebrew installs, not GUI-app installs.**
   The original probe relied on PATH-based lookup. End users who install
   Ollama via the Mac .app put the binary at
   `/Applications/Ollama.app/Contents/Resources/ollama` — in no shell's
   PATH. Need explicit absolute-path candidate sweep.

**Routing decision (this fix): all cloud, no delegation.**

Rationale: the probe code itself is small and surgical, but the
*diagnosis* required:
- Knowing macOS App Transport Security rules
- Knowing which Xcode project template defaults are sandbox-on
- Knowing Homebrew vs GUI .app install locations
- Cross-checking with `pgrep` / `which` / `curl` output from the user's
  real machine to confirm where the failure was

That is exactly the class of work granite would have either skipped (it
doesn't reach for "is this an ATS issue?") or hallucinated answers for
(it would have likely written more code, not less, to "fix" the missing
PATH). **The fix was reading and reasoning, not generation.** The actual
code change was ~40 lines across one file plus a new 12-line entitlements
file and a 4-line Info.plist addition.

**Routing rule reinforced:** debugging-by-diagnosis (read the error,
reason about platform/runtime/permissions) is cloud-only. Code generation
within a well-understood specification is granite-suitable, but reaching
the well-understood specification is itself a cloud task.

**No delegation_log.jsonl entry** — this was diagnostic + cloud edit, no
local model invocation. The decision *not* to delegate is itself a data
point and worth noting here.

### 2026-06-29 — C2G v0.2 menu bar app, step 2a (Status Panel)

Tested: Swift StatusPanelView.swift — SwiftUI `Form` with 3 `Section`s,
`LabeledContent` rows with `if let` conditional rendering for optionals,
computed `Color` properties based on enum cases, `Task { await }` refresh
button.

**Score: abandoned (cloud completed in less time than waiting for
granite).** Granite took >2 minutes producing 4211 chars of output;
the cloud write took ~5 minutes start to finish including verification.

Three observations from the broader session:

1. **`import Combine` missing in BridgeStatus.swift delegation**
   produced 8 compile errors. Added as Observed-weakness entry.
2. **SwiftUI structural work** clearly above the comfort zone. Added
   as Observed-weakness entry with routing recommendation.
3. **AppKit boilerplate** (`StatusPanelWindowController.swift`) was
   written directly in cloud — a previous granite delegation on
   `MenuBarApp.swift` produced patchable but flawed window-lifetime
   code. Window controllers seem similar enough to remain cloud-side
   for now.

Filed entry in `SE/delegation_log.jsonl` as outcome
`abandoned_for_cloud`. This is a new outcome class — useful for
distinguishing "granite produced bad output we patched" from
"granite is too slow / unsuitable for the task class."

### 2026-06-28 — C2G v0.2 menu bar app, step 1

Tested: Swift code generation for a macOS menu bar app
(`MenuBarApp.swift` with SwiftUI `@main` + AppKit `NSStatusItem`).

**Score: ~50% first-pass usable.** Granite produced the right shape —
selectors, menu items, image template flag, basic structure — but
missed five things:

1. Missing `import AppKit` and `import SwiftUI`.
2. Missing `@NSApplicationDelegateAdaptor` in the `@main` struct.
3. `weak var statusItem: NSStatusItem?` — wrong lifetime; must be strong.
4. Trailing `NSApplication.shared.delegate = AppDelegate()` — invalid
   top-level statement in a `@main` SwiftUI app.
5. Menu items missing explicit `target = self` — items attached to
   `NSStatusItem` do not naturally find AppDelegate via the responder
   chain.

Cloud-side patch effort: ~5 minutes. Estimated effort reduction:
~50-60% vs. writing from scratch.

New entries added to the Observed weaknesses section for the AppKit
lifecycle and SwiftUI `@main` wiring patterns. Filed entry in
`SE/delegation_log.jsonl`.

### 2026-06-27 — STRUVE bus thermal estimator build

Tested: multi-function batch (8 spacecraft-thermal equations from
Gamaunt 2024 Ch. 3, plus standard albedo / IR / lumped-bus solver).

**Score: 7/8 first-pass usable.** The eighth (`eclipse_fraction`)
required two patches: a deg/rad unit fix and a local-variable shadow
removal. Total cloud-side patch effort: ~2 minutes vs an estimated
~15–20 minutes to write the eight functions from scratch.

Multi-function batching is now confirmed as a viable pattern for
granite4.1:8b. Updated the recommended-prompts section to reflect
this.

The unit-convention bug surfaced during a 10-case numerical sanity
check against Gamaunt's published reference values (view factor at
550 km, ISS eclipse fraction at β=0, etc.). The sanity-check approach
is **the** mechanism for catching this class of bug; without it the
code would have produced silently-wrong eclipse fractions ~57× too
small and only the user's downstream surprise would have surfaced
the issue.

Cold-start latency observed: ~19s on the first delegation after a
watcher restart, dropping to ~6s on warm subsequent delegations.
Cold-start is a real UX wart and is queued as a v1.1 roadmap item
(warm-up ping while user is active in Claude Desktop).

Filed entry in `SE/delegation_log.jsonl`.
