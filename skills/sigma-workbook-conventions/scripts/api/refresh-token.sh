#!/usr/bin/env bash
# Headless access-token refresh for the browser-login flow.
#
# Ported from Sigma's reference sigma-api skill and adapted to this repo's
# conventions. After scripts/api/browser-login.sh has run once (storing the
# refresh token, client_id, and token endpoint via _state.sh's cred_set --
# the OS keychain where one exists, a 0600 state file otherwise, e.g. under
# Claude Cowork -- see reference/workflows/cowork.md), this mints a valid
# access token with NO browser round-trip:
#   1. If a cached access token is still valid, emit it (no network call).
#   2. Otherwise redeem the stored refresh token, cache the new access token and
#      its expiry, rotate the stored refresh token if the server returns a new
#      one, and emit it.
#
# Prints (stdout, meant to be eval'd):
#   export SIGMA_API_TOKEN=<token>
# Progress/errors go to stderr, so `eval "$(refresh-token.sh)"` works.
#
# Usage:
#   eval "$(scripts/api/refresh-token.sh)"
#
# Point scripts/api/_env.sh's cache-miss path at this script (instead of
# get-token.sh's client_credentials exchange) by exporting:
#   export SIGMA_TOKEN_FETCHER=$PWD/scripts/api/refresh-token.sh
# so every scripts/api/*.sh call redeems the stored browser-login session
# automatically instead of trying (and failing, with no client_id/secret set)
# the client_credentials flow.

set -euo pipefail

for bin in curl jq; do
  command -v "$bin" >/dev/null 2>&1 || { echo "Error: $bin is required" >&2; exit 1; }
done

log() { printf '%s\n' "$*" >&2; }

# --- Credential access via the shared 3-tier accessor (macOS keychain /
# --- libsecret / a 0600 file under $SIGMA_STATE_DIR — see _state.sh for why
# --- the third tier exists). Resolved relative to this script's own
# --- location so it works regardless of the caller's cwd.
source "$(dirname "${BASH_SOURCE[0]}")/_state.sh"

emit() { # validate against the RFC 6750 bearer alphabet before it is eval'd, then print
  local t="$1"
  if ! [[ "$t" =~ ^[A-Za-z0-9._~+/=-]+$ ]]; then
    echo "Error: token contains unexpected characters; refusing to emit." >&2
    exit 1
  fi
  printf 'export SIGMA_API_TOKEN=%q\n' "$t"
}

NOW=$(date +%s)

# --- 1. Serve a still-valid cached access token without touching the network. ---
CACHED=$(cred_get access-token)
EXPIRY=$(cred_get access-expiry)
if [ -n "$CACHED" ] && [ -n "$EXPIRY" ] && [ "$EXPIRY" -gt "$NOW" ] 2>/dev/null; then
  log "Using cached access token ($(( EXPIRY - NOW ))s remaining)."
  emit "$CACHED"
  exit 0
fi

# --- 2. Cache miss/expired -> redeem the stored refresh token. ---
REFRESH=$(cred_get refresh-token)
CLIENT_ID=$(cred_get client-id)
TOKEN_URL=$(cred_get token-url)
if [ -z "$REFRESH" ] || [ -z "$CLIENT_ID" ] || [ -z "$TOKEN_URL" ]; then
  echo "Error: no saved browser-login credentials (checked: $(cred_tier_label)). Run scripts/api/browser-login.sh first." >&2
  exit 1
fi

# Never POST the refresh token anywhere but a Sigma host, even if the keychain
# value was tampered with. Parse the authority exactly as curl would (stop at the
# first '/', '?', or '#'; drop userinfo and port) so a value like
# https://evil.com#.sigmacomputing.com can't sneak past the glob below.
TU_HOST=$(printf '%s' "$TOKEN_URL" | sed -E 's#^https?://##; s#[/?#].*##; s#^[^@]*@##; s#:[0-9]+$##')
case "$TU_HOST" in
  *.sigmacomputing.com|sigmacomputing.com) ;;
  *) echo "Error: stored token-url points at a non-Sigma host ($TU_HOST); refusing to use it." >&2; exit 1 ;;
esac

RESP=$(curl -sS -X POST "$TOKEN_URL" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "grant_type=refresh_token" \
  --data-urlencode "refresh_token=$REFRESH" \
  --data-urlencode "client_id=$CLIENT_ID")

ACCESS=$(printf '%s' "$RESP" | jq -r '.access_token // empty')
if [ -z "$ACCESS" ]; then
  echo "Error: refresh failed (the saved refresh token may be revoked or expired -- re-run scripts/api/browser-login.sh):" >&2
  printf '%s\n' "$RESP" | jq . >&2 2>/dev/null || printf '%s\n' "$RESP" >&2
  exit 1
fi

EXPIRES_IN=$(printf '%s' "$RESP" | jq -r '.expires_in // 3600')
case "$EXPIRES_IN" in ''|*[!0-9]*) EXPIRES_IN=3600 ;; esac
# 60s safety margin so a token never expires mid-request.
cred_set access-token "$ACCESS" || true
cred_set access-expiry "$(( NOW + EXPIRES_IN - 60 ))" || true

# Refresh tokens may rotate; persist the new one so the next redeem still works.
NEW_REFRESH=$(printf '%s' "$RESP" | jq -r '.refresh_token // empty')
if [ -n "$NEW_REFRESH" ] && [ "$NEW_REFRESH" != "$REFRESH" ]; then
  cred_set refresh-token "$NEW_REFRESH" || true
  log "Rotated the stored refresh token."
fi

log "Minted a fresh access token via refresh (valid ~${EXPIRES_IN}s)."
emit "$ACCESS"
