# ACT-001 — Define the representative C2G workload

**Owner:** Andrew
**Status:** Open
**Blocks:** PRD-002 (cloud token reduction), PRD-004 (energy per session), and indirectly several L2 budgets
**Why it matters:** Almost every measurable claim Cloud2GroundAI will make hangs on this. "Reduces cloud tokens by 40%" is meaningless without a defined workload. Same with "fits in X Wh per session." Closing this single action unblocks the largest cluster of L2 measurements.

This worksheet is a short structured prompt to drag the workload definition out of your head. Fill it in tomorrow morning and it closes ACT-001 — and through ACT-001, ACT-002 (token target) and ACT-003 (energy target) become measurable.

---

## 1. What you actually use AI for

Think about a typical week of using AI assistance — Claude in chats, code helpers, anything. Estimate the *proportion* of your AI time in each category. Doesn't have to sum precisely; ballpark percentages are fine. Add categories I missed.

| Category | % of your AI time | Example you've actually done |
|---|---|---|
| Short Q&A ("how does X work?", "what's the unit for Y?") | 5% | |
| Code generation (write a function from a spec) | 45% | |
| Code review / debugging (explain why this is wrong) | 29% | |
| Long-form writing (drafts, blog posts, reports) | 5% | |
| Editing / reformatting (rewrite this in plain English) | 5% | |
| Summarization (give me the gist of this paper / email / doc) | 1% | |
| Brainstorming / ideation (what should we name X?) | 1% | |
| Systems engineering / planning (like what we just did) | 9% | |
| Other: __________________________________________ | __% | |

---

## 2. Prompt-length distribution

For each category above, how long is a typical prompt? Rough buckets:

| Category | Typical prompt length |
|---|---|
| Short Q&A | x tweet-sized (≤50 words) □ paragraph (50–200) □ longer |
| Code generation | □ one-liner spec □ paragraph spec x multi-paragraph + context |
| Code review | □ paste a function x paste a file □ multi-file |
| Long-form writing | x short brief □ detailed outline □ pasted draft |
| Editing | □ paste paragraph □ paste page x paste document |
| Summarization | x short text □ a page □ multiple pages |
| Brainstorming | x one question □ context + question |
| SE / planning | □ one question x pasted artifact + question |

Why this matters: a workload heavy in long-context tasks (summarization, multi-file code review) stresses the local model's context window (L2-AI-002) and will pull the energy-per-session target up. A workload heavy in short prompts lets a smaller local model carry it.

---

## 3. Response-length expectation

| Category | Typical expected response |
|---|---|
| Short Q&A | x ≤50 words □ a paragraph □ longer |
| Code generation | □ a function (~20 lines) □ a file (~100 lines) x multiple files |
| Code review | □ a paragraph of feedback x a corrected version □ a written analysis |
| Long-form writing | □ short x medium □ long |
| Editing | (2 page file input length) |
| Summarization | □ TL;DR (≤100 words) x structured summary □ exhaustive |
| Brainstorming | □ a list x a list with analysis □ deep dive |
| SE / planning | (varies long form with context guess) |

---

## 4. Delegation-suitability — your gut feel

For each category, when you imagine the *local* model handling it, how do you feel?

| Category | Confidence local model can handle it |
|---|---|
| Short Q&A | □ confident x partial □ no |
| Code generation | x confident □ partial □ no |
| Code review | □ confident x partial □ no |
| Long-form writing | □ confident x partial □ no |
| Editing | □ confident x partial □ no |
| Summarization | □ confident x partial □ no |
| Brainstorming | □ confident x partial □ no |
| SE / planning | □ confident x partial □ no |

This populates the routing policy (L2-AI-003). Confident → delegate, partial x delegate with cloud review, no → keep in cloud.

---

## 5. "Useful" — what does it mean per category?

The L1 check method for PRD-001 says "useful output for at least 3 representative task types." Defining "useful" per category lets us actually measure it.

| Category | "Useful" means | "Useless" means |
|---|---|---|
| Short Q&A | answer is correct on the facts | hallucinates a wrong fact | -AAC note i want Claude to check the local for hallucinations
| Code generation | compiles, runs, and does the asked thing | doesn't compile, wrong output, or wrong API | 
| Code review | identifies the actual issue | identifies a non-issue, misses the real one |
| Long-form writing | matches voice and is factually right | wrong tone or factually wrong |
| Editing | preserves meaning, improves clarity | changes meaning or worsens clarity |
| Summarization | covers all major points, no fabrication | misses major points or invents content |
| Brainstorming | diverse, on-prompt ideas | repetitive or off-prompt |
| SE / planning | traceable to the input, internally consistent | violates the SE framework |

Fill in or correct the rows. The third column ("useless means") is the negative criterion — what disqualifies a response from counting as useful.

---

## 6. Reference session shape

Putting the above together, what does ONE representative C2G session look like? The L1 check method says "≥5 turns." Sketch what those 5 turns might be — they don't have to be real, they should be representative. --AAC note, lets actually do this with a project I have actively instead of guessing

```
Turn 1 (user): _______________________________________________
Turn 1 (AI):   _______________________________________________
Turn 2 (user): _______________________________________________
Turn 2 (AI):   _______________________________________________
Turn 3 (user): _______________________________________________
Turn 3 (AI):   _______________________________________________
Turn 4 (user): _______________________________________________
Turn 4 (AI):   _______________________________________________
Turn 5 (user): _______________________________________________
Turn 5 (AI):   _______________________________________________
```

This becomes the actual measurement script for ACT-003 (energy) and ACT-002 (token reduction).

---

## 7. Aspirational vs. realistic

Two passes — fill in your *actual* current usage above (be honest about how much of your AI time is short Q&A vs. real work), then mark with an asterisk anywhere you wish C2G unlocked a new category for you. Cloud2GroundAI doesn't have to match your current mix — it might be designed for the *future* mix you want.

What would you *use* C2G for that you don't currently use AI for?

```
_______________________________________________________________
_______________________________________________________________
_______________________________________________________________
```

---

## Once this is filled in

I can:

1. Translate the category mix into a numeric workload spec (sequence of prompts of bounded length, expected response shape) that goes into `SE/workload.json`.
2. Use it to pick a measurement script (Python harness that runs the workload against cloud-only and cloud+bridge configurations).
3. Set a real (non-strawman) target for PRD-002 (ACT-002 closes) and PRD-004 (ACT-003 closes).
4. Use the routing-suitability column to draft L2-AI-003's first routing policy.

Estimated work to translate this into measurements: ~30 minutes of mine, no Andrew input needed once the worksheet is filled.
