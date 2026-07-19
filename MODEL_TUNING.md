# Model Tuning — now split per-model

This file has been superseded by a directory of per-model tuning files:

```
skill/
├── SKILL.md                    ← orchestrator (model-agnostic)
└── models/
    ├── README.md               ← index and conventions
    ├── _generic.md             ← fallback for untested models
    ├── _template.md            ← copy this when adding a model
    └── granite-code.md         ← active default
```

The split happened on 2026-06-20 because we realised:

1. Different local models have genuinely different prompting needs
   (Granite's IBM template vs. a general-purpose chat model's defaults
   vs. a hypothetical Claude-CLI's chat format). Mixing all the rules in
   one file made it hard to know which applied.

2. The orchestrator shouldn't need to change when a new model is added.
   A monolithic file conflated "when should I delegate" (universal) with
   "how do I prompt Granite specifically" (per-model). Splitting lets the
   orchestrator stay frozen while the tuning library grows.

For full per-model tuning history and findings, see `skill/models/`.
Today's findings (IBM Q/A template + greedy decoding + preamble
stripper) are documented in `skill/models/granite-code.md`.
