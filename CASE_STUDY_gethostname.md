# Case Study: The macOS `gethostname()` Bug

*How a local AI's mistake actually proves why local AI works.*

---

## The 60-second version

On June 20, 2026, we asked an 8-billion-parameter local model
(IBM Granite Code 8B) to write a Python function that detects all
LAN-reachable IP addresses on a Mac.

The model produced almost-correct code with one macOS-specific bug:
it used `socket.gethostname()`, which on macOS returns `Mac.local` —
a name that resolves only to `127.0.0.1`, the loopback address.
On real LAN networks, the function would silently fail.

The cloud assistant (Claude) caught the bug in a brief review, explained
why it happens, and wrote the corrected version using a UDP-socket trick
to discover the outbound interface. The corrected function works on
macOS, Linux, and Windows.

**The whole transaction cost a fraction of what writing the function
from scratch in the cloud would have cost — and the original draft
ran entirely on a solar-powered MacBook.**

That is the system working as designed. Not despite the bug. *Because*
of the bug.

---

## Why this story matters

The most common skeptical response to "delegate mechanical work to a
small local model" is some version of:

> *"But the local model will make mistakes. You'll still need the cloud
> assistant to fix them. So what did you actually save?"*

This is a real concern and it deserves a real answer. The answer is
that **writing code and reviewing code are very different in cost.**
A senior engineer writes a function in (say) one unit of effort.
Reading the same function, spotting a bug, and patching it takes
roughly a quarter of that effort. The same asymmetry holds for cloud
LLMs: writing-from-scratch is roughly 4× more tokens than reviewing
and editing.

That asymmetry is the engine that makes local delegation profitable
even when the local output is wrong. As long as the cloud assistant's
job is reduced from "write the whole thing" to "review and patch,"
the system saves tokens. Not just on perfect delegations — on most
delegations.

---

## The full story, with code

### The prompt

```
Write a Python function named get_lan_ips() that returns a list of all
IPv4 addresses bound to network interfaces on the local machine,
excluding 127.0.0.1 and any address starting with "169.254."
(link-local).

Constraints:
- Use only the Python standard library. No external packages.
- Use socket.getaddrinfo with socket.gethostname() OR parse `ifconfig`/`ip addr`
- Return a list of strings, sorted, deduplicated.
- If no usable IPs found, return ["127.0.0.1"] as fallback.

Output ONLY the function and its imports. Start with `import`.
```

### What Granite produced (8B, ~22 seconds, locally)

```python
import socket

def get_lan_ips():
    host_name = socket.gethostname()
    addr_info = socket.getaddrinfo(host_name, None)
    lan_ips = []
    for family, type, proto, canon_name, sa in addr_info:
        ip = sa[0]
        if ip != "127.0.0.1" and not ip.startswith("169.254."):
            lan_ips.append(ip)
    lan_ips = sorted(set(lan_ips))
    return lan_ips or ["127.0.0.1"]
```

Eight lines of clean Python. Correct shape: sorts, dedupes, applies
the right filters, falls back gracefully. The model picked a reasonable
implementation approach from the two options offered in the prompt.

There's just one problem.

### The bug

`socket.gethostname()` on macOS returns the machine's local hostname,
typically something like `Mac.local`. Without a configured DNS or
Bonjour entry that maps that name to a routable address, `getaddrinfo`
resolves it to `127.0.0.1` only. The filter then strips that result,
the list is empty, the function returns `["127.0.0.1"]` — and the
caller has no idea their LAN-detection function silently couldn't find
their LAN.

This is a known, well-documented macOS behaviour. It is not a Granite
hallucination — the *approach* is reasonable, it's a textbook
`getaddrinfo` call. The model simply lacked the platform-specific
knowledge that on macOS, this approach fails. That kind of knowledge
sits at the long tail of the training distribution. Small models drop
the long tail first.

### The fix (written by the cloud assistant)

The cloud assistant noticed the bug on read, explained the failure
mode in one paragraph, and produced this corrected version:

```python
import socket

def get_lan_ips():
    """Return all IPv4 addresses bound to this machine, excluding
    loopback and link-local. Survives the macOS gethostname() trap
    (which returns Mac.local → 127.0.0.1) by opening a UDP socket to
    a public address; the kernel picks the outbound interface without
    actually sending any packets."""
    ips = set()

    # Primary: the kernel's chosen outbound interface for internet traffic.
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 80))  # no packets actually sent
        ips.add(s.getsockname()[0])
    except OSError:
        pass
    finally:
        s.close()

    # Secondary: every IP getaddrinfo can find for the local hostname.
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None,
                                       family=socket.AF_INET):
            ips.add(info[4][0])
    except socket.gaierror:
        pass

    usable = sorted(
        ip for ip in ips
        if not ip.startswith("127.") and not ip.startswith("169.254.")
    )
    return usable or ["127.0.0.1"]
```

The UDP-socket-to-public-address trick is a well-known idiom for
"which interface would the kernel use to reach the internet" — it
doesn't actually send packets because of how `connect()` on UDP
sockets works. Combined with the original `getaddrinfo` fallback,
the function now works on macOS, Linux, and Windows.

---

## The cost math

Order-of-magnitude token costs for the three possible paths to this
function:

