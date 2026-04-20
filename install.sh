#!/usr/bin/env bash
# Install / update the Claude Code statusline on this machine.
# Merges statusline.json into ~/.claude/settings.json without touching other keys.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
SETTINGS="$CLAUDE_DIR/settings.json"

command -v jq >/dev/null || { echo "jq is required (brew install jq / pacman -S jq)"; exit 1; }

mkdir -p "$CLAUDE_DIR"
cp "$REPO_DIR/statusline-command.sh" "$CLAUDE_DIR/statusline-command.sh"
chmod +x "$CLAUDE_DIR/statusline-command.sh"

if [ ! -f "$SETTINGS" ]; then
  echo '{}' > "$SETTINGS"
fi

cp "$SETTINGS" "$SETTINGS.bak.$(date +%Y%m%d%H%M%S)"

tmp="$(mktemp)"
jq -s '.[0] * .[1]' "$SETTINGS" "$REPO_DIR/statusline.json" > "$tmp"
mv "$tmp" "$SETTINGS"

echo "Installed. Statusline merged into $SETTINGS (backup saved alongside)."
