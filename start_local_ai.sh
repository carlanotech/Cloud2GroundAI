#!/bin/bash
# start_local_ai.sh — Local AI delegation bridge for Claude/Cowork
#
# v0.2 protocol changes (2026-06-20):
#   1. Race fix: when consumed.txt is observed, response.txt and consumed.txt
#      are removed BEFORE the loop checks for the next request.txt. Eliminates
#      the window where a new request could be answered with the previous
#      response.
#   2. Request IDs: an optional first line of request.txt of the form
#      `# id: <uuid>` is preserved and echoed back as the first line of
#      response.txt, also as `# id: <uuid>`. Requests without an id line
#      are still accepted (backward compatible). The skill side is what
#      enforces id matching; the watcher just round-trips the field.
#
# v0.2.1 tuning changes (2026-06-20, afternoon):
#   3. Model-specific prompt wrapping. For Granite Code models, the prompt
#      is wrapped in the IBM-recommended "Question:/Answer:" template per
#      https://www.ibm.com/docs/en/watsonx/saas?topic=models-prompting-granite-code
#      Other models pass through unchanged.
#   4. Ollama generation options pinned to IBM-recommended values for
#      Granite Code: temperature=0 (greedy), repeat_penalty=1.05,
#      num_predict=900, stop=["<|endoftext|>"]. Same payload for any
#      model — Ollama ignores stop sequences a model doesn't emit.
#
# v0.2.2 tuning changes (2026-06-20, evening):
#   5. Output post-processing strips markdown fences and a short natural-
#      language preamble before the first code-keyword line, since the IBM
#      Q/A template encourages Granite to answer in prose first.
#
# v0.2.4 tuning changes (2026-06-29):
#   7. Default model is now granite4.1:8b (was granite-code:8b). Override
#      via the C2G_MODEL environment variable. IBM Q/A prompt template and
#      <|endoftext|> stop sequence are now applied ONLY for granite-code:*
#      because granite4.1 follows instructions directly (per its tuning
#      file in skill/models/granite4.1.md).
#   8. Per-model Ollama options. granite4.1 uses temperature 0.2,
#      num_predict 2048, no explicit stop sequence; granite-code retains
#      its IBM-recommended settings. Each model's values mirror the
#      corresponding skill/models/<name>.md tuning file.
#
# v0.2.5 tuning changes (2026-07-01):
#   9. Per-model prompt wrapping and Ollama options are no longer hardcoded
#      here as an if/elif/else chain keyed on model name. They're read at
#      request time from model_families.json (installed alongside this
#      script). This was a real, observed drift bug: the same facts were
#      hand-copied into this script, SKILL.md's routing table, and
#      protocol/SPEC.md §6.2/§6.3, and they went out of sync (README.md
#      kept listing granite-code as "active default" after granite4.1
#      became the default here). Adding or retuning a model family is now
#      a JSON edit, not a shell script edit. If model_families.json is
#      missing or malformed, this script falls back to neutral,
#      model-agnostic defaults rather than failing — see
#      load_family_config() in the inference step below.
#
# v0.2.6 tuning changes (2026-07-03):
#  10. Real, configurable Ollama request timeout. Previously hardcoded to
#      120s regardless of what the Settings slider (Preferences.
#      delegationTimeoutSeconds, 15-300s) said — that slider was UI-only
#      and never reached this script. Now read at request time from
#      bridge_config.json (written by the Mac app's BridgeConfigWriter
#      into the same $BRIDGE folder this script already reads/writes
#      every cycle). Missing or malformed config falls back to 120s, the
#      prior hardcoded value, so behavior is unchanged for anyone running
#      an older app build that's never written the file. SKILL.md's Step 4
#      poll loop reads the same file so the cloud side and the watcher
#      agree on how long "patient" actually means.
#
# v0.2.3 tuning changes (2026-06-22):
#   6. Expected-start anchoring. An optional "# start: <token>" request line
#      (after the optional id line) declares the token the answer should
#      begin with; if absent, a "Start with `X`" instruction in the prompt
#      is auto-detected. The preamble stripper now anchors on this token in
#      addition to the code keywords, allowing leading indentation. This
#      fixes pattern-completion output (e.g. `    "pump_2": {...}`) whose
#      first line is an indented quoted key the keyword-only anchor missed.
#      Backward compatible: requests without the line behave as before.
#
# v0.2.7 changes (2026-07-06):
#  11. Bridge folder relocated out of ~/Documents entirely, to
#      ~/claude_bridge/_bridge. The previous design (see the old comment
#      this replaces, kept below in spirit) assumed "Homebrew Python
#      retains the Documents grant from prior interactive use" — that grant
#      is never actually established by anything in this app's install
#      flow, so it failed on every fresh account, not as an edge case but
#      as the default. Confirmed via a clean Parallels VM test: every
#      python3 call touching the bridge folder failed with "[Errno 1]
#      Operation not permitted" — EPERM, the TCC-denial errno, not
#      EACCES/13 (an ordinary Unix permission problem). ~/Documents,
#      ~/Desktop, ~/Downloads, ~/Pictures etc. are macOS's specially
#      TCC-gated "personal data" folders; a plain folder elsewhere under
#      $HOME is governed by normal POSIX permissions only, which the
#      user's own account already satisfies. Users now connect
#      ~/claude_bridge to Cowork instead of ~/Documents/claude_bridge.
#
# Split-location design:
#   - Watcher script:  ~/Library/Application Support/claude_bridge/start_local_ai.sh
#     (out of ~/Documents/ so the LaunchAgent can run it without macOS TCC
#      blocking launchd-spawned bash.)
#   - Bridge folder:   ~/claude_bridge/_bridge/
#     (Cowork refuses to mount ~/Library/Application Support/ — protected
#      location — but it can mount any user-selected folder, so request and
#      response files live in this plain, non-TCC-gated home-directory
#      folder instead.)
#
# Manual run:  bash "$HOME/Library/Application Support/claude_bridge/start_local_ai.sh"
# Auto-start:  installed via install_autostart.sh
#
# Requirements: brew install ollama

