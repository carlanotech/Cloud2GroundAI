# Per-Model Tuning Files

This directory holds the model-specific knowledge that makes the local-AI
bridge productive. Each file documents how to prompt one specific local
model effectively, what its failure modes are, and how to work around them.

The orchestrator (`SKILL.md`) is model-agnostic. It looks up which model
is currently active and loads the matching file from this directory.

## Currently tracked models

| File | Model(s) | Status | Notes |
|---|---|---|---|
| `granite-code.md` | `granite-code:*` | active default | IBM Granite Code. License-clean training data. Federal/enterprise pitch. |
| `_generic.md` | any untested local model | fallback | Conservative defaults; reduce confidence in delegation. |
| `_template.md` | — | template | Copy this when onboarding a new model. |

Planned (not yet written — create when first tested):

| File | Model(s) | Why we'd add it |
|---|---|---|
| `granite3.md` | `granite3-dense:*`, `granite3-moe:*` | IBM's newer general-purpose Granite, not code-tuned. Different from granite-code. |
| `claude-cli.md` | `claude-*` running locally via CLI | Claude has *very* different prompting characteristics from coding-tuned local models — keep separate. |
| `llama3-coder.md` | `llama3.2-coder:*` | If we test Meta's coding variant. |

## Why this split exists

We started with a single monolithic `MODEL_TUNING.md`. Two problems
emerged:

1. **Models have genuinely different prompting needs.** Granite's
   instruction-tuning expects a `Question:/Answer:` template; a hypothetical Claude-CLI would expect a system-role and conversation
   format. Mixing all of these in one file made it hard to know which
   rules applied to the model currently running.
2. **The orchestrator should not need to change when we add a model.**
   A monolithic file conflates "when should I delegate at all" (universal)
   with "how do I phrase the prompt for Granite specifically" (per-model).
   Splitting lets the orchestrator stay frozen while the tuning library
   grows.

## File conventions

Every model file in this directory should follow this structure (see
`_template.md` for a starting skeleton):

1. **Why this model** — what's its differentiator (license, speed, size,
   language coverage, domain tuning)?
2. **Watcher configuration** — required Ollama options, prompt-wrapping
   strategy, anything the watcher itself needs to know to talk to this
   model effectively.
3. **Observed strengths** — what it does cleanly on the first pass.
4. **Observed weaknesses → mitigations** — failure modes and the prompt
   patterns or watcher changes that work around them. This is the heart
   of the file.
5. **Recommended prompt examples** — copy-pasteable templates that
   consistently work.
6. **Routing addenda** — *additional* "do not delegate" cases on top of
   the universal rules in `SKILL.md`.
7. **Session log** — dated entries of what was tested, what worked, what
   didn't. The empirical record.

## Why this matters for the eventual commercial product

The bridge protocol (`protocol/SPEC.md`) is open and copyable. What is
*not* easily copyable is the accumulated tuning knowledge in these files
— empirical, per-model, built from real delegation traces. As we add
more models and (eventually) more customers, this directory becomes the
moat. It's the difference between "a file-based IPC protocol" (commodity)
and "a productized local-AI orchestration system that actually works"
(asset).

For the v0.1 open-source release: ship `granite-code.md`, `_generic.md`,
and `_template.md`. Keep deeper per-model tuning, customer-specific
overrides, and any models we haven't fully publicized in a private
knowledge base.
