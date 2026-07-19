# Why local

A short pitch, then the long one.

## The short one

If you have a new Apple Silicon Mac, your home is on a lot of renewable
energy, and you don't mind waiting an extra few seconds for boilerplate,
running the mechanical bits of your AI workflow locally is free. Free
on the bill, free on the carbon footprint, and free on the privacy
ledger. The cloud assistant stays for the work that actually needs it.

The project defaults are also US-anchored — IBM Granite Code as the
primary model, Microsoft Phi as the lightweight tier — which matters
if you work on government contracts or in any other regulated industry
where audit-trail cleanliness counts. Other strong non-Western
models are documented as alternatives, but you have to opt in.

That's the entire pitch. Everything below is the long version.

## The math

A typical coding session with a cloud assistant fires off dozens of
mechanical subtasks: write this helper function, add docstrings to that
block, transform a CSV into JSON, fill out a template from a one-row
example. Each of these takes a few hundred milliseconds of GPU time in
a hyperscale datacenter — which means a few hundred milliseconds of
cooling water, a few hundred milliseconds of grid power, and the share
of the embodied carbon of that GPU.

None of those tasks need a frontier model. A 7B coding-tuned model
running on the user's own machine handles them cleanly. The reference
setup in this repo uses `granite-code:8b` on an M-series MacBook Air,
which can answer most of these prompts in under ten seconds, drawing
single-digit watts from a panel of rooftop solar.

A back-of-the-envelope estimate: a heavy day of AI-assisted coding might
generate fifty mechanical delegations. If thirty of them route to the
local model, that's thirty round-trips to a hyperscale datacenter that
didn't happen. Over a year, for a single user, the numbers add up to
real water and real watts.

The math is more compelling if the user's local power is renewable.
If your laptop runs off rooftop solar most of the day, every delegated
task is genuinely zero-emission inference. The cloud assistant is still
in the loop for the work that needs it — design, judgment, debugging,
domain expertise — but the routine work runs on sunlight.

## Who this is for

This project is explicitly NOT for everyone. If you're on a low-spec
machine, if your local power mix is mostly coal, if you're billing your
time at hundreds of dollars an hour and care about every saved second,
or if the cloud assistant is genuinely better at the mechanical tasks
you're sending it, none of this makes sense.

The fit is narrow but real:

- You have an Apple Silicon Mac with at least 16 GB of RAM (24 GB
  comfortable, 32 GB ideal).
- Your power mix at home is heavily renewable — rooftop solar, a green
  utility plan, a community solar share, or a region with a clean grid.
- You care, at least a little, about where your AI inference physically
  happens — for privacy, environmental, or principle reasons.
- You're working on coding or content tasks where the mechanical bits
  outweigh the judgment bits.
- You don't mind waiting an extra few seconds on routine work.

If three or more of those describe you, this project is for you. If not,
honestly, the cloud assistant is fine.

## Privacy as a side effect

The environmental argument is the main one, but local routing has a
privacy side effect that's worth naming. Every byte routed locally is
a byte your cloud assistant's provider never sees. Helper functions you
write for a private codebase, internal templates, sensitive data
transformations — all of these can stay on your laptop without the
overhead of running everything locally.

This isn't a security guarantee. It's a workflow side effect. Treat it
as a tasteful default, not a substitute for proper data classification.

## The values pitch, explicit

A growing share of the world's compute is going to AI inference. Some
fraction of that is unavoidable — frontier reasoning, deep research,
work that genuinely needs a 400 B parameter model running on a wall of
H100s. A larger fraction, honestly, is mechanical execution that could
have been done by a small model running on whatever device the user
already has plugged in.

The case for local-first AI delegation isn't that local models are
better. They're not. The case is that a lot of what we ask cloud models
to do doesn't need them, and the energy savings from routing the easy
stuff to a laptop add up at population scale.

This project is a contribution toward that pattern becoming normal.
The reference implementation runs on a single user's machine. The skill
generalizes to any cloud assistant. The protocol is small enough that
anyone can implement a watcher for their preferred runtime. If a few
thousand people end up routing their mechanical work locally because of
this project, the savings are measurable.

If you're in the narrow ICP described above and the values pitch
resonates, welcome — there's not much to install. If you want to
contribute a watcher for a runtime that isn't covered yet, please do.

## Why this, not the other local-routing tools?

Local AI routing isn't a brand-new idea. There are competent tools in
this space — houtini-lm and Hybrid Claw are the closest. If your goal
is purely "save Claude Code tokens" and you don't care about which
country built the model or how the experience feels to someone who
doesn't enjoy editing JSON config files, those projects are fine and
in some ways more technically mature than this one. Use them.

Three things make Cloud2GroundAI worth a separate install for the
right buyer.

**The skill is the product.** Most competitors give you a tool —
"call the local model" — and leave the decision of *when* to use it as
an exercise for the cloud assistant. The result is a coin flip. We
ship an opinionated policy: a decision table, two hard tests that gate
every delegation, prompt patterns calibrated for smaller models,
explicit rules for fallback when the bridge isn't running. The cloud
assistant doesn't have to think — it has to follow the playbook. That's
what makes the experience feel like routing instead of access. The
playbook took real engineering effort to write and is the part of this
project that's hardest to replicate.

**US-anchored defaults, regulated-industry friendly.** Our defaults
are IBM Granite Code and Microsoft Phi. We ship with no Chinese-origin
models pulled, no telemetry, no analytics. For a developer working on
a CMMC-controlled program, a defense contract, an ITAR-restricted
codebase, or any framework where the answer to "what foreign-origin
software is on this machine?" needs to be short, no other tool in this
category is doing the right thing by default. We are. (The competing
tools default to whatever performs best on a benchmark, which means
the answer is usually a Chinese-origin model — fine for a hobbyist, not
fine for a developer who has to pass a software-inventory review.)

**A polished consumer experience is on the roadmap.** The v0.1 is an
open-source repository for developers who can `pipx install` and edit
JSON. The v1.0 is a notarized macOS menu-bar app — install in one
click, Ollama lifecycle managed automatically, status badge that
shows "delegating now" in real time, model updates surfaced as native
notifications, zero terminal needed. The OSS proves the design works
and earns trust; the paid app is the form factor most users actually
want. That's where Carlano LLC plans to monetize, and that's why the
project is worth investing in beyond what an open-source side project
would justify on its own.

You're not paying for the cloud-to-local delegation. You're paying
for the *judgment* baked into the routing skill and the *trust* that
comes with US-anchored defaults and a real LLC standing behind the
software.
