#!/usr/bin/env bash
# Pull/refresh a read-only mirror of sigmacomputing/sigma-agent-skills into vendor/
# for inspection while authoring project-local skills. The mirror is gitignored;
# the upstream skills themselves are loaded via the Claude Code plugin marketplace
# (see .claude/settings.json), not from here.

set -euo pipefail

REPO_URL="https://github.com/sigmacomputing/sigma-agent-skills.git"
VENDOR_DIR="vendor/sigma-agent-skills"

if [ -d "$VENDOR_DIR/.git" ]; then
  echo "Updating $VENDOR_DIR ..."
  git -C "$VENDOR_DIR" fetch --depth=1 origin main
  git -C "$VENDOR_DIR" reset --hard origin/main
else
  echo "Cloning $REPO_URL into $VENDOR_DIR ..."
  rm -rf "$VENDOR_DIR"
  mkdir -p "$(dirname "$VENDOR_DIR")"
  git clone --depth=1 "$REPO_URL" "$VENDOR_DIR"
fi

echo "Done. Read-only mirror is at $VENDOR_DIR (gitignored)."
