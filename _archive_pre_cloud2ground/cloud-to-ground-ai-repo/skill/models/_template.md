# Tuning: <model-name>

**Applies to:** `<model-prefix>:*`

**Status:** <draft / active / deprecated>

## Why this model

<What's the model's differentiator? License, speed, size, language
coverage, domain tuning, who built it, what it's known to be good at.>

## Watcher configuration

These options are applied in `start_local_ai.sh` when the active model
matches the prefix above. Do not duplicate them in prompts.

**Prompt wrapping:**

```
<template, if any — e.g. Granite's Question:/Answer: or none>
```

**Ollama options:**

| Option | Value | Why |
|---|---|---|
| `temperature` | <value> | <reason> |
| `repeat_penalty` | <value> | <reason> |
| `num_predict` | <value> | <reason> |
| `stop` | <value> | <reason> |

**Output post-processing:**

<What does the watcher strip from this model's output? Fences only,
or preambles, or something else?>

## Observed strengths

<What does this model do cleanly on the first pass? Be specific —
"writes correct Python list comprehensions," "respects type-hint
requests," "handles JSON object construction well." Anecdotes welcome.>

## Observed weaknesses → mitigations

### <Weakness 1>

<What goes wrong? Show a specific failure if possible.>

**Mitigation:**

<What prompt pattern, watcher option, or workflow change addresses it?>

### <Weakness 2>

<...>

## Recommended prompts

**Pattern X:**

```
<copy-pasteable example that has consistently worked>
```

## Additional routing rules (on top of SKILL.md universals)

Do **not** delegate to this model if any of these is true:

- <case 1>
- <case 2>

## Session log

### <date> — <short title>

<What was tested. What worked. What didn't. Score: N/M first-pass
usable.>
