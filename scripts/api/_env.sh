#!/usr/bin/env bash
# Self-bootstrap for scripts in scripts/api/. Sourced (not executed).
#
# After sourcing, these vars are set in the calling script's shell:
#   SIGMA_BASE_URL   already-exported before this file is sourced —
#                    browser-login.sh/refresh-token.sh set it alongside
#                    SIGMA_API_TOKEN; Claude Code web injects it directly.
#                    No file is ever read.
#   SIGMA_API_TOKEN  cached on disk at $SIGMA_TOKEN_CACHE (per-user path under
#                    XDG_RUNTIME_DIR/TMPDIR, mode 0600), refreshed when older
#                    than 55 min, fetched fresh via the repo-local
#                    scripts/api/get-token.sh on first call of a session.
#
# Override the token-fetcher path via $SIGMA_TOKEN_FETCHER if you want to use
# the upstream sigma-api plugin's get-token.sh or a custom fetcher instead.
# Override the cache path via $SIGMA_TOKEN_CACHE if needed.
#
# Usage from a script in scripts/api/:
#   set -euo pipefail
#   source "$(dirname "$0")/_env.sh"
#   # SIGMA_BASE_URL and SIGMA_API_TOKEN are now set.

# Don't impose `set -euo pipefail` here — inherit the caller's shell options.

# BASH_SOURCE[0] is empty when this file is sourced from a non-bash shell
# (e.g. zsh, the macOS/many-Linux-distro default login shell) rather than
# from inside a bash script/`bash -c`. dirname of an empty string silently
# resolves to ".", turning the "../.." below into a walk from the *caller's
# cwd* instead of this file's location — landing on a wrong-but-plausible
# repo root 2 directories shallower, with get-token.sh then failing on a
# garbled path instead of a clear error. Fail loudly here instead.
if [ -z "${BASH_SOURCE[0]:-}" ]; then
  echo "_env.sh: \$BASH_SOURCE is unset — this file must be sourced from" >&2
  echo "  bash, not zsh/sh/dash. Run the wrapping script via 'bash scripts/api/<name>.sh'," >&2
  echo "  or if sourcing _env.sh directly (e.g. for its sigma_curl helper)," >&2
  echo "  do so from inside a bash shell: bash -c 'source scripts/api/_env.sh; ...'" >&2
  return 1 2>/dev/null || exit 1
fi

_sigma_repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# SIGMA_ENV_SH: absolute path to this file, exported so sigma_curl's 401
# self-heal (below) can re-source it even when the function itself was
# inherited via `export -f` into a child bash with no BASH_SOURCE of its own.
SIGMA_ENV_SH="${BASH_SOURCE[0]}"
export SIGMA_ENV_SH

# Preflight: every scripts/api/*.sh needs curl + python3. Failing here with
# a clear message beats a bare "command not found" three calls deep, and
# is the first thing worth checking on an unfamiliar/minimal host.
for _sigma_bin in curl python3; do
  if ! command -v "$_sigma_bin" >/dev/null 2>&1; then
    echo "_env.sh: required binary '$_sigma_bin' not found on PATH." >&2
    return 1 2>/dev/null || exit 1
  fi
done
unset _sigma_bin

# SIGMA_PYTHON: resolved once here so a future portability pass (native
# Windows, where the interpreter is `python`/`py -3`, not `python3`) is a
# find-replace across scripts/ rather than a design change. Not yet
# threaded through call sites — this repo currently targets macOS/Linux/WSL,
# where `python3` is always present.
SIGMA_PYTHON="${SIGMA_PYTHON:-$(command -v python3 || command -v python)}"
export SIGMA_PYTHON

# Token cache: per-user, not a fixed world-guessable /tmp path. A shared
# /tmp/.sigma_token on a multi-user host or container risks cross-UID EACCES
# (umask only governs *creation*, not an existing file's mode) or a
# pre-planted symlink redirecting the token. XDG_RUNTIME_DIR is preferred
# when set (already per-user by convention); TMPDIR/`/tmp` + uid as fallback.
SIGMA_TOKEN_CACHE="${SIGMA_TOKEN_CACHE:-${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/.sigma_token.$(id -u)}"
export SIGMA_TOKEN_CACHE
_sigma_token_ttl=$((55 * 60))   # refresh 5 min before the 60-min OAuth expiry

