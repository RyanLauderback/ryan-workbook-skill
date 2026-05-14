#!/usr/bin/env bash
# Self-bootstrap for scripts in scripts/api/. Sourced (not executed).
#
# After sourcing, these vars are set in the calling script's shell:
#   SIGMA_BASE_URL   from .env
#   SIGMA_API_TOKEN  cached on disk (/tmp/.sigma_token, mode 0600), refreshed
#                    when older than 55 min, fetched fresh via the sigma-api
#                    skill's get-token.sh on first call of a session.
#
# Override the token-fetcher path via $SIGMA_TOKEN_FETCHER if your install
# differs from the marketplace plugin default.
#
# Usage from a script in scripts/api/:
#   set -euo pipefail
#   source "$(dirname "$0")/_env.sh"
#   # SIGMA_BASE_URL and SIGMA_API_TOKEN are now set.

# Don't impose `set -euo pipefail` here — inherit the caller's shell options.

_sigma_repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
_sigma_token_cache="/tmp/.sigma_token"
_sigma_token_ttl=$((55 * 60))   # refresh 5 min before the 60-min OAuth expiry

# 1. Load .env if the relevant vars aren't already exported.
if [ -z "${SIGMA_BASE_URL:-}" ] || [ -z "${SIGMA_CLIENT_ID:-}" ] || [ -z "${SIGMA_CLIENT_SECRET:-}" ]; then
  eval "$("${_sigma_repo_root}/scripts/load-env.sh")"
fi

# 2. Resolve SIGMA_API_TOKEN via cache → fresh fetch.
if [ -z "${SIGMA_API_TOKEN:-}" ]; then
  _fresh=false
  if [ -f "$_sigma_token_cache" ]; then
    # macOS: stat -f %m   |   Linux: stat -c %Y
    _mtime=$(stat -f %m "$_sigma_token_cache" 2>/dev/null \
          || stat -c %Y "$_sigma_token_cache" 2>/dev/null \
          || echo 0)
    _age=$(( $(date +%s) - _mtime ))
    if [ "$_age" -lt "$_sigma_token_ttl" ]; then
      _fresh=true
    fi
  fi

  if $_fresh; then
    SIGMA_API_TOKEN=$(cat "$_sigma_token_cache")
  else
    _gettoken="${SIGMA_TOKEN_FETCHER:-$HOME/.claude/plugins/marketplaces/sigma-computing/skills/sigma-api/scripts/get-token.sh}"
    if [ ! -f "$_gettoken" ]; then
      echo "_env.sh: get-token.sh not found at $_gettoken." >&2
      echo "  Set SIGMA_TOKEN_FETCHER to the correct path." >&2
      return 1 2>/dev/null || exit 1
    fi
    # get-token.sh prints `export SIGMA_API_TOKEN=...` on stdout for eval.
    eval "$(bash "$_gettoken")"
    if [ -z "${SIGMA_API_TOKEN:-}" ]; then
      echo "_env.sh: token fetch returned empty." >&2
      return 1 2>/dev/null || exit 1
    fi
    # Cache for subsequent invocations in this session (mode 0600).
    ( umask 077 && printf '%s' "$SIGMA_API_TOKEN" > "$_sigma_token_cache" )
  fi
fi

export SIGMA_BASE_URL SIGMA_API_TOKEN

unset _sigma_repo_root _sigma_token_cache _sigma_token_ttl _fresh _mtime _age _gettoken
