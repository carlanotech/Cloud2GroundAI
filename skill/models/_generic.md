# Tuning: generic / untested local model

**Applies to:** any local model for which a specific tuning file does not
yet exist.

**Status:** conservative fallback. The goal of this file is to keep
delegations safe when we don't know the model's failure modes yet.

## Default posture: reduce confidence

Without empirical data on a specific model, we don't know:
- Whether it follows negative constraints
- Whether it adds preambles
- Whether it hallucinates APIs
- What output format it defaults to
- How well it handles edge cases

So this file errs on the side of caution.

## Watcher configuration

If the watcher hasn't been updated with model-specific options, it
defaults to:

| Option | Value | Notes |
|---|---|---|
| `temperature` | (Ollama default, often 0.7) | Probably too high for code; tune if outputs look creative. |
| Prompt wrapping | none | Send the prompt as-is. |
| Output post-processing | strip markdown fences only | Don't strip preambles — we don't know if they're real content. |

## Rules for prompts

1. **Be explicit about expected output format.** Don't trust the model
   to infer it.
2. **Name the expected first token.** "Start with `def`" works on most
   models.
3. **Use positive constraints, not negative ones.** "Return a list of
   strings" lands better than "do not return a dict."
4. **Avoid pattern completion until you've tested it.** Pattern
   completion is high-value on models like Granite but can
   confuse models that weren't tuned for it.

## Routing posture

Be more conservative than the universal SKILL.md rules suggest:

- **Stricter prompt-length cap:** under 60 words, not 100. We don't
  know how the model degrades on longer prompts.
- **Always run a verification pass** on the output before using it —
  syntax check, simple unit test, eyeball comparison against the spec.
- **Never use the output verbatim in code paths that affect hardware,
  money, or data integrity** until the model has a real tuning file.

## When to upgrade a model from this file to its own file

After ~5–10 delegations to a new model, you should have empirical data
on:
- Hit rate on first-pass usability
- Common failure modes
- Whether a specific prompt-wrapping helps
- Whether specific Ollama options help

When you have answers to those, copy `_template.md` to
`<model-name>.md` and fill it in. Add the prefix → file mapping to the
table in `SKILL.md` Step 2.

## Note when delegating to an untested model

When using `_generic.md`, add a brief note in the final response that
the model is untuned:

> *(handled locally via `<model-name>`; this model has no tuning file
> yet — output verified manually)*

This makes the empirical record visible and signals where the next
tuning-file should be written.
