#!/bin/bash
# build-dmg.sh — Build, sign, notarize, and package Cloud2GroundAI as
# a DMG for GitHub Releases distribution.
#
# Prerequisites:
#   - Apple Developer Program membership (active, approved)
#   - Developer ID Application certificate installed in your Mac Keychain
#   - `xcrun notarytool` set up with stored credentials (see below)
#   - `create-dmg` installed: brew install create-dmg
#   - Xcode and the Cloud2Ground.xcodeproj available
#
# Notarytool credential setup (one-time):
#   xcrun notarytool store-credentials "C2G_NOTARY" \
#       --apple-id "your-apple-id@example.com" \
#       --team-id "__TEAM_ID__" \
#       --password "<app-specific-password-from-appleid.apple.com>"
#
# Usage:
#   ./scripts/build-dmg.sh           # default: build + sign + notarize + DMG
#   ./scripts/build-dmg.sh --no-notarize  # skip notarization (for dev iteration)
#   ./scripts/build-dmg.sh --no-sign      # also skip signing (development only)
#
# Output:
#   dist/Cloud2GroundAI_v<version>.dmg
#   dist/Cloud2GroundAI_v<version>.dmg.sha256

set -e
set -u
set -o pipefail

# ─── Configuration ──────────────────────────────────────────────────────────
TEAM_ID="HH62YCY422"                        # Apple Developer Team ID (10 chars)
APPLE_ID="acarlile@pm.me"                   # Your Apple ID email
NOTARY_PROFILE="C2G_NOTARY"                 # Stored credential name
DEVELOPER_ID_NAME="Developer ID Application: Carlano Technology Solutions LLC (${TEAM_ID})"

# Project paths (relative to repo root)
PROJECT_DIR="Cloud2Ground"
PROJECT_FILE="${PROJECT_DIR}/Cloud2Ground.xcodeproj"
SCHEME="Cloud2Ground"
CONFIGURATION="Release"

# Output paths
DIST_DIR="dist"
BUILD_DIR="${DIST_DIR}/build"
APP_NAME="Cloud2Ground.app"
DMG_VOLUME_NAME="Cloud2GroundAI"

# Version — pull from the Mac app's bundle short version string
VERSION=$(defaults read "$(pwd)/${PROJECT_DIR}/${PROJECT_DIR}/Info.plist" CFBundleShortVersionString 2>/dev/null \
          || grep -A1 'MARKETING_VERSION' "${PROJECT_FILE}/project.pbxproj" \
             | head -1 | sed 's/.*= //;s/;//' | tr -d ' ' \
          || echo "0.0.0")

# Flags
DO_SIGN=true
DO_NOTARIZE=true

while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-sign) DO_SIGN=false; DO_NOTARIZE=false ;;
        --no-notarize) DO_NOTARIZE=false ;;
        -h|--help)
            grep '^#' "$0" | head -30 | sed 's/^# //;s/^#//'
            exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
    shift
done

# ─── Pre-flight checks ──────────────────────────────────────────────────────
echo "================================================================"
echo "  build-dmg.sh — Cloud2GroundAI v${VERSION}"
echo "================================================================"

if [ "${TEAM_ID}" = "__TEAM_ID__" ] || [ "${APPLE_ID}" = "__APPLE_ID__" ]; then
    echo "ERROR: Edit this script to set TEAM_ID and APPLE_ID first."
    echo "       Look for the lines marked __TEAM_ID__ and __APPLE_ID__."
    exit 1
fi

if [ ! -d "${PROJECT_FILE}" ]; then
    echo "ERROR: Could not find ${PROJECT_FILE}"
    echo "       Run this script from the repository root."
    exit 1
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
    echo "ERROR: xcodebuild not found. Install Xcode."
    exit 1
fi

if ${DO_SIGN} && ! security find-identity -v -p codesigning | grep -q "${DEVELOPER_ID_NAME}"; then
    echo "ERROR: Developer ID Application certificate not found in keychain."
    echo "       Expected: ${DEVELOPER_ID_NAME}"
    echo "       Install via Xcode → Settings → Accounts → your team → Manage Certificates."
    exit 1
fi

if ! command -v create-dmg >/dev/null 2>&1; then
    echo "ERROR: create-dmg not installed. Run: brew install create-dmg"
    exit 1
fi

# ─── Clean ──────────────────────────────────────────────────────────────────
echo ""
echo "→ Cleaning previous build..."
rm -rf "${DIST_DIR}"
mkdir -p "${BUILD_DIR}"

