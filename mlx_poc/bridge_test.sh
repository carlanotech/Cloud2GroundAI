#!/usr/bin/env bash
# bridge_test.sh — simulate the "Claude" (cloud) side of the bridge so you can
# test the full loop WITHOUT the real delegation skill. Writes a request with a
# unique id, waits for the matching response, prints it, then acks it.
#
# Usage:
#   ./bridge_test.sh                 # uses a default coding prompt
#   ./bridge_test.sh "your prompt"   # custom prompt
set -u

BRIDGE="${C2G_BRIDGE:-$HOME/claude_bridge/_bridge}"
PROMPT="${1:-Write a bash one-liner that prints the number of lines in every .txt file in the current directory.}"

mkdir -p "$BRIDGE"
id="t-$(date +%s)-$$"

# Wait for the bridge to be idle before sending.
for _ in $(seq 1 15); do
    [ ! -f "$BRIDGE/request.txt" ] \
        && [ ! -f "$BRIDGE/response.txt" ] \
        && [ ! -f "$BRIDGE/processing.lock" ] && break
    sleep 1
done

{ printf '# id: %s\n' "$id"; printf '%s\n' "$PROMPT"; } > "$BRIDGE/request.txt"
echo "→ sent id=$id"
echo "  prompt: $PROMPT"
echo ""

# Poll up to 180s (first call includes model download + load).
for _ in $(seq 1 180); do
    if [ -f "$BRIDGE/response.txt" ] && [ ! -f "$BRIDGE/processing.lock" ]; then
        first=$(head -n1 "$BRIDGE/response.txt")
        if [ "$first" = "# id: $id" ]; then
            echo "← response:"
            echo "────────────────────────────────────────"
            tail -n +2 "$BRIDGE/response.txt"
            echo "────────────────────────────────────────"
            echo done > "$BRIDGE/consumed.txt"
            exit 0
        fi
    fi
    sleep 1
done

echo "x  no matching response within 180s"
echo "   Check the watcher window and $BRIDGE/mlx.log"
exit 1
