#!/usr/bin/env bash
# Pull the current statusline-command.sh from ~/.claude/ into this repo and push.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO_DIR"

cp "$HOME/.claude/statusline-command.sh" "$REPO_DIR/statusline-command.sh"

if git diff --quiet && git diff --cached --quiet; then
  echo "No changes."
  exit 0
fi

git add statusline-command.sh statusline.json
git commit -m "sync: update statusline from $(hostname) $(date -u +%Y-%m-%dT%H:%M:%SZ)"
git push
