# Keep Claude for the thinking. Run the busywork on your own Mac.

I use Claude every day. And the more I watched what it actually does in a coding session, the more one thing stood out: most of it is busywork.

Write a helper function from a clear spec. Add docstrings to a block I pasted. Turn a CSV into JSON. Fill out a config from a one-row example. Rename things, reshape things, boilerplate. That's the bulk of a normal session. The genuinely hard part — the design, the judgment, debugging the weird stuff, reasoning across a whole codebase — is a small fraction. Everything else is just execution.

And execution doesn't need a data center. A small, coding-tuned model running right on my laptop can do it. So why was I paying cloud tokens — and spinning up data-center hardware — for the part a local model handles cleanly?

That question turned into **Cloud2GroundAI**.

## Senior engineer, junior engineer

The whole design is one idea: Claude stays the senior engineer, and a small local model is the junior.

Claude keeps doing what it's best at — understanding what you want, making the calls, reviewing the work. When a subtask is mechanical enough to hand down, Claude writes a short request to a shared folder on your Mac. A local model — IBM Granite, running through Ollama — picks it up, does the work, and writes the answer back. Claude reads it, checks it, and drops it into your code, with a quiet note that it was handled locally.

You keep using Claude exactly the way you do now. Nothing changes in your workflow. You just spend fewer cloud tokens for the same output, because the repetitive majority ran on your own machine.

## Why it holds up

The obvious worry is quality: a small local model isn't as sharp as a frontier cloud model. True — and it doesn't need to be, because it's never the one in charge. Claude decides what to delegate, and Claude reviews what comes back. When the local model nails a mechanical task, you saved a cloud round-trip. When it gets something subtly wrong, Claude catches it and patches it — which is still cheaper than generating the whole thing in the cloud from scratch. The senior engineer is always holding the pen.

## What you get, beyond the token savings

Three things come along for the ride:

**Privacy.** The delegated work never leaves your Mac. There's no third party in the loop — you're still just a Claude customer, and the local model runs entirely on your own hardware.

**A lighter footprint.** Every task that stays on your laptop is data-center power and water that nobody had to spend. Apple Silicon sips energy, and it only works hard in the seconds it's actually generating an answer. If your Mac runs on solar — mine does — that work is close to carbon-free. The greenest task is the one that never had to leave your desk.

**Provenance you can defend.** The defaults are deliberately Western-anchored and open: IBM Granite, Apache-2.0, on Ollama. If you work somewhere a software-inventory review has to come back boring, this is a clean fit.

## Where it came from

This started in a solar-powered home, on an M-series MacBook Air, with that one observation: a huge share of AI-assisted work is mechanical, and mechanical work runs fine — and nearly free, financially and environmentally — on the machine already sitting on your desk. Cloud2GroundAI is just the contract that makes the handoff work, without changing your relationship with Claude at all.

## Try it — it's a free preview

Cloud2GroundAI is a small Mac menu-bar app. You install it once; a setup wizard walks you through installing Ollama, pulling the model, and wiring up the bridge (about ten minutes, most of it the model download). After that it runs quietly in the background.

You'll need an Apple Silicon Mac, macOS 14 or newer, and — this one matters — **at least 16 GB of memory**, because the model needs room to run well. The app is signed and notarized, and the source is Apache-2.0.

It's a **free public preview** while I gather feedback, and I genuinely want yours — what breaks, what's confusing, what you'd want it to do. Download it and tell me: **carlanotech@pm.me**.

Download and source: https://github.com/carlanotech/cloud-to-ground-ai
