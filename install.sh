#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$REPO_ROOT/lib/find_x4.sh"

GAME_PATH="$(find_x4)" || {
    echo "could not find an X4: Foundations installation - set X4_PATH to point at it" >&2
    exit 1
}

[[ -d "$GAME_PATH/extensions" ]] || {
    echo "no extensions directory at $GAME_PATH/extensions" >&2
    exit 1
}

EXTENSION_ID="$(extension_id "$REPO_ROOT/extension/content.xml")"
if [[ -z "$EXTENSION_ID" ]]; then
    echo "could not read the extension id out of extension/content.xml" >&2
    exit 1
fi

TARGET="$GAME_PATH/extensions/$EXTENSION_ID"

if [[ "--uninstall" == "${1:-}" ]]; then
    rm -rf -- "$TARGET"
    echo "removed $TARGET"
    echo "restart X4 for the change to take effect"
    exit 0
fi

rm -rf -- "$TARGET"
mkdir -p -- "$TARGET"
if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete "$REPO_ROOT/extension/" "$TARGET/"
else
    cp -r -- "$REPO_ROOT/extension/." "$TARGET/"
fi

echo "installed $TARGET"
echo "restart X4 for the change to take effect"
