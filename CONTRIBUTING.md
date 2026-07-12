# Contributing to Cloud2GroundAI

Thank you for considering a contribution. This document describes the
bar for contributions and the process.

## The short version

1. Open an issue first for non-trivial changes so we can discuss design
   before you write code.
2. Fork, branch, change, test, sign off your commits (`git commit -s`),
   open a pull request.
3. Keep the change focused. One concern per PR.
4. Be patient — this is maintained part-time.

## What we welcome

- **Bug fixes** with a minimal reproduction.
- **Tuning files for additional local models** (`skill/models/<name>.md`)
  with empirical evidence of what works and what fails.
- **Documentation improvements** — especially clarifications where the
  existing docs were ambiguous when you first read them.
- **Tests** that exercise existing untested code paths.
- **Platform support** for non-macOS hosts of the bridge (the watcher
  is bash-portable; the Mac app is the macOS surface).

## What we will likely decline

- **Pull requests that re-architect the core protocol** without prior
  discussion in an issue.
- **Dependencies on non-Western-headquartered libraries or models** —
  see the "auditable provenance" framing in the README. This is a
  deliberate constraint, not an oversight.
- **Telemetry or "phone home" features** that change the
  privacy-preserving defaults. Opt-in channels are fine; defaults are not
  negotiable.
- **Commercial-add-ons-only features** in the open-source repo. Paid
  tiers live elsewhere; the OSS repo is for the core that works without
  payment.

## Developer Certificate of Origin (DCO)

Every commit must be signed off. This is the
[Developer Certificate of Origin v1.1](https://developercertificate.org/),
a lightweight legal statement that you have the right to submit the
contribution under the project's license.

Sign your commits by passing `-s` to `git commit`:

```bash
git commit -s -m "Fix race condition in watcher cleanup"
```

This appends a line like:

```
Signed-off-by: Your Name <you@example.com>
```

If you forget, you can amend the most recent commit:

```bash
git commit --amend -s --no-edit
```

Or rebase a series and sign off in bulk:

```bash
git rebase --signoff main
```

Pull requests without DCO sign-off on every commit will not be merged.

## Coding conventions

### Bash (the watcher)

- Single file. We do not split the watcher across files in v0.x.
- Document protocol changes inline at the top of `start_local_ai.sh`
  using the `v0.x.y tuning changes` block pattern already in place.
- Bump the protocol version banner string when you change behavior.

### Markdown (skill files)

- Use sentence-case headings.
- Keep tables narrow enough to render in GitHub's default web view.
- Cite the requirement ID or external source in claims about behavior
  ("per L2-OPS-010" / "per IBM's Granite prompting docs at <url>").

### Swift (the Mac app — when contributing post-v0.2)

- Every file header cites the L2 requirement(s) it implements.
- `import Combine` whenever you use `ObservableObject`, `@Published`,
  `@ObservedObject`, `@StateObject`, or `@EnvironmentObject`. SwiftUI's
  partial re-export is unreliable across Xcode versions.
- AppKit lifecycle objects (NSStatusItem, NSWindow, NSWindowController)
  must be strongly owned by their responsible class. Do not use `weak`
  references for them.
- See `skill/models/granite4.1.md` "Observed weaknesses → mitigations"
  for the full Swift-specific gotchas list.

## Testing

There is no comprehensive test suite yet. For bug fixes, include a
minimal reproduction in the PR description. For feature additions,
include manual test steps that exercise the new code path.

## Release tagging

Release tags follow [Semantic Versioning](https://semver.org/) at the
**protocol** level:

- **MAJOR** — protocol-breaking changes (request.txt schema, etc.)
- **MINOR** — backward-compatible additions (new optional first-line
  conventions, new outcome classes in the delegation log)
- **PATCH** — bug fixes and tuning changes

The Mac app version tracks the protocol version it speaks.

## Reporting security issues

Please **do not** open a public issue for security-sensitive reports.
Email `security@carlano.com` instead. We will acknowledge within 7 days
and coordinate disclosure.

## Questions

Open a [Discussion](https://github.com/carlanotech/Cloud2GroundAI/discussions)
for design questions or general help. Use Issues for confirmed bugs and
feature proposals.
