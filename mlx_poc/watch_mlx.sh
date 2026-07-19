#!/usr/bin/env bash
# watch_mlx.sh — minimal Cloud2Ground bridge watcher backed by c2g-mlx (MLX).
#
# POC replacement for start_local_ai.sh with Ollama removed entirely. It polls
# the SAME _bridge folder and speaks the SAME protocol (request.txt / id echo /
# response.txt / consumed.txt / processing.lock) as the production watcher, so
# the existing delegation skill and bridge_test.sh both work against it.
#
# Deliberately does NOT reimplement heartbeat / ledger / model_families / fence
# stripping from the production watcher — none of that is needed to prove the
# Claude -> bridge -> Granite loop. Once the loop is proven, those features port
# over one at a time.
#
# Stop with Ctrl+C.
set -u

# ── Config (all overridable via env) ─────────────────────────────────────────
BRIDGE="${C2G_BRIDGE:-$HOME/claude_bridge/_bridge}"
MODEL="${C2G_MLX_MODEL:-mlx-community/granite-3.3-2b-instruct-8bit}"
# Point this at the built binary. Default assumes the package sits alongside
# this script. The binary needs to be in the same directory as mlx.metallib.
DEFAULT_BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/c2g-mlx/.build/arm64-apple-macosx/release/c2g-mlx"
BIN="${C2G_MLX_BIN:-$DEFAULT_BIN}"

export C2G_MLX_MODEL="$MODEL"

mkdir -p "$BRIDGE"
rm -f "$BRIDGE/request.txt" "$BRIDGE/response.txt" "$BRIDGE/consumed.txt" "$BRIDGE"/*.lock 2>/dev/null

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  C2G MLX watcher (POC) — no Ollama"
echo "  Bridge: $BRIDGE"
echo "  Model:  $MODEL"
echo "  Binary: $BIN"
echo "  Ctrl+C to stop."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ ! -x "$BIN" ]; then
    echo "x  c2g-mlx binary not found / not executable:"
    echo "     $BIN"
    echo "   Build it first (README Stage 1) or set C2G_MLX_BIN."
    exit 1
fi

# Check for metallib
METALLIB_DIR="$(dirname "$BIN")"
if [ ! -f "$METALLIB_DIR/mlx.metallib" ]; then
    echo "x  mlx.metallib not found in:"
    echo "     $METALLIB_DIR"
    echo "   Copy it there: cp /tmp/mlx.metallib \"$METALLIB_DIR/mlx.metallib\""
    exit 1
fi

cleanup() {
    rm -f "$BRIDGE/request.txt" "$BRIDGE/response.txt" "$BRIDGE/consumed.txt" \
          "$BRIDGE"/*.lock "$BRIDGE"/.mlxprompt.* 2>/dev/null
}
trap 'echo; echo "→ shutting down"; cleanup; exit 0' INT TERM
trap cleanup EXIT

echo "✓ ready — waiting for requests"
echo ""

while true; do
    # Client acked the previous response -> clear it this tick.
    if [ -f "$BRIDGE/consumed.txt" ]; then
        rm -f "$BRIDGE/response.txt" "$BRIDGE/consumed.txt" 2>/dev/null
    fi

    if [ -f "$BRIDGE/request.txt" ] \
       && [ ! -f "$BRIDGE/response.txt" ] \
       && [ ! -f "$BRIDGE/processing.lock" ]; then

        echo "$$" > "$BRIDGE/processing.lock"
        raw=$(cat "$BRIDGE/request.txt")

        # Request id from the first "# id:" line (echoed back so the client
        # can match its request to this response).
        id=$(printf '%s\n' "$raw" \
             | sed -n 's/^# id:[[:space:]]*\([A-Za-z0-9_-][A-Za-z0-9_-]*\).*/\1/p' \
             | head -1)

        # Prompt body = request minus the "# id:" / "# start:" header lines,
        # with leading blank lines trimmed.
        promptfile="$BRIDGE/.mlxprompt.$$"
        printf '%s\n' "$raw" \
            | sed '/^# id:/d; /^# start:/d' \
            | sed -e '/./,$!d' > "$promptfile"

        echo "→ request id=${id:-none} — running MLX…"
        t0=$(date +%s)
        out=$("$BIN" --file "$promptfile" 2>>"$BRIDGE/mlx.log")
        rc=$?
        t1=$(date +%s)

        if [ $rc -ne 0 ]; then
            out="ERROR: c2g-mlx exit $rc (see $BRIDGE/mlx.log)"
            echo "  x inference failed (exit $rc)"
        fi

        {
            [ -n "$id" ] && printf '# id: %s\n' "$id"
            printf '%s' "$out"
        } > "$BRIDGE/response.txt"

        echo "✓ done in $((t1 - t0))s (${#out} chars)"
        rm -f "$promptfile" "$BRIDGE/request.txt" "$BRIDGE/processing.lock" 2>/dev/null
    fi

    sleep 1
done
