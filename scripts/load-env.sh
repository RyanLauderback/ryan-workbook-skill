#!/usr/bin/env bash
# Load .env into the current shell without echoing secrets.
# Usage:  eval "$(scripts/load-env.sh)"
#
# Prints `export VAR=value` lines to stdout for each non-comment, non-blank line in .env.
# Values are single-quoted so embedded spaces / special chars survive the eval.
# Errors go to stderr; exits non-zero on missing file or malformed lines.

set -euo pipefail

ENV_FILE="${ENV_FILE:-.env}"

if [ ! -f "$ENV_FILE" ]; then
  echo "load-env.sh: $ENV_FILE not found. Copy .env.example to .env and fill in values." >&2
  exit 1
fi

while IFS= read -r line || [ -n "$line" ]; do
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
