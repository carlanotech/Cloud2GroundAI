#!/usr/bin/env bash
# Stop and remove the dev-only MLX watcher LaunchAgent installed by
# install_launchd_dev.sh.
set -euo pipefail

LABEL="com.cloud2ground.mlx-watcher-dev"
DEST="$HOME/Library/LaunchAgents/$LABEL.plist"
SERVICE_TARGET="gui/$(id -u)/$LABEL"

# Service-scoped bootout only — never the bare gui/<uid> domain (that logs
# the user out). Safe to call if nothing is loaded.
launchctl bootout "$SERVICE_TARGET" 2>/dev/null || true

if [ -f "$DEST" ]; then
    rm -f "$DEST"
    echo "Removed $DEST"
else
    echo "Nothing installed at $DEST"
fi

echo "Uninstalled $LABEL"
