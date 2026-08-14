#!/usr/bin/env bash
# Local OAuth token fetcher — the skill's own auth path. Works whether the
# SIGMA_* credentials arrive as exported env vars (Claude Code web) or from
# .env (CLI/local). Prints `export SIGMA_API_TOKEN=...` on stdout for eval,
# matching the contract _env.sh expects.
#
# Requires SIGMA_BASE_URL, SIGMA_CLIENT_ID, SIGMA_CLIENT_SECRET in the env
# (exported by the environment, or loaded from .env by load-env.sh).
set -euo pipefail

if [ -z "${SIGMA_BASE_URL:-}" ] || [ -z "${SIGMA_CLIENT_ID:-}" ] || [ -z "${SIGMA_CLIENT_SECRET:-}" ]; then
  _root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  if [ -f "$_root/.env" ]; then
    eval "$("$_root/scripts/load-env.sh")"
  fi
fi

: "${SIGMA_BASE_URL:?SIGMA_BASE_URL not set}"
: "${SIGMA_CLIENT_ID:?SIGMA_CLIENT_ID not set}"
: "${SIGMA_CLIENT_SECRET:?SIGMA_CLIENT_SECRET not set}"

_token=$(curl -sS -X POST "$SIGMA_BASE_URL/v2/auth/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "grant_type=client_credentials" \
  --data-urlencode "client_id=$SIGMA_CLIENT_ID" \
  --data-urlencode "client_secret=$SIGMA_CLIENT_SECRET" \
  | python3 -c 'import sys,json; print(json.load(sys.stdin).get("access_token",""))')

if [ -z "$_token" ]; then
  echo "get-token.sh: token exchange returned empty (check credentials / SIGMA_BASE_URL region)." >&2
  exit 1
fi

printf 'export SIGMA_API_TOKEN=%s\n' "$_token"
