#!/usr/bin/env bash
# Interactive browser login for the Sigma API (OAuth 2.1 authorization-code + PKCE).
#
# Ported from Sigma's reference sigma-api skill and adapted to this repo's
# conventions (see reference/workflows/discover.md -> "MCP status" for why
# this exists: /v2/whoami's client_credentials tokens are categorically
# rejected by /mcp/v2, but a browser-login token is accepted).
#
# Unlike get-token.sh (headless client-credentials), this signs a *human* in
# through the browser -- no pre-provisioned client_id/secret. It:
#   1. discovers the OAuth endpoints from an unauthenticated /v2/whoami 401,
#   2. registers a public client (RFC 7591),
#   3. runs the PKCE authorization-code flow, opening the system browser,
#   4. captures the redirect on a one-shot local loopback listener (falls back
#      to pasting the callback URL back if python3 isn't available, or the
#      listener times out), verifying the CSRF state,
#   5. exchanges the code, stores the refresh token in the OS keychain,
#   6. prints `export SIGMA_API_TOKEN=<token>` on stdout.
#
# Reads (env):
#   SIGMA_BASE_URL   e.g. https://aws-api.sigmacomputing.com (required) --
#                    errors with a clear message if unset.
#
# Prints (stdout, meant to be eval'd):
#   export SIGMA_API_TOKEN=<token>
# All prompts/progress go to stderr, so `eval "$(browser-login.sh)"` works.
#
# Usage:
#   eval "$(scripts/api/browser-login.sh)"
#
# Repeat sessions: once this has run once, `scripts/api/refresh-token.sh`
# mints a fresh access token from the stored refresh token with no browser
# round-trip. Point _env.sh at it via `SIGMA_TOKEN_FETCHER` if you want every
# scripts/api/*.sh call to redeem it automatically on cache miss.

set -euo pipefail

: "${SIGMA_BASE_URL:?SIGMA_BASE_URL is not set. Export it (see https://help.sigmacomputing.com/docs/region-warehouse-and-feature-support for common regional base URLs) then re-run.}"

for bin in curl jq openssl; do
  command -v "$bin" >/dev/null 2>&1 || { echo "Error: $bin is required" >&2; exit 1; }
done

log() { printf '%s\n' "$*" >&2; }

# Pin SIGMA_BASE_URL to a known Sigma cloud host. The script's stdout is eval'd,
# so a hostile discovery/token response could otherwise become RCE on the caller.
case "$SIGMA_BASE_URL" in
  https://aws-api.sigmacomputing.com|\
  https://api.us-a.aws.sigmacomputing.com|\
  https://api.ca.aws.sigmacomputing.com|\
  https://api.eu.aws.sigmacomputing.com|\
  https://api.au.aws.sigmacomputing.com|\
  https://api.uk.aws.sigmacomputing.com|\
  https://api.us.azure.sigmacomputing.com|\
  https://api.eu.azure.sigmacomputing.com|\
  https://api.ca.azure.sigmacomputing.com|\
  https://api.uk.azure.sigmacomputing.com|\
  https://api.au.azure.sigmacomputing.com|\
  https://api.sigmacomputing.com|\
  https://api.sa.gcp.sigmacomputing.com) ;;
  *) echo "Error: SIGMA_BASE_URL must be one of the published Sigma API hosts (see https://help.sigmacomputing.com/docs/region-warehouse-and-feature-support)." >&2; exit 1 ;;
esac

# Every endpoint we discover must live on a Sigma host -- never open a browser at,
# or POST credentials to, an authorization server a spoofed discovery doc names.
assert_sigma_host() {
  local url="$1" host
  # The authority ends at the first '/', '?', or '#'; strip any userinfo and port
  # so the check sees exactly the host curl will connect to. A naive "everything
  # up to the first /" parse would let https://evil.com#.sigmacomputing.com (curl
  # connects to evil.com) slip past the *.sigmacomputing.com glob.
  host=$(printf '%s' "$url" | sed -E 's#^https?://##; s#[/?#].*##; s#^[^@]*@##; s#:[0-9]+$##')
  case "$host" in
    *.sigmacomputing.com|sigmacomputing.com) ;;
    *) echo "Error: refusing OAuth endpoint on non-Sigma host: ${host:-<none>}" >&2; exit 1 ;;
  esac
}

