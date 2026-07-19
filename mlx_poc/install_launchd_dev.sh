#!/usr/bin/env bash
# Install the dev-only MLX watcher LaunchAgent so watch_mlx_v2.sh survives
# logout/reboot. Separate from the app's own installer (LaunchAgentInstaller.swift)
# — see com.cloud2ground.mlx-watcher-dev.plist.template's header comment for why.
#
# IMPORTANT: launchd cannot run anything from inside the ProtonDrive
# CloudStorage mount — a background LaunchAgent (no interactive session)
# gets EPERM on both cwd and exec there ("Operation not permitted"),
# confirmed by testing 2026-07-19. Same class of TCC-style gotcha already
# documented in WatcherScriptInstaller.swift for ~/Documents. Fix is the
# same pattern: copy everything the watcher needs OUT of the synced
# folder to a plain location first, then point the LaunchAgent at the copy.
#
# Uses `launchctl bootstrap` (not the deprecated `load`), and always targets
# the specific service (gui/<uid>/<label>) for bootout/print — never the bare
# gui/<uid> domain, which logs the user out. Same safety rule the app's own
# installer follows (LaunchAgentInstaller.swift's validateBootoutSafety()).
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LABEL="com.cloud2ground.mlx-watcher-dev"
TEMPLATE="$REPO_DIR/mlx_poc/com.cloud2ground.mlx-watcher-dev.plist.template"
DEST="$HOME/Library/LaunchAgents/$LABEL.plist"
SERVICE_TARGET="gui/$(id -u)/$LABEL"

# Plain, non-cloud-synced install location — same rationale as the app's
# own WatcherScriptInstaller.installedScriptURL.
INSTALL_DIR="$HOME/Library/Application Support/Cloud2Ground/mlx-dev"
SRC_BIN="$REPO_DIR/mlx_poc/c2g-mlx/.build/arm64-apple-macosx/release/c2g-mlx"
SRC_METALLIB="$REPO_DIR/mlx_poc/c2g-mlx/.build/arm64-apple-macosx/release/mlx.metallib"
SRC_WATCHER="$REPO_DIR/mlx_poc/watch_mlx_v2.sh"

if [ ! -f "$TEMPLATE" ]; then
    echo "Template not found: $TEMPLATE" >&2
    exit 1
fi
for f in "$SRC_BIN" "$SRC_METALLIB" "$SRC_WATCHER"; do
    if [ ! -f "$f" ]; then
        echo "Missing required file: $f (run 'swift build -c release' in mlx_poc/c2g-mlx first)" >&2
        exit 1
    fi
done

mkdir -p "$INSTALL_DIR"
cp "$SRC_BIN" "$INSTALL_DIR/c2g-mlx"
cp "$SRC_METALLIB" "$INSTALL_DIR/mlx.metallib"
cp "$SRC_WATCHER" "$INSTALL_DIR/watch_mlx_v2.sh"
chmod +x "$INSTALL_DIR/c2g-mlx" "$INSTALL_DIR/watch_mlx_v2.sh"
echo "Copied watcher + binary + metallib to $INSTALL_DIR (outside ProtonDrive)"

mkdir -p "$HOME/Library/LaunchAgents"
sed -e "s|__REPO__|$INSTALL_DIR|g" -e "s|__BIN__|$INSTALL_DIR/c2g-mlx|g" "$TEMPLATE" > "$DEST"
echo "Wrote $DEST"

# Idempotent: bootout first (no-op if not loaded), then bootstrap fresh.
launchctl bootout "$SERVICE_TARGET" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$DEST"
launchctl enable "$SERVICE_TARGET"

echo "Installed and started $LABEL"
echo "Check status:  launchctl print $SERVICE_TARGET | head -20"
echo "Logs:          $INSTALL_DIR/.launchd-watcher.out.log"
echo "Uninstall:     $REPO_DIR/mlx_poc/uninstall_launchd_dev.sh"