# ─── Build via xcodebuild ───────────────────────────────────────────────────
echo ""
# Array, not a plain string: DEVELOPER_ID_NAME contains spaces and colons
# ("Developer ID Application: Carlano Technology Solutions LLC (TEAMID)").
# A plain string expanded unquoted gets word-split on every space by the
# shell, not just the ones separating these three settings — that word-
# split the literal word "ID" out of "Developer ID Application" straight
# into xcodebuild's argument list, which then read it as an attempted
# build action ("Unknown build action 'ID'"). An array + quoted "${@}"-
# style expansion keeps each setting as exactly one argument no matter
# what's inside it.
if ${DO_SIGN}; then
    CODE_SIGN_ARGS=(
        "CODE_SIGN_IDENTITY=${DEVELOPER_ID_NAME}"
        "CODE_SIGN_STYLE=Manual"
        "DEVELOPMENT_TEAM=${TEAM_ID}"
    )
else
    CODE_SIGN_ARGS=(
        "CODE_SIGN_IDENTITY=-"
        "CODE_SIGNING_REQUIRED=NO"
        "CODE_SIGNING_ALLOWED=NO"
    )
fi

# Wraps xcodebuild in xcbeautify only when it's actually installed.
# Previously this piped unconditionally with a `2>/dev/null || cat`
# fallback for the missing-binary case — broken, because the shell's own
# "command not found" error is what lands in that /dev/null (it fires
# before xcbeautify is ever found), so the failure was silent, and the
# `|| cat` fallback then ran bare `cat` with nothing piped to it, which
# just blocks forever reading the terminal's real stdin. Checking
# availability up front avoids that trap entirely.
run_xcodebuild() {
    if command -v xcbeautify >/dev/null 2>&1; then
        xcodebuild "$@" | xcbeautify
    else
        echo "  (xcbeautify not found — showing raw xcodebuild output. 'brew install xcbeautify' for prettier logs next time.)"
        xcodebuild "$@"
    fi
}

if ${DO_SIGN}; then
    # `xcodebuild build` (as opposed to `archive`) always injects the
    # com.apple.security.get-task-allow entitlement — Xcode adds it to
    # every non-archive build so the debugger can attach, regardless of
    # signing identity or CODE_SIGN_STYLE. Apple's notary service rejects
    # that entitlement outright, and a plain `build` also tends to skip
    # the secure code-signing timestamp that `archive`'s export step adds
    # automatically. So for signed (and therefore notarized) output we
    # have to go through the real archive → export pipeline, not `build`.
    echo "→ Archiving ${SCHEME} (${CONFIGURATION})..."
    ARCHIVE_PATH="${BUILD_DIR}/${APP_NAME%.app}.xcarchive"
    run_xcodebuild \
        -project "${PROJECT_FILE}" \
        -scheme "${SCHEME}" \
        -configuration "${CONFIGURATION}" \
        -archivePath "${ARCHIVE_PATH}" \
        "${CODE_SIGN_ARGS[@]}" \
        clean archive

    if [ ! -d "${ARCHIVE_PATH}" ]; then
        echo "ERROR: Archive step succeeded but ${ARCHIVE_PATH} not found"
        exit 1
    fi
    echo "✓ archived: ${ARCHIVE_PATH}"

    echo ""
    echo "→ Exporting signed .app for Developer ID distribution..."
    EXPORT_DIR="${BUILD_DIR}/export"
    EXPORT_OPTIONS_PLIST="${BUILD_DIR}/export-options.plist"
    cat > "${EXPORT_OPTIONS_PLIST}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>${TEAM_ID}</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>signingCertificate</key>
    <string>Developer ID Application</string>
</dict>
</plist>
PLIST

    run_xcodebuild \
        -exportArchive \
        -archivePath "${ARCHIVE_PATH}" \
        -exportPath "${EXPORT_DIR}" \
        -exportOptionsPlist "${EXPORT_OPTIONS_PLIST}"

    BUILT_APP="${EXPORT_DIR}/${APP_NAME}"
    if [ ! -d "${BUILT_APP}" ]; then
        echo "ERROR: Export succeeded but ${APP_NAME} not found at ${BUILT_APP}"
        exit 1
    fi
    echo "✓ exported (archive method, no get-task-allow, secure timestamp): ${BUILT_APP}"
else
    # --no-sign path: a plain `build` is fine here since this output is
    # never notarized — get-task-allow and timestamp don't matter for
    # local, unsigned dev iteration.
    echo "→ Building ${SCHEME} (${CONFIGURATION}, unsigned)..."
    run_xcodebuild \
        -project "${PROJECT_FILE}" \
        -scheme "${SCHEME}" \
        -configuration "${CONFIGURATION}" \
        -derivedDataPath "${BUILD_DIR}/dd" \
        -destination "platform=macOS" \
        "${CODE_SIGN_ARGS[@]}" \
        clean build

    BUILT_APP="${BUILD_DIR}/dd/Build/Products/${CONFIGURATION}/${APP_NAME}"
    if [ ! -d "${BUILT_APP}" ]; then
        echo "ERROR: Build succeeded but ${APP_NAME} not found at ${BUILT_APP}"
        exit 1
    fi
    echo "✓ built: ${BUILT_APP}"
