# Cloud2GroundAI — demo storyboard

## Goal
Show, in under 90 seconds, that Claude quietly hands the busywork to a model on
your own Mac — you spend fewer cloud tokens, and nothing leaves the machine.
One idea, made visible. Lead with the Claude-power-user payoff.

## Specs
- **Length:** aim for 60s (social loop) or up to 90s (explainer). Shorter wins.
- **Format:** screen recording at 1080p+ (QuickTime → File → New Screen
  Recording, or Cmd-Shift-5). Export the loopable 60s cut as a GIF/MP4 for
  X/Reddit; keep the 90s MP4 (with voiceover) for the blog and YouTube.
- **Two audio versions:** one with the voiceover below, one silent that relies
  only on the on-screen captions (autoplay feeds are muted by default).
- **Keep the cursor calm.** Slow, deliberate movements read as confident.

## The one thing to make visible
Delegation is normally invisible — that's the product's magic and its demo
problem. Three cues make it visible, in order of punch:
1. Claude's own note in its reply — e.g. *"(handled locally via granite4.1)"*.
2. The menu-bar status panel showing the local model + bridge up.
3. **The offline proof** (see Beat 4) — the most convincing three seconds in
   the whole video.

---

## Storyboard (90s explainer cut)

**Beat 1 — Hook (0:00–0:08)**
- *Visual:* a normal Claude coding session, mid-task.
- *Caption:* "Most of what Claude does all day is busywork."
- *VO:* "If you use Claude to code, most of a session is busywork — helpers,
  docstrings, reformatting. Work that doesn't need a data center."

**Beat 2 — The setup (0:08–0:18)**
- *Visual:* click the menu-bar cloud-and-lightning icon → the status panel:
  Ollama running, granite4.1 loaded, bridge up.
- *Caption:* "Cloud2Ground puts a small AI on your own Mac."
- *VO:* "Cloud2GroundAI runs a small local model — IBM Granite — right on
  your machine, and connects it to Claude."

**Beat 3 — The handoff, live (0:18–0:42)**  ← the core
- *Visual:* in Claude, type a clearly mechanical request. Good options:
  - "Add docstrings to this function." (paste a short function)
  - "Write a helper that formats a byte count as KB/MB/GB."
  - "Turn this CSV into JSON." (paste 3 rows)
  Claude answers, and its reply shows the local note.
- *Caption:* "Claude handed it to your Mac — not the cloud."
- *VO:* "Claude decides the task is mechanical, hands it to the local model,
  reads the answer back, and checks it — the senior engineer always holds the
  pen. You just spent zero cloud tokens on it."
- *Note:* zoom/highlight the *"handled locally"* line when it appears. If the
  reply doesn't surface it clearly, cut to the status panel's "last delegation"
  line instead.

**Beat 4 — The proof (0:42–0:52)**  ← the money shot
- *Visual:* click Wi-Fi off (or Airplane Mode — show the menu bar toggle), then
  open the app's **Ground chat** and ask it something simple. It answers.
- *Caption:* "Still works with the internet off. It's really on your Mac."
- *VO:* "And because it's genuinely local — turn the internet off, and it still
  answers."

**Beat 5 — Payoff (0:52–1:12)**
- *Visual:* clean title card or the three points animating in.
- *Caption / VO:* "Fewer cloud tokens. Your files never leave your Mac. And it
  runs on efficient Apple Silicon — greener, especially on solar."
- Optional 4th line for the compliance crowd: "Western-sourced and open —
  IBM Granite, Apache-2.0."

**Beat 6 — CTA (1:12–1:25)**
- *Visual:* the app icon + the URL.
- *Caption:* "Free public preview — Apple Silicon Mac, 16 GB+."
- *VO:* "It's a free preview. github.com/carlanotech/cloud-to-ground-ai."

---

## 60-second social cut
Drop Beat 1 to one line and Beat 5 to a single card. Keep Beats 3 and 4 intact —
the live handoff and the offline proof are the whole point. End on the app icon
+ URL held for 2–3 seconds so it reads in a muted, scrolling feed.

## Recording checklist
- Clean desktop, hide clutter, use a neutral wallpaper, light or dark
  consistently. Bump the system font size a notch so captions/code are legible
  when the video is small.
- Pre-warm the model (run one delegation first) so the on-camera one is fast —
  your real Mac round-trips in a few seconds; don't record a cold start.
- Do the whole flow once as a rehearsal; the second take is always cleaner.
- Record a few seconds of pad at the start/end for trimming.
- For the offline beat, actually toggle Wi-Fi on camera — don't fake it; the
  visible toggle is what sells it.

## The one rule
If you only nail two beats, make them **3 (the live handoff)** and
**4 (the offline proof)**. Everything else is framing.
