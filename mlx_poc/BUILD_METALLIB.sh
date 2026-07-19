#!/usr/bin/env bash
# BUILD_METALLIB.sh — compile MLX Metal shaders into mlx.metallib
# Run this after `swift build` if you need to rebuild the Metal library.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
METAL_SRC="$SCRIPT_DIR/c2g-mlx/.build/checkouts/mlx-swift/Source/Cmlx/mlx-generated/metal"
BUILD_DIR="$SCRIPT_DIR/c2g-mlx/.build/arm64-apple-macosx/release"
TMP_DIR="/tmp/mlx_metal_build_$$"

echo "→ Compiling Metal shaders..."
mkdir -p "$TMP_DIR"

cd "$METAL_SRC"

# Compile all .metal files
for f in *.metal steel/attn/kernels/*.metal; do
    [ -f "$f" ] || continue
    echo "  - $(basename "$f")"
    xcrun -sdk macosx metal -c "$f" -o "$TMP_DIR/$(basename "${f%.metal}").air"
done

# Create metallib
echo "→ Creating mlx.metallib..."
xcrun -sdk macosx metallib "$TMP_DIR"/*.air -o "$TMP_DIR/mlx.metallib"

# Copy to build directory
cp "$TMP_DIR/mlx.metallib" "$BUILD_DIR/mlx.metallib"

# Cleanup
rm -rf "$TMP_DIR"

echo "✓ Metal library ready at: $BUILD_DIR/mlx.metallib"
ls -lh "$BUILD_DIR/mlx.metallib"
