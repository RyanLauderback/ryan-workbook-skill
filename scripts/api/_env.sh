#!/usr/bin/env bash
# Self-bootstrap for scripts in scripts/api/. Sourced (not executed).
#
# After sourcing, these vars are set in the calling script's shell:
#   SIGMA_BASE_URL   from .env (or already-exported env vars — Claude Code web)
#   SIGMA_API_TOKEN  cached on disk (/tmp/.sigma_token, mode 0600), refreshed
#                    when older than 55 min, fetched fresh via the repo-local
#                    scripts/api/get-token.sh on first call of a session.
#
# Override the token-fetcher path via $SIGMA_TOKEN_FETCHER if you want to use
# the upstream sigma-api plugin's get-token.sh or a custom fetcher instead.
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
    # Linux: stat -c %Y   |   macOS/BSD: stat -f %m
    # Order matters: on Linux, `stat -f` prints a filesystem report to
    # *stdout* (not stderr), so trying the BSD form first silently
    # "succeeds" with garbage. `stat -c` is a hard error on BSD, so this
    # order fails cleanly to the fallback on macOS.
    _mtime=$(stat -c %Y "$_sigma_token_cache" 2>/dev/null \
          || stat -f %m "$_sigma_token_cache" 2>/dev/null \
          || echo 0)
    [ -z "${_mtime:-}" ] && _mtime=0
    _age=$(( $(date +%s) - _mtime ))
    if [ "$_age" -lt "$_sigma_token_ttl" ]; then
      _fresh=true
    fi
  fi

  if $_fresh; then
    SIGMA_API_TOKEN=$(cat "$_sigma_token_cache")
  else
    # Skill owns auth: default to the repo-local fetcher (present in every
    # checkout / zip, in CLI and web alike). $SIGMA_TOKEN_FETCHER overrides
    # for anyone who prefers the upstream sigma-api plugin's get-token.sh.
    _gettoken="${SIGMA_TOKEN_FETCHER:-$_sigma_repo_root/scripts/api/get-token.sh}"
    if [ ! -f "$_gettoken" ]; then
      echo "_env.sh: token fetcher not found at $_gettoken." >&2
      echo "  Expected scripts/api/get-token.sh in the repo, or set SIGMA_TOKEN_FETCHER." >&2
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

# sigma_curl — wrap curl with auth header, Accept: application/json, and 401
# auto-retry. Use this from scripts/api/*.sh instead of raw curl for any call
# to the Sigma REST API.
#
# Usage:  sigma_curl [curl args...] <url>
# Output: response body to stdout (HTTP status suffix stripped).
# Exit:   0 if HTTP < 400, 1 otherwise.
#
# On HTTP 401, evicts the cached token, re-bootstraps _env.sh to fetch fresh,
# and retries the call once. Eliminates the stale-cache footgun where a
# revoked or wrong-base-URL token in /tmp/.sigma_token would silently fail.
sigma_curl() {
  local _resp _body _status _retries=0
  while :; do
    _resp=$(curl -sS \
      -H "Authorization: Bearer $SIGMA_API_TOKEN" \
      -H "Accept: application/json" \
      -w '\nHTTP_STATUS:%{http_code}' \
      "$@")
    _status="${_resp##*HTTP_STATUS:}"
    _body="${_resp%HTTP_STATUS:*}"
    _body="${_body%$'\n'}"
    if [ "$_status" = "401" ] && [ "$_retries" -eq 0 ]; then
      rm -f /tmp/.sigma_token
      unset SIGMA_API_TOKEN
      source "${BASH_SOURCE[0]}"
      _retries=1
      continue
    fi
    printf '%s' "$_body"
    [ "$_status" -lt 400 ] && return 0 || return 1
  done
}
export -f sigma_curl

unset _sigma_repo_root _sigma_token_cache _sigma_token_ttl _fresh _mtime _age _gettoken