fi

# ─── Copy app to dist ───────────────────────────────────────────────────────
APP_STAGE="${DIST_DIR}/stage"
mkdir -p "${APP_STAGE}"
cp -R "${BUILT_APP}" "${APP_STAGE}/${APP_NAME}"

# ─── Code sign (if not already done by xcodebuild) ──────────────────────────
if ${DO_SIGN}; then
    echo ""
    echo "→ Verifying code signature..."
    codesign --verify --deep --strict --verbose=2 "${APP_STAGE}/${APP_NAME}"
    echo "✓ signed and verified"
fi

# ─── Notarize ───────────────────────────────────────────────────────────────
if ${DO_NOTARIZE}; then
    echo ""
    echo "→ Notarizing (this can take several minutes)..."

    # Notarytool wants a zip, not the .app directly
    NOTARY_ZIP="${DIST_DIR}/${APP_NAME}.zip"
    ditto -c -k --sequesterRsrc --keepParent "${APP_STAGE}/${APP_NAME}" "${NOTARY_ZIP}"

    xcrun notarytool submit "${NOTARY_ZIP}" \
        --keychain-profile "${NOTARY_PROFILE}" \
        --wait

    # Staple the notarization to the .app so Gatekeeper accepts it offline
    xcrun stapler staple "${APP_STAGE}/${APP_NAME}"
    echo "✓ notarized and stapled"

    rm "${NOTARY_ZIP}"
fi

# ─── Build the DMG ──────────────────────────────────────────────────────────
echo ""
echo "→ Building DMG..."
DMG_NAME="Cloud2GroundAI_v${VERSION}.dmg"
DMG_PATH="${DIST_DIR}/${DMG_NAME}"

# Volume icon (the mounted disk's own icon in Finder) — reuses the app art.
# Guarded: only added if the .icns is present, so a missing file can never
# break the build.
VOLICON="release_staging/dmg-volicon.icns"
VOLICON_ARGS=()
if [ -f "${VOLICON}" ]; then VOLICON_ARGS=(--volicon "${VOLICON}"); fi

create-dmg \
    --volname "${DMG_VOLUME_NAME}" \
    "${VOLICON_ARGS[@]}" \
    --window-size 600 400 \
    --icon "${APP_NAME}" 150 200 \
    --app-drop-link 450 200 \
    --hide-extension "${APP_NAME}" \
    "${DMG_PATH}" \
    "${APP_STAGE}/" \
    || { echo "create-dmg failed"; exit 1; }

# ─── Sign and notarize the DMG itself ───────────────────────────────────────
if ${DO_SIGN}; then
    echo ""
    echo "→ Signing DMG..."
    codesign --sign "${DEVELOPER_ID_NAME}" "${DMG_PATH}"
fi

if ${DO_NOTARIZE}; then
    echo ""
    echo "→ Notarizing DMG..."
    xcrun notarytool submit "${DMG_PATH}" \
        --keychain-profile "${NOTARY_PROFILE}" \
        --wait
    xcrun stapler staple "${DMG_PATH}"
    echo "✓ DMG notarized and stapled"
fi

# ─── Checksum ───────────────────────────────────────────────────────────────
echo ""
echo "→ Computing SHA-256..."
SHA_FILE="${DMG_PATH}.sha256"
shasum -a 256 "${DMG_PATH}" > "${SHA_FILE}"
echo "✓ ${SHA_FILE}"

# ─── Cleanup ────────────────────────────────────────────────────────────────
rm -rf "${APP_STAGE}" "${BUILD_DIR}"

# ─── Summary ────────────────────────────────────────────────────────────────
echo ""
echo "================================================================"
echo "  ✅ DMG built: ${DMG_PATH}"
echo "================================================================"
echo ""
echo "Size:     $(du -h "${DMG_PATH}" | cut -f1)"
echo "SHA-256:  $(cat "${SHA_FILE}" | awk '{print $1}')"
echo ""
echo "Next steps:"
echo "  1. Test the DMG: open '${DMG_PATH}' on a clean Mac"
echo "  2. Verify Gatekeeper accepts: spctl -a -t open --context context:primary-signature -v '${DMG_PATH}'"
echo "  3. Create a GitHub Release and upload the DMG + .sha256 as assets"
echo ""
