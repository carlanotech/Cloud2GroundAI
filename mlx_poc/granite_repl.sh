#!/usr/bin/env bash
# granite_repl.sh — Interactive REPL for asking Granite questions
# 
# Usage: ./granite_repl.sh
#
# Type your questions and get answers from Granite.
# Type 'exit' or Ctrl+D to quit.
# Type 'help' for commands.

set -euo pipefail

BINARY="${C2G_MLX_BIN:-$(dirname "$0")/c2g-mlx/.build/arm64-apple-macosx/release/c2g-mlx}"

if [ ! -x "$BINARY" ]; then
    echo "Error: c2g-mlx binary not found at: $BINARY" >&2
    echo "Build it first or set C2G_MLX_BIN" >&2
    exit 1
fi

MODEL="${C2G_MLX_MODEL:-mlx-community/granite-3.3-2b-instruct-8bit}"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║     Granite Helper — Interactive REPL                     ║"
echo "║     Ask Granite questions to help build Phase 1           ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "Model: $MODEL"
echo "Binary: $BINARY"
echo ""
echo "Commands:"
echo "  help     - Show this help"
echo "  model    - Show current model"
echo "  exit     - Quit (or Ctrl+D)"
echo ""
echo "Ready! Ask a question:"
echo ""

CONTEXT="You are helping a developer build Swift applications using MLX-Swift for local AI inference. Be concise, practical, and provide working code examples when relevant."

while true; do
    # Show prompt
    printf "granite> "
    
    # Read input
    if ! read -r PROMPT; then
        echo ""
        echo "Goodbye!"
        exit 0
    fi
    
    # Handle empty input
    if [ -z "$PROMPT" ]; then
        continue
    fi
    
    # Handle commands
    case "$PROMPT" in
        exit|quit)
            echo "Goodbye!"
            exit 0
            ;;
        help)
            echo ""
            echo "Commands:"
            echo "  help     - Show this help"
            echo "  model    - Show current model"
            echo "  exit     - Quit"
            echo ""
            echo "Examples:"
            echo "  granite> How do I count tokens in Swift with MLX?"
            echo "  granite> Write a Swift function that writes JSON to a file"
            echo "  granite> Explain the ChatSession API in MLX-Swift"
            echo ""
            continue
            ;;
        model)
            echo "Current model: $MODEL"
            echo "Change with: export C2G_MLX_MODEL=mlx-community/granite-3.3-8b-instruct-8bit"
            echo ""
            continue
            ;;
    esac
    
    # Build full prompt
    FULL_PROMPT="$CONTEXT

Question: $PROMPT

Answer:"
    
    echo ""
    echo "───────────────────────────────────────────────────────────"
    
    # Run Granite
    echo "$FULL_PROMPT" | "$BINARY" 2>/dev/null || {
        echo "Error: Granite inference failed" >&2
        echo "Check that the model is downloaded and metallib is in place" >&2
    }
    
    echo ""
    echo "───────────────────────────────────────────────────────────"
    echo ""
done
