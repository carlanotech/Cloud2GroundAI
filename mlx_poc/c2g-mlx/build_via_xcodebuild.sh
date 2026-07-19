#!/bin/bash
# build_via_xcodebuild.sh — build c2g-mlx via Xcode's build system so the
# Metal shader library actually gets produced.
#
# Why this exists:
#   `swift build -c release` on mlx-swift compiles the C++ but does NOT
#   invoke Xcode's Metal shader build phase. The default.metallib and the
#   `mlx-swift_Cmlx.bundle` never get created, so the resulting binary fails
#   with "MLX error: Failed to load the default metallib" at model load.
#
#   xcodebuild uses Xcode's build system, which handles Metal compilation
#   correctly. It's what Apple's own `mlx-run` script wraps internally.
#
# What this does:
#   1. Confirms xcodebuild is on PATH.
#   2. Builds c2g-mlx via xcodebuild with an explicit Apple Silicon
#      destination (avoids the "My Mac vs Any Mac" ambiguity mlx-run hit).
#   3. Locates the built binary and metallib bundle in DerivedData.
#   4. Copies both into ./bin/ next to this script so watch_mlx.sh has a
#      stable path.
#   5. Prints the exact command to run c2g-mlx.

set -e

SCHEME="c2g-mlx"
CONFIG="Release"
DESTINATION="platform=macOS,arch=arm64"
HERE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
OUT_DIR="$HERE/bin"

echo "============================================================"
echo "  c2g-mlx — build via xcodebuild"
echo "============================================================"
echo ""

# 1. Sanity: xcodebuild present, xcode-select points at a real Xcode
if ! command -v xcodebuild >/dev/null 2>&1; then
    echo "  xcodebuild not on PATH."
    echo "  Try: xcode-select --install"
    exit 2
fi
xcodeSelect=$(xcode-select --print-path 2>/dev/null || true)
echo "  xcode-select --print-path: $xcodeSelect"
if [[ "$xcodeSelect" != *"/Xcode.app/"* ]]; then
    echo ""
    echo "  WARNING: xcode-select does not point at Xcode.app."
    echo "  Fix with:  sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer"
    echo "  Continuing anyway."
fi
echo ""

# 2. Build via xcodebuild
echo "  -> xcodebuild -scheme $SCHEME -destination '$DESTINATION' -configuration $CONFIG build"
echo ""

# Build and capture the SYMROOT so we can find the products afterward
BUILD_LOG="$HERE/xcodebuild.log"
xcodebuild \
    -scheme "$SCHEME" \
    -destination "$DESTINATION" \
    -configuration "$CONFIG" \
    -derivedDataPath "$HERE/.derived" \
    build 2>&1 | tee "$BUILD_LOG"

XCODEBUILD_STATUS=${PIPESTATUS[0]}
if [ "$XCODEBUILD_STATUS" -ne 0 ]; then
    echo ""
    echo "  xcodebuild failed (exit $XCODEBUILD_STATUS)."
    echo "  Full log: $BUILD_LOG"
    echo ""
    echo "  Common failure modes:"
    echo "  - Scheme not found: xcodebuild -list to see what schemes exist,"
    echo "    or open Package.swift in Xcode once so it generates the scheme."
    echo "  - Destination invalid: try -destination 'generic/platform=macOS'"
    echo "  - Signing complaints: add -allowProvisioningUpdates or"
    echo "    CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO"
    exit "$XCODEBUILD_STATUS"
fi

# 3. Locate build products
PRODUCTS_DIR="$HERE/.derived/Build/Products/$CONFIG"
if [ ! -d "$PRODUCTS_DIR" ]; then
    # Some xcodebuild variants use just 'Release' at the top level
    PRODUCTS_DIR=$(find "$HERE/.derived" -type d -name "$CONFIG" 2>/dev/null | head -1)
fi

if [ -z "$PRODUCTS_DIR" ] || [ ! -d "$PRODUCTS_DIR" ]; then
    echo ""
    echo "  Build succeeded but I can't find the Products directory."
    echo "  Look manually with:  find $HERE/.derived -type f -name c2g-mlx"
    exit 3
fi

echo ""
echo "  Products directory: $PRODUCTS_DIR"

BIN_PATH=$(find "$PRODUCTS_DIR" -maxdepth 3 -name c2g-mlx -type f 2>/dev/null | head -1)
BUNDLE_PATH=$(find "$PRODUCTS_DIR" -maxdepth 3 -name 'mlx-swift_Cmlx.bundle' -type d 2>/dev/null | head -1)
METALLIB_PATH=$(find "$PRODUCTS_DIR" -maxdepth 5 -name 'default.metallib' -type f 2>/dev/null | head -1)

echo "  Binary:            ${BIN_PATH:-NOT FOUND}"
echo "  Cmlx bundle:       ${BUNDLE_PATH:-NOT FOUND}"
echo "  default.metallib:  ${METALLIB_PATH:-NOT FOUND}"

if [ -z "$BIN_PATH" ] || [ -z "$METALLIB_PATH" ]; then
    echo ""
    echo "  One or more expected products are missing. Investigate:"
    echo "    find $HERE/.derived -type f -name c2g-mlx"
    echo "    find $HERE/.derived -type f -name '*.metallib'"
    echo "    find $HERE/.derived -type d -name '*.bundle'"
    exit 4
fi

# 4. Stage a stable location for watch_mlx.sh
mkdir -p "$OUT_DIR"
cp -R "$BIN_PATH" "$OUT_DIR/"
if [ -n "$BUNDLE_PATH" ]; then
    rm -rf "$OUT_DIR/$(basename "$BUNDLE_PATH")"
    cp -R "$BUNDLE_PATH" "$OUT_DIR/"
fi

echo ""
echo "  Staged into: $OUT_DIR"
ls -la "$OUT_DIR"

# 5. Test line
echo ""
echo "============================================================"
echo "  Try it:"
echo ""
echo "    echo \"Write a Python function that reverses a string.\" | \\"
echo "      $OUT_DIR/c2g-mlx"
echo ""
echo "  If it generates text, Stage 1b is unblocked. Next step is to"
echo "  point watch_mlx.sh at $OUT_DIR/c2g-mlx and run through the"
echo "  full bridge loop."
echo "============================================================"
