#!/usr/bin/env bash
set -euo pipefail

BINARY="${C2G_MLX_BIN:-$(dirname "$0")/c2g-mlx/.build/arm64-apple-macosx/release/c2g-mlx}"

if [ ! -x "$BINARY" ]; then
    echo "Error: c2g-mlx binary not found at: $BINARY" >&2
    exit 1
fi

if [ $# -gt 0 ]; then
    PROMPT="$*"
else
    PROMPT=$(cat)
fi

CONTEXT="You are helping a developer build a Swift application using MLX-Swift. Be concise and provide working code examples."

echo "$CONTEXT

Question: $PROMPT

Answer:" | "$BINARY"
