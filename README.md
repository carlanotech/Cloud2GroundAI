# Cloud2GroundAI

**A macOS menu bar app that lets Claude hand routine code generation to a local AI model running on your own Mac.**

The cloud assistant stays in charge — planning the work and reviewing what comes back. The token-heavy generation happens on your machine instead of in a datacenter.

[carlanotech.github.io/carlano-site/cloud2groundai.html](https://carlanotech.github.io/carlano-site/cloud2groundai.html)

---

## Download

**[Cloud2GroundAI_v2.5.dmg](Cloud2GroundAI_v2.5.dmg)** — signed and notarized by Apple.

Open the DMG, drag Cloud2Ground to Applications, launch it, and follow the setup wizard. The local model downloads automatically on first run.

### Verifying your download (optional)

```bash
shasum -a 256 -c Cloud2GroundAI_v2.5.dmg.sha256
```

Should print `Cloud2GroundAI_v2.5.dmg: OK`.

---

## Requirements

- Apple Silicon Mac (M-series), macOS 14 or later
- **16 GB memory minimum, 24 GB recommended**
- ~8 GB of disk space for the model, downloaded on first run
- Your own Claude account

### About that memory recommendation

While the local model is loaded it holds about **8.5 GB of RAM that other applications cannot reclaim**. It is never written to your SSD, so it causes no drive wear — but on a 16 GB Mac that leaves little headroom, and other apps may slow down while it is running. It unloads on its own when idle, and more aggressively when you are on battery.

---

## What it does

- Delegates well-defined, mechanical coding tasks to a local model
- **Verifies the result before you see it** — add a `# smoke-test:` line to a request and the generated code is executed and checked automatically, catching an invented function that would crash or a calculation that quietly returns the wrong answer
- Costs effectively nothing when idle, and unloads the model on battery
- Tracks what delegation has saved you

---

## Support

Questions or problems: **carlanotech@pm.me**

---

## License

Apache License 2.0 — see [LICENSE](LICENSE) and [NOTICE](NOTICE).

Copyright 2026 Carlano Technology Solutions LLC