MODEL="${C2G_MODEL:-granite4.1:8b}"
BRIDGE="$HOME/claude_bridge/_bridge"

# Directory this script actually lives in — used to find model_families.json
# installed alongside it (WatcherScriptInstaller copies both together).
# BASH_SOURCE (not $0) so this still resolves correctly if the script is
# ever sourced rather than executed directly.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FAMILIES_FILE="$SCRIPT_DIR/model_families.json"

# Model is overridable via the C2G_MODEL environment variable so the
# LaunchAgent plist (and end-user shell sessions) can swap models without
# editing this file. Per-model prompt wrapping and Ollama options are no
# longer decided here — see FAMILIES_FILE / load_family_config() below.

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

# ── Ensure Ollama is running ──────────────────────────────────────────────────
if ! pgrep -x "ollama" > /dev/null; then
    echo "→ Starting Ollama..."
    ollama serve &>/dev/null &
    sleep 3
else
    echo "✓ Ollama is already running"
fi

if ! ollama list | grep -q "$MODEL"; then
    echo "→ Pulling $MODEL (one-time)..."
    ollama pull "$MODEL"
fi
echo "✓ Model $MODEL is ready"

# ── Set up bridge folder ──────────────────────────────────────────────────────
mkdir -p "$BRIDGE"