# 1. Require a usable auth source. Nothing here reads from disk — there is
# no .env file. Either:
#   - SIGMA_API_TOKEN is already exported (browser-login.sh, refresh-token.sh,
#     or set some other way) — just require SIGMA_BASE_URL too, and move on; or
#   - SIGMA_CLIENT_ID/SIGMA_CLIENT_SECRET/SIGMA_BASE_URL are already exported
#     (Claude Code web: the platform injects these directly, no human, no
#     browser to redirect to in that execution context) — fall through to
#     step 2 below, which calls get-token.sh exactly as before; or
#   - neither — fail with a clear pointer to browser-login.sh.
if [ -n "${SIGMA_API_TOKEN:-}" ]; then
  # SIGMA_BASE_URL is still required either way — every scripts/api/*.sh call
  # builds its request URL from it, token source notwithstanding.
  : "${SIGMA_BASE_URL:?SIGMA_BASE_URL not set (required even with a pre-exported SIGMA_API_TOKEN)}"
elif [ -n "${SIGMA_CLIENT_ID:-}" ] && [ -n "${SIGMA_CLIENT_SECRET:-}" ] && [ -n "${SIGMA_BASE_URL:-}" ]; then
  : # Claude Code web (or any shell with client_credentials vars already
    # exported) — step 2 below mints a token via get-token.sh.
else
  echo "_env.sh: no usable auth found." >&2
  echo "  Run: eval \"\$(scripts/api/browser-login.sh)\" to sign in via browser" >&2
  echo "  (no admin-provisioned credential needed)." >&2
  return 1 2>/dev/null || exit 1
fi

# 2. Resolve SIGMA_API_TOKEN via cache → fresh fetch.
if [ -z "${SIGMA_API_TOKEN:-}" ]; then
  _fresh=false
  if [ -f "$SIGMA_TOKEN_CACHE" ]; then
    # Linux: stat -c %Y   |   macOS/BSD: stat -f %m
    # Order matters: on Linux, `stat -f` prints a filesystem report to
    # *stdout* (not stderr), so trying the BSD form first silently
    # "succeeds" with garbage. `stat -c` is a hard error on BSD, so this
    # order fails cleanly to the fallback on macOS.
    _mtime=$(stat -c %Y "$SIGMA_TOKEN_CACHE" 2>/dev/null \
          || stat -f %m "$SIGMA_TOKEN_CACHE" 2>/dev/null \
          || echo 0)
    [ -z "${_mtime:-}" ] && _mtime=0
    _age=$(( $(date +%s) - _mtime ))
    if [ "$_age" -lt "$_sigma_token_ttl" ]; then
      _fresh=true
    fi
  fi

  if $_fresh; then
    SIGMA_API_TOKEN=$(cat "$SIGMA_TOKEN_CACHE")
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
    # Cache for subsequent invocations in this session. Create with 0600
    # up front (umask only affects creation, not an existing file's mode).
    ( umask 077 && : > "$SIGMA_TOKEN_CACHE" && chmod 600 "$SIGMA_TOKEN_CACHE" )
    printf '%s' "$SIGMA_API_TOKEN" > "$SIGMA_TOKEN_CACHE"
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
# revoked or wrong-base-URL token in the cache would silently fail.
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
      rm -f "$SIGMA_TOKEN_CACHE"
      unset SIGMA_API_TOKEN
      # Use $SIGMA_ENV_SH, not $BASH_SOURCE[0] — this function may have
      # been inherited via `export -f` into a child bash with no source
      # file of its own, in which case BASH_SOURCE[0] here would not be
      # this file's path.
      source "$SIGMA_ENV_SH"
      _retries=1
      continue
    fi
    printf '%s' "$_body"
    [ "$_status" -lt 400 ] && return 0 || return 1
  done
}
export -f sigma_curl

unset _sigma_repo_root _sigma_token_ttl _fresh _mtime _age _gettoken
# SIGMA_ENV_SH and SIGMA_TOKEN_CACHE stay exported — sigma_curl's 401
# self-heal and any child script need both.
