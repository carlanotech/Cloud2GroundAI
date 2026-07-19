# Show HN post

## URL field
https://github.com/carlanotech/cloud-to-ground-ai

## Title (keep it plain — HN dislikes hype)
Show HN: Cloud2GroundAI – hand Claude's busywork to a local model on your Mac

## Body

I built a small macOS menu-bar app that lets Claude delegate the mechanical parts of a coding task to a local IBM Granite model (via Ollama) running on your own machine, instead of doing them in the cloud.

The observation behind it: most of what a cloud assistant does in a session is execution — write a helper from a spec, add docstrings, transform a file, fill a template — and the actual judgment work is the small part. So Claude stays the "senior" and a small local model handles the "junior" bulk. They talk through a plain file-based protocol in a folder on your Mac: Claude decides when a subtask is mechanical enough, writes a request, a local watcher runs the model, and Claude reads the answer back and reviews it before using it. The senior model is always the one holding the pen, so a weaker local model is fine — when it gets something wrong, Claude catches it, and that's still cheaper than generating from scratch in the cloud.

Why I bothered: it cuts cloud token cost, the delegated work never leaves your machine, and local inference on Apple Silicon is cheap — power-wise, and (if you're on solar, like me) close to carbon-free. The defaults are deliberately Western-sourced and Apache-2.0 (Granite + Ollama), which matters if your software inventory has to survive a compliance review.

Honest limitations: it's a free public preview, macOS 14+, Apple Silicon, and it really wants 16 GB+ of RAM — the model is too slow to be useful below that. The app is signed and notarized; source is Apache-2.0. There's one known rough edge on underpowered Macs where the first-run smoke test can be slow or report a stale response (noted in the release, fix queued).

The part I'd most like feedback on is the delegation heuristics — when is a subtask "mechanical enough" to hand down? — and the file-based protocol itself, which is really the asset here. I'd love to see other implementations of it. Thanks for taking a look.

---

## Notes for posting
- Post on a weekday morning US time (Tue–Thu) for best HN visibility.
- Be around for the first few hours to answer comments — that's what keeps a Show HN alive.
- Lead replies with substance and specifics; HN rewards candor about limitations (the 16 GB requirement, the preview status, the known bug) far more than polish.
- If someone asks "why not just use a smaller cloud model / why local at all," the honest answer is the three-in-one: cost, privacy, and footprint — plus provenance for regulated users.