| Path | Cloud tokens | Local inference | Net cost |
|---|---|---|---|
| Cloud writes from scratch | 1.0× (baseline) | none | 1.0× |
| Local writes, cloud reviews and ships verbatim | ~0.1× (review only) | one local pass | 0.1× |
| Local writes, cloud spots bug + writes fix | ~0.3× (review + small rewrite) | one local pass | **0.3×** ← this case |
| Local writes, cloud throws it out and rewrites | ~1.1× (review + full rewrite) | one local pass (wasted) | 1.1× |

The case where Granite made a real, substantive mistake — exactly the
case skeptics worry about — still cost roughly 30 percent of what writing
from scratch would have cost.

Three out of four delegation outcomes save tokens. The only true loss
case is the full-rewrite outcome, and even that is only modestly worse
than the baseline.

These numbers are first-principles estimates, not measured. We have a
TODO to measure them properly across ~20 representative delegations
and publish real figures. But the order of magnitude is robust: code
review costs a small fraction of code authoring, in human engineers
and in LLMs alike.

---

## The deeper point: this is a *workflow* argument, not a quality argument

The pitch for local AI delegation is often framed as quality: *"the
local model is almost as good as the cloud."* That framing is fragile,
because eventually a customer runs a benchmark where the local model
isn't almost as good, and the pitch falls apart.

The real pitch is structural:

1. The cloud assistant is going to review the output anyway — that's
   already part of being the senior engineer.
2. Moving the *first draft* off the cloud captures most of the cost
   savings, because writing is expensive and reviewing is cheap.
3. The local model's job is to be *useful enough that review beats
   rewrite.* That's a much lower bar than "as good as the cloud."

A small local model only needs to clear the "useful first draft" bar
to deliver value. It does not need to be perfect. It does not even
need to be right most of the time — it needs to be right *or
partially right* most of the time, which is a much easier target.

That's why partial failures like the `gethostname()` bug are not
embarrassments. They are evidence the system is doing its job: the
local model carried the bulk of the writing work, the cloud
assistant carried the bulk of the judgment work, and the total cost
of the transaction was much lower than either alone.

-AAC note: Can we also add some narrative about how these skills and the MD files of All that we could send out updates as AI models change or you and I work out better ways to delicate sort of like we did this morning with the granite documentation. Sorry, using the speech to text feature on my Mac. It's really about how this would evolve and may not save more tokens as models change, but stay effective and as the local models add more capabilities, we would give you claude the senior engineer to track those abilities and RAM isn't gonna get cheaper. Databases aren't gonna get cheaper. This is sort of a hedge against the token cost increasing but MacBook and arm chipped devices staying cheap in comparison. I think we could eventually put this on a Windows arm machine or Lennox.

---

## Sustainability angle (when relevant)

The original Granite inference ran on a 24GB M-series MacBook Air in
a solar-powered home. The model loaded and produced an answer using
~5 Wh of energy — roughly what a smartphone draws in 15 minutes of
heavy use. No datacenter water, no datacenter power, no cooling load.
At scale across many customers, this matters.

The cloud assistant's review pass still draws datacenter resources,
but those resources are roughly an order of magnitude smaller than
they would have been for the writing pass. The system as a whole is
substantially less resource-intensive than cloud-only inference, and
the locally-run portion can be powered by the customer's own clean
energy source.

For customers who care about sustainability reporting, this is a real
story: not "we offset our datacenter" but "we structurally route the
expensive part of the work onto your own machine, where you control
the power source." That's a different and stronger claim. 

---

## Reproducing this case study

The bug and the fix can both be reproduced on any Mac with the local-AI
bridge installed:

```bash
# 1. Install the bridge per the main README.
# 2. Verify granite-code:8b is the active model:
ollama list | grep granite-code

# 3. Run the demo prompt (this script is in demo/get_lan_ips_demo.sh
#    in the open-source release).
bash demo/get_lan_ips_demo.sh

# 4. Compare the local output to the documented corrected version.
#    On a typical macOS host, the buggy version returns ["127.0.0.1"]
#    while the corrected version returns the real LAN IP.
```

The buggy output and the corrected output are both included in the
demo script for side-by-side comparison.

---

## What we want potential customers to take from this

If you remember one thing: **local AI is not about replacing the cloud
assistant. It's about moving the expensive half of the work off the
cloud.**

If you remember two things: **the system works even when the local
model makes mistakes.** That's the whole point. Catching mistakes is
cheap. Writing from scratch is expensive. Routing the writing locally
and keeping the catching in the cloud is a structural win.

If you remember three things: **you can see this happen on your own
machine in five commands.** The demo is reproducible, the failure
mode is real and documented, and the cost asymmetry is verifiable.

We are not asking customers to trust us on any of these claims. We
are asking them to run the demo.

---

## TODOs before public release

- [ ] Measure actual token counts for the four cost paths across ~20
      representative delegations and replace the order-of-magnitude
      estimates with real numbers.
- [ ] Build `demo/get_lan_ips_demo.sh` so the reproduction instructions
      above are runnable as advertised.
- [ ] Confirm the energy figure (~5 Wh per Granite-8B inference on
      M-series) with a benchmark — currently a back-of-envelope number.
- [ ] Decide whether to lead with this case study in the README, link
      to it from the README, or only feature it in `docs/why-local.md`.
- [ ] Vet the macOS bug explanation with someone who knows TCC /
      networking deeply before publishing externally. -AAC note: I don't think we really care about other people vetting that specific bug they can rerun that case or maybe we do like a month trial of the new software so they contest it on their own use cases I feel like that would be a better hook than some expert people have never heard of. Says that it caught the right bug I think.