urlenc() { jq -rn --arg v "$1" '$v|@uri'; }

# --- A. Discover the OAuth endpoints from an unauthenticated /v2/whoami 401. ---
WWW_AUTH=$(curl -sS -D - -o /dev/null "$SIGMA_BASE_URL/v2/whoami" | tr -d '\r' | grep -i '^www-authenticate:' || true)
[ -n "$WWW_AUTH" ] || { echo "Error: $SIGMA_BASE_URL/v2/whoami returned no WWW-Authenticate header; this host does not offer browser login. Use get-token.sh (client credentials)." >&2; exit 1; }

RESOURCE_META=$(printf '%s' "$WWW_AUTH" | grep -oE 'resource_metadata="[^"]+"' | cut -d'"' -f2 || true)
SCOPE=$(printf '%s' "$WWW_AUTH" | grep -oE 'scope="[^"]+"' | cut -d'"' -f2 || true)
[ -n "$RESOURCE_META" ] || { echo "Error: could not parse resource_metadata from WWW-Authenticate header." >&2; exit 1; }
[ -n "$SCOPE" ] || { echo "Error: could not parse scope from WWW-Authenticate header." >&2; exit 1; }
assert_sigma_host "$RESOURCE_META"

AUTH_SERVER=$(curl -sS "$RESOURCE_META" | jq -r '.authorization_servers[0] // empty')
[ -n "$AUTH_SERVER" ] || { echo "Error: no authorization server listed in protected-resource metadata." >&2; exit 1; }
AUTH_SERVER=${AUTH_SERVER%/}
assert_sigma_host "$AUTH_SERVER"

# --- A2. Also discover /mcp/v2's scope requirement and union it in. ---
# /v2/whoami and /mcp/v2 are DISTINCT OAuth-protected resources with
# DISTINCT scopes (confirmed live 2026-08-12: the REST API's protected-
# resource metadata advertises only scope="api:access"; /mcp/v2 has its
# own metadata document advertising scope="mcp:access" and is not listed
# anywhere under the REST resource's document). A token minted with only
# the REST scope is exactly the token /mcp/v2 rejects with `Missing
# required scopes: mcp:access` -- silently defeating the whole reason
# this script exists (unblocking /mcp/v2). /mcp/v2 only challenges on
# POST (GET returns a plain 405 with no WWW-Authenticate), so probe it
# that way. Non-fatal if this probe fails -- fall back to the REST-only
# scope and let mcp-search.sh/mcp-describe.sh surface the 403 as before.
MCP_WWW_AUTH=$(curl -sS -D - -o /dev/null -X POST "$SIGMA_BASE_URL/mcp/v2" -H 'Content-Type: application/json' -d '{}' | tr -d '\r' | grep -i '^www-authenticate:' || true)
if [ -n "$MCP_WWW_AUTH" ]; then
  MCP_SCOPE=$(printf '%s' "$MCP_WWW_AUTH" | grep -oE 'scope="[^"]+"' | cut -d'"' -f2 || true)
  if [ -n "$MCP_SCOPE" ]; then
    # Union + de-dupe (space-separated OAuth scope string), preserving order.
    SCOPE=$(printf '%s %s' "$SCOPE" "$MCP_SCOPE" | tr ' ' '\n' | awk '!seen[$0]++' | paste -sd' ' -)
  else
    log "Warning: $SIGMA_BASE_URL/mcp/v2 challenged but no scope= found; requesting REST scope only -- MCP calls may still 403."
  fi
else
  log "Warning: could not probe $SIGMA_BASE_URL/mcp/v2 for its scope requirement; requesting REST scope only -- MCP calls may still 403."