# Startup cleanup. Plain bash — the bridge folder now lives outside
# ~/Documents (v0.2.7), so the old launchd/TCC reason for shelling out to
# python3 no longer applies. (v0.2.8, 2026-07-07: removed the python3
# dependency entirely so the watcher runs on a stock Mac with NO Command
# Line Tools — a fresh macOS has only a python3 stub that fails until Xcode
# CLT is installed. JSON/regex work moved to /usr/bin/perl + JSON::PP,
# which ship with macOS.)
rm -f "$BRIDGE/request.txt" "$BRIDGE/response.txt" "$BRIDGE/consumed.txt" 2>/dev/null
rm -f "$BRIDGE"/*.lock 2>/dev/null

WATCHER_VERSION="0.2.10"

echo "✓ Bridge ready at $BRIDGE"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Local AI delegation is ACTIVE"
echo "  Model: $MODEL  |  v${WATCHER_VERSION} (bash + perl, heartbeat status.json)"
echo "  You can minimize this window — leave it running."
echo "  Press Ctrl+C to shut down."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ── Heartbeat (v0.2.9, 2026-07-13) ────────────────────────────────────────────
# Writes _bridge/status.json so a sandboxed client can tell "watcher alive" from
# "watcher dead" — three states (alive / stale-unacked / busy) that otherwise
# look identical from the sandbox (skill feedback #2). Also publishes the active
# model so the client stops guessing it (#4). `seq` is the loop counter: a
# reader samples it twice and calls the watcher alive only if it ADVANCED, which
# is immune to host/sandbox clock skew. Written atomically (temp + mv) so a
# reader never sees a half-written file. NOTE: the bash loop blocks on the
# synchronous perl inference, so the beat is set to "processing" just before
# that block and resumes "idle" on the next tick after it returns.
write_status_json() {
    local dir="$1" model="$2" version="$3" pid="$4" seq="$5" state="$6"
    local tmp="$dir/status.json.tmp.$$"
    printf '{ "model": "%s", "watcher_version": "%s", "pid": %d, "seq": %d, "last_seen": %d, "state": "%s" }\n' \
        "$model" "$version" "$pid" "$seq" "$(date +%s)" "$state" > "$tmp" 2>/dev/null \
        && mv -f "$tmp" "$dir/status.json" 2>/dev/null
}

# Emit an initial beat immediately so `status` works the moment the bridge is up.
write_status_json "$BRIDGE" "$MODEL" "$WATCHER_VERSION" "$$" 0 idle

# ── Cleanup on exit / shutdown (v0.2.10, 2026-07-14) ──────────────────────────
# cleanup() removes only THIS watcher's transient protocol files — never
# bridge_config.json (written by the app's Settings slider) and never an
# unrelated file. The old handler ran `find "$BRIDGE" -mindepth 1 -delete` on
# every signal, blanket-wiping the whole shared _bridge (config included), and
# ran on TERM WITHOUT exiting — so a normal `kill` left the watcher running and
# you needed `kill -9`. Now: scoped delete, and INT/TERM actually exit.
cleanup() {
    [ -n "$BRIDGE" ] && rm -f \
        "$BRIDGE/request.txt" "$BRIDGE/response.txt" "$BRIDGE/consumed.txt" \
        "$BRIDGE/processing.lock" "$BRIDGE/status.json" "$BRIDGE"/.payload.* 2>/dev/null
}
trap 'echo ""; echo "→ Shutting down..."; cleanup; echo "✓ Done."; exit 0' INT TERM
trap 'cleanup' EXIT

# ── Main loop ─────────────────────────────────────────────────────────────────
loop_count=0

while true; do
    loop_count=$(( loop_count + 1 ))

    # ── Race-fix: cleanup pass FIRST, before looking at request.txt ───────────
    # If the client has acknowledged the previous response via consumed.txt,
    # remove response.txt and consumed.txt synchronously, in this same tick,
    # so they cannot leak into the next request cycle.
    if [ -f "$BRIDGE/consumed.txt" ]; then
        rm -f "$BRIDGE/response.txt" "$BRIDGE/consumed.txt" 2>/dev/null
    fi

    # Every 60 loops (~30s): clear stale locks (>5 min old).
    if [ $(( loop_count % 60 )) -eq 0 ]; then
        find "$BRIDGE" -name '*.lock' -type f -mmin +5 -delete 2>/dev/null
    fi

    # Heartbeat every 4 ticks (~2s) while idle. Skip while a lock is held — the
    # "processing" beat below owns the status during inference.
    if [ $(( loop_count % 4 )) -eq 0 ] && [ ! -f "$BRIDGE/processing.lock" ]; then
        write_status_json "$BRIDGE" "$MODEL" "$WATCHER_VERSION" "$$" "$loop_count" idle
    fi

    # ── Process a new request ────────────────────────────────────────────────
    # Only if a request is present AND no stale response/consumed remain.
    # The cleanup pass above guarantees those are gone when consumed was set,
    # so the most common race ("client sets consumed and writes a new request
    # before the watcher cleans up") is closed.
    if [ -f "$BRIDGE/request.txt" ] \
       && [ ! -f "$BRIDGE/processing.lock" ] \
       && [ ! -f "$BRIDGE/response.txt" ]; then

        echo "→ Task received — running local inference..."

        # Mark the heartbeat "processing" BEFORE blocking on inference, so a
        # client polling `status` sees BUSY (alive) rather than a frozen beat.
        write_status_json "$BRIDGE" "$MODEL" "$WATCHER_VERSION" "$$" "$loop_count" processing

        perl - "$BRIDGE" "$MODEL" "$FAMILIES_FILE" << 'INFERENCE_PL'
use strict;
use warnings;
use JSON::PP;
use Encode qw(decode encode);

my ($bridge, $model, $families_file) = @ARGV;

# Slurp a file as raw bytes; returns undef on failure.
sub slurp_bytes {
    my ($path) = @_;
    open(my $fh, '<:raw', $path) or return undef;
    local $/;
    my $data = <$fh>;
    close $fh;
    return $data;
}

# Clean up any stale lock files (>5 min) before taking the lock.
for my $lock (glob("$bridge/*.lock")) {
    next unless -f $lock;
    unlink $lock if (time - (stat($lock))[9]) > 300;
}

# Take the processing lock (write PID so crashes are diagnosable).
my $lockfile = "$bridge/processing.lock";
if (open(my $lf, '>', $lockfile)) { print $lf $$; close $lf; }
else { print "  x Could not create lock\n"; }

# Read the request (decode UTF-8 so multibyte prompts round-trip cleanly).
my $request_file = "$bridge/request.txt";
my $raw = slurp_bytes($request_file);
if (!defined $raw) {
    print "  x Could not read request\n";
    unlink($lockfile, $request_file);
    exit 1;
}
$raw = decode('UTF-8', $raw);

# Extract request ID if present: first line "# id: <token>".
my $request_id;
my $prompt = $raw;
if ($prompt =~ /^# id:\s*([A-Za-z0-9_\-]+)\s*\n/) {
    $request_id = $1;
    $prompt = substr($prompt, $+[0]);
}

# Optional expected-start token (v0.2.3): "# start: <token>" (backticks
# around the token are tolerated).
my $explicit_start;
if ($prompt =~ /^# start:\s*(.+?)\s*\n/) {
    $explicit_start = $1;
    if (length($explicit_start) >= 2
        && substr($explicit_start, 0, 1) eq '`'
        && substr($explicit_start, -1) eq '`') {
        $explicit_start = substr($explicit_start, 1, -1);
    }
    $prompt = substr($prompt, $+[0]);
}

$prompt =~ s/^\s+//;
$prompt =~ s/\s+$//;

# If no explicit start token, auto-detect a "Start with `X`" instruction.
if (!defined $explicit_start && $prompt =~ /[Ss]tart with\s*`([^`]+)`/) {
    $explicit_start = $1;
}

# Per-model prompt wrapping + Ollama options, driven by model_families.json.
# Single source of truth — add a JSON entry, not an if/elif branch here.
my %NEUTRAL = (
    prompt_wrapping => "none",
    ollama_options  => { temperature => 0.2, repeat_penalty => 1.05 },
);

sub load_family_config {
    my ($model_name, $path) = @_;
    my $bytes = slurp_bytes($path);
    my $config = defined($bytes) ? eval { decode_json($bytes) } : undef;
    return { %NEUTRAL } unless $config && ref $config eq 'HASH';
    my $ml = lc($model_name);
    for my $entry (@{ $config->{families} || [] }) {
        for my $p (@{ $entry->{match_prefixes} || [] }) {
            if (index($ml, lc($p)) == 0) {
                return {
                    prompt_wrapping => $entry->{prompt_wrapping} // "none",
                    ollama_options  => $entry->{ollama_options} // $NEUTRAL{ollama_options},
                };
            }
        }
    }
    if (my $d = $config->{default}) {
        return {
            prompt_wrapping => $d->{prompt_wrapping} // "none",
            ollama_options  => $d->{ollama_options} // $NEUTRAL{ollama_options},
        };
    }
    return { %NEUTRAL };
}

my $family = load_family_config($model, $families_file);

# Real, configurable request timeout (v0.2.6). bridge_config.json lives in
# the same $BRIDGE folder; missing/malformed falls back to 120s.
my $timeout = 120;
{
    my $bytes = slurp_bytes("$bridge/bridge_config.json");
    my $cfg = defined($bytes) ? eval { decode_json($bytes) } : undef;
    if ($cfg && ref $cfg eq 'HASH' && defined $cfg->{delegation_timeout_seconds}) {
        my $v = $cfg->{delegation_timeout_seconds} + 0;
        $timeout = $v if $v > 0;
    }
}

# Prompt wrapping. "ibm_qa" (Granite Code Question:/Answer:) is the only
# non-trivial strategy today; others pass through unchanged.
my $wrapped = $prompt;
if (($family->{prompt_wrapping} // "none") eq "ibm_qa") {
    $wrapped = "Question:\n$prompt\n\nAnswer:\n\n";
}

# Build the request payload and POST to Ollama via curl (Perl core has no
# HTTP client; curl ships with macOS). Payload goes through a temp file so
# arbitrary prompt content never has to survive shell quoting.
my $payload = encode_json({
    model   => $model,
    prompt  => $wrapped,
    stream  => \0,      # JSON false
    options => $family->{ollama_options},
});

my $payload_file = "$bridge/.payload.$$";
my $resp_file    = "$bridge/.resp.$$";
if (open(my $pf, '>:raw', $payload_file)) { print $pf $payload; close $pf; }

my $result;
my $rc = system('curl', '-s', '--max-time', $timeout,
                '-H', 'Content-Type: application/json',
                '--data-binary', '@' . $payload_file,
                '-o', $resp_file,
                'http://localhost:11434/api/generate');

if ($rc == 0) {
    my $body = slurp_bytes($resp_file);
    my $data = defined($body) ? eval { decode_json($body) } : undef;
    if ($data && ref $data eq 'HASH' && defined $data->{response}) {
        $result = $data->{response};
        # Strip markdown code fences.
        $result =~ s/^```[a-zA-Z]*\n?//mg;
        $result =~ s/\n?```\s*$//mg;
        $result =~ s/^\s+//;
        $result =~ s/\s+$//;
        # Strip natural-language preamble before the first real answer line.
        # Two anchors, whichever matches earliest: a code keyword at line
        # start, or the request's expected-start token (allowing indentation).
        my @cand;
        if ($result =~ /^(?:import |from |def |class |#!\/|\@|async def |if __name__)/m) {
            push @cand, $-[0];
        }
        if (defined $explicit_start && $result =~ /^[ \t]*\Q$explicit_start\E/m) {
            push @cand, $-[0];
        }
        if (@cand) {
            my ($anchor) = sort { $a <=> $b } @cand;
            if ($anchor > 0) {
                my $preamble = substr($result, 0, $anchor);
                $preamble =~ s/^\s+//;
                $preamble =~ s/\s+$//;
                # Only strip if the preamble isn't itself an indented block and
                # is short — guards against false positives where the anchor
                # token sits inside an example string or docstring.
                if (length($preamble)
                    && $preamble !~ /\n\s{4,}/
                    && length($preamble) < 400) {
                    $result = substr($result, $anchor);
                    $result =~ s/\s+$//;
                }
            }
        }
        print "  ok Done (" . length($result) . " chars) id=" . ($request_id // 'none') . "\n";

        # --- C2G savings ledger: record exact on-device token counts.
        # eval_count / prompt_eval_count come straight from Ollama's reply,
        # so the on-device number is EXACT. "Cloud tokens saved" is derived
        # later (in the GUI) and labelled as an estimate.
        {
            my $out_tok = $data->{eval_count}        // 0;
            my $in_tok  = $data->{prompt_eval_count} // 0;
            my $eval_ms = int(($data->{eval_duration} // 0) / 1_000_000);
            # Best-effort GPU correlation: only if a fresh metrics.json exists
            # (gpu_probe.sh running). Proves THIS delegation hit the GPU.
            my $gpu;
            if (my $mb = slurp_bytes("$bridge/metrics.json")) {
                my $m = eval { decode_json($mb) };
                if ($m && ref $m eq 'HASH' && defined $m->{ts}
                    && (time - $m->{ts}) <= 10) {
                    $gpu = $m->{gpu_util_pct};
                }
            }
            my $line = encode_json({
                ts            => time,
                id            => ($request_id // undef),
                model         => $model,
                output_tokens => $out_tok + 0,
                prompt_tokens => $in_tok + 0,
                eval_ms       => $eval_ms,
                gpu_util_pct  => (defined $gpu ? $gpu + 0 : undef),
            });
            if (open(my $lf, '>>:raw', "$bridge/ledger.jsonl")) {
                print $lf $line, "\n";
                close $lf;
            }
        }
    } else {
        $result = "ERROR: could not parse Ollama response";
        print "  x Inference error: unparseable response\n";
    }
} else {
    my $code = $rc == -1 ? -1 : ($rc >> 8);
    $result = "ERROR: Ollama request failed (curl exit $code)";
    print "  x Inference error: curl exit $code\n";
}

unlink($payload_file, $resp_file);

# Write the response, echoing the id back on the first line if provided.
my $response_file = "$bridge/response.txt";
if (open(my $wf, '>:raw', $response_file)) {
    print $wf "# id: $request_id\n" if defined $request_id;
    print $wf encode('UTF-8', $result);
    close $wf;
} else {
    print "  x Could not write response\n";
}

# Remove request and lock.
unlink($request_file, $lockfile);
INFERENCE_PL

    fi

    sleep 0.5
done
