#!/usr/bin/env bash
# watch_mlx.sh v2.0-phase1 with all features
set -u

BRIDGE="${C2G_BRIDGE:-$HOME/claude_bridge/_bridge}"
# Default matches SKILL-MLX.md's documented default (8B for quality; the
# 2B fast-mode fallback produced unreliable code output in testing — see
# skill/bridge_delegate test notes 2026-07-18).
MODEL="${C2G_MLX_MODEL:-mlx-community/granite-3.3-8b-instruct-8bit}"
TEMPERATURE="${C2G_MLX_TEMPERATURE:-0.2}"
HEARTBEAT_INTERVAL=5

DEFAULT_BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/c2g-mlx/.build/arm64-apple-macosx/release/c2g-mlx"
BIN="${C2G_MLX_BIN:-$DEFAULT_BIN}"

export C2G_MLX_MODEL="$MODEL"

mkdir -p "$BRIDGE"

# Cleanup stale locks
if [ -f "$BRIDGE/processing.lock" ]; then
    LOCK_PID=$(cat "$BRIDGE/processing.lock" 2>/dev/null || echo "")
    if [ -n "$LOCK_PID" ] && ! ps -p "$LOCK_PID" > /dev/null 2>&1; then
        echo "→ Cleaning stale lock (PID $LOCK_PID)"
        rm -f "$BRIDGE/processing.lock"
    fi
fi

rm -f "$BRIDGE/request.txt" "$BRIDGE/response.txt" "$BRIDGE/consumed.txt" 2>/dev/null

VERSION="2.0-phase1"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  C2G MLX watcher v$VERSION"
echo "  Bridge: $BRIDGE"
echo "  Model:  $MODEL"
echo "  Temp:   $TEMPERATURE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ ! -x "$BIN" ]; then
    echo "x  Binary not found: $BIN"
    exit 1
fi

# Initialize savings ledger
LEDGER="$BRIDGE/../savings.json"
if [ ! -f "$LEDGER" ]; then
    cat > "$LEDGER" << EOFJSON
{
  "total_requests": 0,
  "total_input_tokens": 0,
  "total_output_tokens": 0,
  "estimated_cost_saved_usd": 0.0,
  "last_updated": $(date +%s),
  "version": "$VERSION"
}
EOFJSON
fi

write_status() {
    cat > "$BRIDGE/status.json" << EOFJSON
{
  "status": "$1",
  "model": "$MODEL",
  "temperature": $TEMPERATURE,
  "backend": "mlx-swift",
  "version": "$VERSION",
  "last_heartbeat": $(date +%s)
}
EOFJSON
}

count_tokens() {
    local words=$(echo "$1" | wc -w | tr -d ' ')
    echo $(( words * 13 / 10 ))
}

# Port of start_local_ai.sh's fence-stripping (MLX_PRODUCTION_PLAN.md Phase 1.1).
# Deletes any line that's solely a ``` fence marker (opening w/ optional lang
# tag, or bare closing), wherever it appears — not just a wrapping pair —
# since real 8B output embeds fenced blocks inside surrounding prose.
strip_fences() {
    printf '%s\n' "$1" | sed -E '/^```[A-Za-z0-9_+-]*[[:space:]]*$/d' \
        | sed -e '/./,$!d' -e '1!G;h;$!d' \
        | sed -e '/./,$!d' -e '1!G;h;$!d'
}

update_savings() {
    local in_tok=$1
    local out_tok=$2
    local total_req=$(jq -r '.total_requests // 0' "$LEDGER" 2>/dev/null || echo 0)
    local total_in=$(jq -r '.total_input_tokens // 0' "$LEDGER" 2>/dev/null || echo 0)
    local total_out=$(jq -r '.total_output_tokens // 0' "$LEDGER" 2>/dev/null || echo 0)
    
    total_req=$((total_req + 1))
    total_in=$((total_in + in_tok))
    total_out=$((total_out + out_tok))
    
    local cost=$(echo "scale=6; ($total_in * 3 + $total_out * 15) / 1000000" | bc 2>/dev/null || echo "0.000000")
    # bc omits the leading zero on fractional-only results (".013452"),
    # which is invalid JSON — pad it back in.
    case "$cost" in
        .*)  cost="0$cost" ;;
        -.*) cost="-0${cost#-}" ;;
    esac
    
    cat > "$LEDGER" << EOFJSON
{
  "total_requests": $total_req,
  "total_input_tokens": $total_in,
  "total_output_tokens": $total_out,
  "estimated_cost_saved_usd": $cost,
  "last_updated": $(date +%s),
  "version": "$VERSION"
}
EOFJSON
}

cleanup() {
    echo ""
    echo "→ shutting down"
    write_status "stopped"
    rm -f "$BRIDGE/request.txt" "$BRIDGE/response.txt" "$BRIDGE/consumed.txt" \
          "$BRIDGE"/*.lock "$BRIDGE"/.mlxprompt.* 2>/dev/null
    exit 0
}
trap cleanup INT TERM
trap 'write_status "stopped"' EXIT

write_status "ready"
echo "✓ ready — waiting for requests"
echo ""

LAST_HEARTBEAT=0

while true; do
    NOW=$(date +%s)
    if [ $((NOW - LAST_HEARTBEAT)) -ge $HEARTBEAT_INTERVAL ]; then
        write_status "ready"
        LAST_HEARTBEAT=$NOW
    fi
    
    if [ -f "$BRIDGE/consumed.txt" ]; then
        rm -f "$BRIDGE/response.txt" "$BRIDGE/consumed.txt" 2>/dev/null
    fi
    
    if [ -f "$BRIDGE/request.txt" ] && [ ! -f "$BRIDGE/response.txt" ] && [ ! -f "$BRIDGE/processing.lock" ]; then
        echo "$$" > "$BRIDGE/processing.lock"
        write_status "processing"
        
        raw=$(cat "$BRIDGE/request.txt")
        id=$(printf '%s\n' "$raw" | sed -n 's/^# id:[[:space:]]*\([A-Za-z0-9_-][A-Za-z0-9_-]*\).*/\1/p' | head -1)
        
        promptfile="$BRIDGE/.mlxprompt.$$"
        printf '%s\n' "$raw" | sed '/^# id:/d; /^# start:/d' | sed -e '/./,$!d' > "$promptfile"
        
        prompt_text=$(cat "$promptfile")
        input_tokens=$(count_tokens "$prompt_text")
        
        echo "→ request id=${id:-none} (${input_tokens} tokens)"
        t0=$(date +%s)
        
        out=$("$BIN" --file "$promptfile" 2>>"$BRIDGE/mlx.log")
        rc=$?
        t1=$(date +%s)
        
        if [ $rc -ne 0 ]; then
            out="ERROR: c2g-mlx exit $rc"
        else
            out=$(strip_fences "$out")
            output_tokens=$(count_tokens "$out")
            update_savings "$input_tokens" "$output_tokens"
            
            cost_saved=$(jq -r '.estimated_cost_saved_usd' "$LEDGER" 2>/dev/null || echo "0")
            echo "✓ done in $((t1 - t0))s ($output_tokens tokens) 💰 \$$cost_saved saved"
        fi
        
        {
            [ -n "$id" ] && printf '# id: %s\n' "$id"
            printf '%s' "$out"
        } > "$BRIDGE/response.txt"
        
        rm -f "$promptfile" "$BRIDGE/request.txt" "$BRIDGE/processing.lock" 2>/dev/null
        write_status "ready"
    fi
    
    sleep 1
done