fi

META=$(curl -sS "$AUTH_SERVER/.well-known/oauth-authorization-server")
AUTHORIZE_URL=$(printf '%s' "$META" | jq -r '.authorization_endpoint // empty')
TOKEN_URL=$(printf '%s' "$META" | jq -r '.token_endpoint // empty')
REGISTER_URL=$(printf '%s' "$META" | jq -r '.registration_endpoint // empty')
for u in "$AUTHORIZE_URL" "$TOKEN_URL" "$REGISTER_URL"; do
  [ -n "$u" ] || { echo "Error: authorization-server metadata is missing an endpoint URL." >&2; exit 1; }
  assert_sigma_host "$u"
done

# --- Pick a loopback port that NOTHING is currently listening on, so the auth
# --- code is only ever delivered to the address bar -- never to a foreign local
# --- process that happens to hold the port. ---
port_is_free() {
  # Succeeds (returns 0) only when NOTHING is listening on 127.0.0.1:$1.
  # Prefer lsof (shell-independent, present on macOS/Linux); fall back to bash's
  # /dev/tcp connect. Both are used only to SKIP busy ports -- the random high
  # port below is the real guard against handing the code to a foreign process.
  if command -v lsof >/dev/null 2>&1; then
    ! lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1
  else
    ! (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null
  fi
}
REDIRECT_PORT=""
for ((i = 0; i < 50; i++)); do
  cand=$(( 20000 + (RANDOM % 20000) ))
  if port_is_free "$cand"; then REDIRECT_PORT="$cand"; break; fi
done
[ -n "$REDIRECT_PORT" ] || { echo "Error: could not find a free loopback port after 50 tries." >&2; exit 1; }
REDIRECT_URI="http://127.0.0.1:${REDIRECT_PORT}/oauth/callback"

# --- B. Register a public client (RFC 7591). ---
REG=$(curl -sS -X POST "$REGISTER_URL" \
  -H "Content-Type: application/json" \
  -d "$(jq -n --arg r "$REDIRECT_URI" --arg s "$SCOPE" '{
    redirect_uris: [$r], client_name: "ryan-workbook-skill", scope: $s,
    token_endpoint_auth_method: "none"
  }')")
CLIENT_ID=$(printf '%s' "$REG" | jq -r '.client_id // empty')
[ -n "$CLIENT_ID" ] || { echo "Error: client registration failed:" >&2; printf '%s\n' "$REG" >&2; exit 1; }

# --- C. PKCE verifier/challenge + a CSRF state. ---
VERIFIER=$(openssl rand -base64 96 | tr -d '\n=+/' | cut -c1-64)
CHALLENGE=$(printf '%s' "$VERIFIER" | openssl dgst -binary -sha256 | openssl base64 | tr '+/' '-_' | tr -d '=\n')
STATE=$(openssl rand -base64 24 | tr '+/' '-_' | tr -d '=\n')

# --- D. Authorize in the browser, capturing the redirect automatically. ---
AUTH_REQ="${AUTHORIZE_URL}?response_type=code&client_id=$(urlenc "$CLIENT_ID")&redirect_uri=$(urlenc "$REDIRECT_URI")&state=$(urlenc "$STATE")&code_challenge=${CHALLENGE}&code_challenge_method=S256&scope=$(urlenc "$SCOPE")"

# Pull code + state out of a callback URL (belt-and-suspenders for the fallback
# path below; the listener does its own parsing to build a same-origin
# response, but this is what actually feeds the token exchange). Stop at '&'
# AND '#' so a trailing fragment isn't swallowed into the value, then
# percent-decode -- the address-bar/query value is URL-encoded and curl
# --data-urlencode re-encodes on the way out, so without this a code carrying
# a %XX escape would be double-encoded and rejected.
# The pattern must be quoted -- bash parses the unquoted form `${1//%/...}` as
# the anchored-suffix substitution `${1/%.../...}` (empty pattern anchored at
# the end), which unconditionally appends the replacement instead of
# replacing every literal `%`. Verified live: unquoted, this silently
# corrupts every decoded value with a trailing NUL byte and never actually
# decodes a real %XX escape.
urldec() { printf '%b' "${1//'%'/\\x}"; }
qs_param() { printf '%s' "$1" | sed -n "s/.*[?&]$2=\([^&#]*\).*/\1/p"; }

CODE=""
RET_STATE=""
LISTENER_PID=""
LISTENER_OUT=""

open_browser() {
  log ""
  log "Opening your browser to sign in to Sigma..."
  log "If it does not open, paste this URL into a browser yourself:"
  log ""
  log "  $AUTH_REQ"
  log ""
  if command -v open >/dev/null 2>&1; then
    open "$AUTH_REQ" >/dev/null 2>&1 || true
  elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$AUTH_REQ" >/dev/null 2>&1 || true
  fi
}

# Start a one-shot local listener BEFORE opening the browser, so the redirect
# lands on it directly and the code never has to be read back from the address
# bar. Bind failure or no python3 -> CODE stays empty and we fall back below.
if command -v python3 >/dev/null 2>&1; then
  LISTENER_OUT=$(mktemp)
  python3 - "$REDIRECT_PORT" >"$LISTENER_OUT" 2>/dev/null <<'PYEOF' &
import socket, sys, time

port = int(sys.argv[1])
srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
try:
    srv.bind(("127.0.0.1", port))
    srv.listen(5)
except OSError:
    sys.exit(1)

body = b"<html><body>Signed in to Sigma \xe2\x80\x94 you can close this tab and return to the terminal.</body></html>"
resp = (
    b"HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: "
    + str(len(body)).encode()
    + b"\r\nConnection: close\r\n\r\n"
    + body
)

deadline = time.time() + 120
found = None
while time.time() < deadline:
    srv.settimeout(max(0.1, deadline - time.time()))
    try:
        conn, _ = srv.accept()
    except socket.timeout:
        break
    conn.settimeout(5)
    try:
        data = conn.recv(65536).decode("utf-8", "replace")
    except OSError:
        data = ""
    request_line = data.split("\r\n", 1)[0] if data else ""
    parts = request_line.split(" ")
    req_path = parts[1] if len(parts) > 1 else ""
    try:
        conn.sendall(resp)
    except OSError:
        pass
    conn.close()
    # Ignore stray requests (e.g. a browser's speculative /favicon.ico) --
    # keep accepting on the same listener until the real callback arrives
    # or the deadline above is hit.
    if req_path.startswith("/oauth/callback"):
        found = req_path
        break

srv.close()
if found:
    print(found)
PYEOF
  LISTENER_PID=$!

  open_browser
  log "Waiting for you to approve in the browser (up to 2 minutes)..."

  wait "$LISTENER_PID" 2>/dev/null || true
  CALLBACK_PATH=$(cat "$LISTENER_OUT" 2>/dev/null || true)
  rm -f "$LISTENER_OUT"

  if [ -n "$CALLBACK_PATH" ]; then
    CODE=$(urldec "$(qs_param "$CALLBACK_PATH" code)")
    RET_STATE=$(urldec "$(qs_param "$CALLBACK_PATH" state)")
    [ -n "$CODE" ] || log "Warning: listener caught a callback with no ?code= -- falling back to manual paste."
  else
    log "No callback arrived within 2 minutes -- falling back to manual paste."
  fi
fi

# Fallback: no python3, the listener couldn't bind, or it timed out/came back
# empty. This is the same zero-dependency path the flow always used. Only
# open the browser here if the listener path above never got a chance to
# (no python3) -- if it already opened once and just timed out waiting for
# approval, opening a second tab on the same request would just be noise.
if [ -z "$CODE" ]; then
  if [ -z "$LISTENER_PID" ]; then
    open_browser
  fi
  log "After you approve, the browser will try to load a"
  log "  http://127.0.0.1:${REDIRECT_PORT}/oauth/callback?code=...&state=..."
  log "page that fails to connect -- that is expected (nothing is listening there)."
  log "Copy the FULL address-bar URL, paste it here, and press Enter:"
  # Prefer the controlling terminal (works even under `eval "$(...)"`, where
  # stdout is captured). If there is no usable tty -- the open/read fails, e.g.
  # macOS "Device not configured" -- fall back to stdin (piped/automated callers).
  CALLBACK=""
  if ! { read -r CALLBACK < /dev/tty; } 2>/dev/null; then
    read -r CALLBACK || true
  fi
  [ -n "$CALLBACK" ] || { echo "Error: no callback URL provided." >&2; exit 1; }
  CODE=$(urldec "$(qs_param "$CALLBACK" code)")
  RET_STATE=$(urldec "$(qs_param "$CALLBACK" state)")
  [ -n "$CODE" ] || { echo "Error: no ?code= found in the pasted URL." >&2; exit 1; }
fi

[ "$RET_STATE" = "$STATE" ] || { echo "Error: state mismatch (possible CSRF) -- aborting." >&2; exit 1; }

# --- E. Exchange the authorization code for tokens. ---
TOKENS=$(curl -sS -X POST "$TOKEN_URL" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "grant_type=authorization_code" \
  --data-urlencode "code=$CODE" \
  --data-urlencode "redirect_uri=$REDIRECT_URI" \
  --data-urlencode "code_verifier=$VERIFIER" \
  --data-urlencode "client_id=$CLIENT_ID")
ACCESS=$(printf '%s' "$TOKENS" | jq -r '.access_token // empty')
REFRESH=$(printf '%s' "$TOKENS" | jq -r '.refresh_token // empty')
if [ -z "$ACCESS" ]; then
  echo "Error: token exchange failed:" >&2
  printf '%s\n' "$TOKENS" | jq . >&2 2>/dev/null || printf '%s\n' "$TOKENS" >&2
  exit 1
fi

# The token will be eval'd by the caller. Reject anything outside the RFC 6750
# bearer-token alphabet so a spoofed token endpoint cannot smuggle shell into eval.
if ! [[ "$ACCESS" =~ ^[A-Za-z0-9._~+/=-]+$ ]]; then
  echo "Error: token contains unexpected characters; refusing to emit." >&2
  exit 1
fi

# --- F. Persist the refresh token (never to a workspace file) so a later
# --- refresh needs no browser round-trip. client_id + token_url ride along so
# --- the refresh is self-contained (see scripts/api/refresh-token.sh). ---
if [ -n "$REFRESH" ]; then
  if command -v security >/dev/null 2>&1; then
    if security add-generic-password -U -a "$USER" -s "sigma-api:refresh-token" -w "$REFRESH" 2>/dev/null; then
      security add-generic-password -U -a "$USER" -s "sigma-api:client-id" -w "$CLIENT_ID" >/dev/null 2>&1 || true
      security add-generic-password -U -a "$USER" -s "sigma-api:token-url" -w "$TOKEN_URL" >/dev/null 2>&1 || true
      log "Stored refresh token in the macOS keychain (service 'sigma-api:refresh-token')."
    else
      log "Warning: could not write to the macOS keychain; refresh token NOT persisted."
    fi
  elif command -v secret-tool >/dev/null 2>&1; then
    if printf '%s' "$REFRESH" | secret-tool store --label="sigma-api refresh token" service sigma-api key refresh-token; then
      log "Stored refresh token via libsecret (service 'sigma-api', key 'refresh-token')."
    else
      log "Warning: could not write to libsecret; refresh token NOT persisted."
    fi
  else
    log "Note: no OS keychain tool (security/secret-tool) found; refresh token NOT persisted."
  fi
else
  log "Note: no refresh_token returned; sign in again when the access token expires (~1h)."
fi

printf 'export SIGMA_API_TOKEN=%q\n' "$ACCESS"
