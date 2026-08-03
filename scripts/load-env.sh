#!/usr/bin/env bash
# Load .env into the current shell without echoing secrets.
# Usage:  eval "$(scripts/load-env.sh)"
#
# Prints `export VAR=value` lines to stdout for each non-comment, non-blank line in .env.
# Values are single-quoted so embedded spaces / special chars survive the eval.
# Errors go to stderr; exits non-zero on missing file or malformed lines.

set -euo pipefail

# ENV_FILE defaults to <repo-root>/.env, not cwd-relative .env — a bare
# ".env" only resolved when the caller's cwd happened to be the repo root.
# Any cd, git worktree, or harness that invokes this from elsewhere used to
# fail with "not found" even though .env was sitting right there. Fixed
# 2026-08-03; ENV_FILE remains a documented override for callers that want
# a different file.
_repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$_repo_root/.env}"

if [ ! -f "$ENV_FILE" ]; then
  echo "load-env.sh: $ENV_FILE not found. Copy .env.example to .env and fill in values." >&2
  exit 1
fi

while IFS= read -r line || [ -n "$line" ]; do
  # Strip a trailing \r — defense in depth against a CRLF .env (e.g. from
  # a Windows editor, or a checkout that predates .gitattributes). Without
  # this, a CR gets baked into the exported value, e.g. a base URL ending
  # in "\r" that then shows up as a malformed Authorization header.
  line="${line%$'\r'}"
  # strip leading whitespace
  line="${line#"${line%%[![:space:]]*}"}"
  # skip comments and blanks
  [ -z "$line" ] && continue
  case "$line" in \#*) continue ;; esac

  # require KEY=VALUE
  if ! printf '%s' "$line" | grep -qE '^[A-Za-z_][A-Za-z0-9_]*='; then
    echo "load-env.sh: skipping malformed line: $line" >&2
    continue
  fi

  key="${line%%=*}"
  value="${line#*=}"
  # strip surrounding quotes if present
  case "$value" in
    \"*\") value="${value%\"}"; value="${value#\"}" ;;
    \'*\') value="${value%\'}"; value="${value#\'}" ;;
  esac
  # single-quote for safe eval; escape any embedded single quotes
  escaped="$(printf '%s' "$value" | sed "s/'/'\\\\''/g")"
  printf "export %s='%s'\n" "$key" "$escaped"
done < "$ENV_FILE"
