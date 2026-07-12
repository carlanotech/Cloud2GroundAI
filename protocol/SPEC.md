# Cloud2Ground Bridge Protocol — v0.2.5

**Document status:** Specification, normative. Reference implementation
is `start_local_ai.sh` in this repository at the version tag matching
this document.

**Audience:** Anyone writing a cloud-side client (Claude skill, MCP
server, custom tool) or an alternative server (Python rewrite of the
watcher, another model runtime).

---

## 1. Purpose and scope

The protocol defines how a **client** (running as a Claude skill, or as
any process willing to follow the file convention) hands a single
mechanical subtask to a **server** (the watcher process, which speaks to
a local model via Ollama) and receives the result.

The protocol is intentionally minimal: filesystem-only, no network, no
authentication, no concurrency above 1, no streaming. It is designed for
one user, one machine, one delegation at a time — the case where the
overhead of a real RPC layer would dwarf the work being delegated.

Out of scope: model selection, prompt engineering, output evaluation.
Those are the client's concern (see `SKILL.md` and `models/*.md`).

---

## 2. Terminology

The key words **MUST**, **MUST NOT**, **SHOULD**, **SHOULD NOT**, and
**MAY** are to be interpreted as described in
[RFC 2119](https://datatracker.ietf.org/doc/html/rfc2119).

**Bridge folder** — the directory containing the IPC files. The
reference implementation uses `~/Documents/claude_bridge/_bridge/` on
macOS, chosen because Cowork can mount `~/Documents/` but cannot mount
`~/Library/Application Support/`. Other hosts MAY choose a different
location as long as both client and server agree.

**Request** — a `request.txt` file written by the client into the
bridge folder.

**Response** — a `response.txt` file written by the server into the
bridge folder.

**Consumption acknowledgement** — a `consumed.txt` file the client
writes after reading a response, telling the server it is safe to clean
up.

**Processing lock** — a `processing.lock` file the server creates while
inference is in flight. Contains the server's PID.

---

## 3. Bridge folder layout

```
<bridge folder>/
    request.txt          # transient — present when client has a pending request
    response.txt         # transient — present when server has produced a reply
    consumed.txt         # transient — present when client has read the response
    processing.lock      # transient — present during inference; contains server PID
```

All four files MUST be plain UTF-8 text. The bridge folder MUST be
writable by both client and server processes. On macOS, this means
choosing a location not subject to TCC restrictions for either party —
`~/Documents/` works because users typically grant Documents access
interactively; `~/Library/Application Support/` does not work for
launchd-spawned clients without a prior interactive grant.

---

## 4. Request format

A `request.txt` is a UTF-8 text file with the following structure:

```
[# id: <request-id>]
[# start: <expected-start-token>]
<prompt body...>
```

### 4.1 Optional `# id:` line

If present, MUST be the first line of the file. The format is:

```
# id: <alphanumeric, underscore, or hyphen, ≥1 char>
```

The server MUST echo this id verbatim as the first line of the
corresponding `response.txt`. Clients MUST verify the id matches before
accepting the response; if it does not match, the response is stale or
intended for a different request and MUST be discarded.

If no `# id:` line is present, the server MAY emit a response without
an id line. Clients that omit the id field SHOULD use a wall-clock
timeout for staleness detection instead.

### 4.2 Optional `# start:` line

If present, MUST appear immediately after the `# id:` line (or as the
first line if there is no id). The format is:

```
# start: <token>
```

The token MAY be wrapped in backticks; the server MUST strip surrounding
backticks if present.

The token names what the answer should begin with. The server uses it
to strip a natural-language preamble from the model's output: it finds
the first line in the model response that begins with the token
(tolerating leading whitespace) and discards everything before that
line. This is necessary because some models (notably Granite Code under
the IBM Q/A template) produce "Here's the code:" preambles before the
actual answer.

If no `# start:` line is present, the server MAY auto-detect a "Start
with `<token>`" instruction inside the prompt body via the regex
`[Ss]tart with\s*\`([^\`]+)\``. If neither an explicit `# start:` line
nor an auto-detectable instruction is present, the server uses only
code-keyword anchors (see §6.3).

### 4.3 Prompt body

Everything after the optional header lines, until end-of-file. The
client SHOULD NOT include trailing whitespace. The server MUST
`strip()` the body before applying any per-model prompt wrapping (see
§6.2).

### 4.4 Request size

There is no hard upper bound. In practice, prompts above
~`(Ollama context window) - num_predict` characters will be silently
truncated by Ollama. Clients SHOULD keep prompts under 8000 characters
for granite4.1:8b (32K context, 2K predict allocation).

---

## 5. Response format

A `response.txt` is a UTF-8 text file with the following structure:

```
[# id: <echoed-request-id>]
<model output...>
```

The optional `# id:` line MUST be present if and only if the
corresponding request had one, and MUST exactly equal the request's id
line.

The model output MUST NOT include surrounding markdown code fences;
the server is responsible for stripping them before writing (see §6.3).

If inference failed, the model-output portion MUST be a single line
of the form:

```
ERROR: <description>
```

Clients MUST treat any response beginning with `ERROR:` (after the
optional id line) as a failure and SHOULD NOT retry on the same prompt.

---

## 6. Server behavior

### 6.1 Main loop

The server MUST:

1. On every iteration of its main loop, before checking for a new
   request, examine `consumed.txt`. If present, remove `response.txt`
   and `consumed.txt` (in that order, atomically per file). This
   eliminates the race where a client acknowledges a response and
   writes a new request in the same tick.
2. Check for `request.txt`. If present AND `processing.lock` is absent
   AND `response.txt` is absent, begin processing.
3. Otherwise, sleep briefly (the reference uses 500 ms) and continue.

The server MUST process at most one request at a time.

### 6.2 Per-model prompt wrapping

Different models require different prompt framing. The server MUST
apply per-model wrapping based on the active model name (matched by
prefix).

As of v0.2.5, the prefix → wrapping mapping is **data, not part of this
spec**: it lives in `skill/models/model_families.json` (`match_prefixes`
and `prompt_wrapping` fields), read directly by the reference
implementation at request time. This document previously embedded a copy
of that table here; it drifted out of sync with the reference
implementation and with `SKILL.md`'s own copy at least once, because the
same facts were hand-maintained in three places. See
`model_families.json`'s `_doc` field for the incident. This section now
states the *mechanism* (MUST language below); `model_families.json` is
authoritative for the *values*.

The server MUST:
1. Load `model_families.json` from alongside itself at startup/per-request.
2. Find the first `families` entry whose `match_prefixes` contains a
   case-insensitive prefix of the active model name.
3. If none match, use the `default` entry.
4. If the file is missing or unparseable, fall back to neutral,
   model-agnostic settings (no wrapping; see 6.3) rather than failing —
   a bad config file MUST NOT stop inference.

The mapping MUST be extensible; adding a new model family MUST require
only an addition to `model_families.json` and a corresponding tuning
file at `skill/models/<name>.md` — no change to this document or to the
server's code.

### 6.3 Per-model Ollama options

The server MUST apply per-model generation options, sourced from the
same `model_families.json` entry resolved in §6.2 (`ollama_options`
field). As with prompt wrapping, this document does not embed a copy of
the current values — see `model_families.json` directly, or the
human-readable summary table in `skill/models/README.md`.

If `model_families.json` is missing, unparseable, or the resolved entry
has no `ollama_options`, the server MUST fall back to
`{"temperature": 0.2, "repeat_penalty": 1.05}` with no other options set.

### 6.4 Output post-processing

After Ollama returns, the server MUST:

1. Strip surrounding markdown code fences. Specifically: remove a
   leading ` ```<language>?\n ` and a trailing ` ```\n? `, both
   anchored to the start/end of the response.
2. Strip the natural-language preamble before the first answer line,
   using whichever anchor matches earliest:
   - The `# start:` token from the request (explicit or auto-detected),
     allowing arbitrary leading whitespace on the matched line.
   - A code keyword at the start of a line: `import `, `from `, `def `,
     `class `, `#!/`, `@`, `async def `, `if __name__`.
3. Protect against false positives: do NOT strip a preamble if it
   appears to contain a code block (the regex `\n\s{4,}` matches any
   4-space-indented line) OR exceeds 400 characters.

### 6.5 Error handling

If Ollama returns a non-200 status or the inference times out (server
default: 120 s), the server MUST write `ERROR: <description>` to
`response.txt` and remove `request.txt` and `processing.lock` as it
would after a successful response. The server MUST NOT retry on its
own; retry is the client's choice.

### 6.6 Cleanup

On startup, the server MUST remove any stale `request.txt`,
`response.txt`, `consumed.txt`, and any `*.lock` files in the bridge
folder. This is necessary because a crashed previous instance may have
left them behind.

Every ~30 seconds during normal operation, the server SHOULD scan for
`*.lock` files older than 300 seconds and remove them as stale.

On graceful shutdown (SIGINT, SIGTERM), the server MUST remove all
transient files from the bridge folder.

### 6.7 PATH and environment

The server MUST construct a PATH that includes `/opt/homebrew/bin` and
`/usr/local/bin` so the `ollama` and `python3` binaries are findable
regardless of how the server was launched (interactive shell vs.
launchd-spawned).

The server MUST respect a `C2G_MODEL` environment variable if set,
using its value as the active model name. If absent, the server uses
its compiled-in default.

---

## 7. Client behavior

### 7.1 Pre-flight check

Before sending a request, the client SHOULD verify:

1. The bridge folder exists and is writable.
2. Ollama is reachable at `http://localhost:11434/api/tags` (HTTP 200).
3. The server (watcher) is running. Detection method is
   platform-specific; on macOS the reference is
   `pgrep -f start_local_ai.sh`.

If any check fails, the client MUST fall back to handling the task
itself rather than blocking indefinitely.

### 7.2 Send

The client MUST wait until the bridge is idle before writing a request:

```
no request.txt AND no response.txt AND no processing.lock
```

A 15-second wait with 1-second polling is sufficient in practice.

The client MUST then write `request.txt` atomically — typically by
writing to a temporary file and renaming, or by writing in one syscall
if the prompt fits in the OS page size.

### 7.3 Wait

The client MUST poll for `response.txt` with the following constraints:

- Maximum wait time: read from `delegation_timeout_seconds` in
  `bridge_config.json` (a small file living in the bridge folder itself,
  written by the Mac app's Settings whenever the user adjusts the
  delegation-timeout slider). Falls back to 120 seconds if the file is
  missing, malformed, or the value is non-positive. This is also the
  timeout `start_local_ai.sh` uses for its own Ollama request — both
  sides read the same file so they can't disagree.
  *(History: before 2026-07-03 this section claimed a fixed 60s
  default "configurable per model tuning file," which was never
  actually true — the timeout was hardcoded independently in three
  places (this spec, the skill, and the watcher) with three different
  values (60/90/120) and none of them read anything the user could
  actually change. Don't reintroduce a fixed number here.)*
- Polling interval: 1 second.
- The client MUST verify `processing.lock` is absent before reading
  `response.txt`. If the lock is still present, the file may be
  partially written.

### 7.4 Verify

After reading `response.txt`, the client MUST:

1. If the request had a `# id:` line, verify the response's first line
   exactly matches. If not, treat as a stale response and discard.
2. Check whether the response begins with `ERROR:`. If so, do not use
   the output.

### 7.5 Acknowledge

The client MUST write `consumed.txt` (any content; the file's existence
is the signal) after extracting the response body. This allows the
server to safely clean up.

### 7.6 Fallback

If any step fails — timeout, error response, mismatched id — the client
MUST fall back to handling the task itself (e.g. cloud inference) and
MUST NOT retry the same prompt against the local model. Retrying
typically reproduces the same failure and wastes time.

---

## 8. Concurrency

The protocol supports exactly one in-flight request per bridge folder.
Multiple concurrent clients sharing one bridge folder are not supported
and will produce undefined behavior (id mismatches, lost requests).

Hosts that need concurrency SHOULD use multiple bridge folders, one per
client process. The server-side architecture for multi-folder operation
is out of scope for this version of the spec.

---

## 9. Compatibility and versioning

This document specifies protocol version **v0.2.5**.

The protocol uses Semantic Versioning at the protocol level:

- **MAJOR** version increments on incompatible changes to the request
  or response format, the bridge folder layout, or the meaning of any
  existing field.
- **MINOR** version increments on backward-compatible additions
  (a new optional header line, a new outcome class).
- **PATCH** version increments on tuning or post-processing changes
  that do not affect the protocol surface.

The server SHOULD emit its protocol version in its startup banner.
Clients MAY use this for diagnostic purposes but MUST NOT make
behavior-changing decisions based on it within the same MAJOR version.

### 9.1 v0.2.5 changes from v0.2.4

- Per-model prompt wrapping (§6.2) and Ollama options (§6.3) moved out of
  this spec and out of the reference implementation's hardcoded
  branching, into `skill/models/model_families.json` — now the single
  source of truth, read directly by both the server and `SKILL.md` Step
  2. This is a PATCH-level change (tuning/post-processing mechanism, not
  the protocol surface): the wire format is unchanged, only where the
  per-model values live.
- Motivation: the three previously-independent copies of this mapping
  (this spec, `start_local_ai.sh`'s if/elif, `SKILL.md`'s routing table)
  had already drifted at least once.

### 9.2 v0.2.4 changes from v0.2.3

- Default model changed from `granite-code:8b` to `granite4.1:8b`.
- Prompt wrapping and stop-sequence handling are now per-model.
- `C2G_MODEL` environment variable now overrides the default model.

### 9.3 v0.2.3 changes from v0.2.2

- Added optional `# start:` request line and auto-detection of "Start
  with \`X\`" instructions in the prompt body.
- Preamble stripper now anchors on the start token in addition to code
  keywords, tolerating leading indentation.

### 9.4 v0.2.2 changes from v0.2.1

- Output post-processing now strips natural-language preambles before
  the first code-keyword line.

### 9.5 v0.2.1 changes from v0.2.0

- Per-model prompt wrapping introduced (IBM Q/A for `granite-code:*`).
- Per-model Ollama options pinned to IBM recommendations.

### 9.6 v0.2.0 baseline

- `# id:` request-ID convention.
- Race-fix cleanup pass before each new-request check.

---

## 10. Security considerations

The protocol does no authentication. Any process with read/write
access to the bridge folder can issue requests and read responses. On
single-user macOS this matches the trust boundary (one user, one
machine), but on multi-user hosts the bridge folder MUST be created
with restrictive permissions (mode 0700 or stricter).

The protocol carries plaintext prompts and responses. Prompts may
contain user code, file contents, or chat history. The bridge folder
location SHOULD NOT be world-readable.

The server passes the prompt to Ollama, which runs the local model.
Both the watcher and Ollama execute under the user's UID and have
access to whatever the user has access to. The user is responsible
for the trust posture of the model they pull and run.

---

## 11. Reference implementation

`start_local_ai.sh` in this repository at the v0.2.5 tag is the
reference implementation. Where this specification and the reference
implementation disagree, **this specification is authoritative** —
file a bug against the reference.

Alternative implementations (Python, Rust, native macOS daemon) are
welcome and should pass the conformance tests at
`tests/protocol_conformance/` (TODO: not yet written).
