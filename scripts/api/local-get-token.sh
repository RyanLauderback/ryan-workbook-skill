#!/usr/bin/env bash
# Environment-local OAuth token fetcher for Claude Code cloud sessions.
#
# WHY THIS EXISTS
#   The canonical auth path (_env.sh) shells out to the `sigma-api` marketplace
#   plugin's get-token.sh. That plugin is NOT cloned into the cloud execution
#   container, so the default fetcher path does not exist here. This script is
#   a drop-in replacement wired via SIGMA_TOKEN_FETCHER (see .claude/settings.json
#   env block) so every scripts/api/*.sh call self-bootstraps auth in the cloud
#   the same way it does on a local install.
#
# CONTRACT (must match what _env.sh expects)
#   - Reads SIGMA_BASE_URL, SIGMA_CLIENT_ID, SIGMA_CLIENT_SECRET from the env.
#     In the cloud environment these are provisioned as environment variables;
#     no .env file is required.
#   - Performs the client-credentials grant against /v2/auth/token.
#   - Prints exactly `export SIGMA_API_TOKEN=<token>` on stdout for eval.
#   - Never echoes the client secret or the token to stderr.
#
# Naming: `local-` prefix per the repo convention for environment-local,
# opt-in additions (see CLAUDE.md / SKILL.md "session-local enrichment").
set -euo pipefail

: "${SIGMA_BASE_URL:?local-get-token.sh: SIGMA_BASE_URL not set}"
: "${SIGMA_CLIENT_ID:?local-get-token.sh: SIGMA_CLIENT_ID not set}"
: "${SIGMA_CLIENT_SECRET:?local-get-token.sh: SIGMA_CLIENT_SECRET not set}"

_resp=$(curl -sS -w '\nHTTP_STATUS:%{http_code}' \
  -X POST "$SIGMA_BASE_URL/v2/auth/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "grant_type=client_credentials" \
  --data-urlencode "client_id=$SIGMA_CLIENT_ID" \
  --data-urlencode "client_secret=$SIGMA_CLIENT_SECRET")

_status="${_resp##*HTTP_STATUS:}"
_body="${_resp%HTTP_STATUS:*}"
_body="${_body%$'\n'}"

if [ "$_status" != "200" ]; then
  echo "local-get-token.sh: token endpoint returned HTTP $_status." >&2
  echo "  Check SIGMA_BASE_URL region and client credentials." >&2
  exit 1
fi

_token=$(printf '%s' "$_body" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("access_token",""))')
if [ -z "$_token" ]; then
  echo "local-get-token.sh: no access_token in token response." >&2
  exit 1
fi

printf 'export SIGMA_API_TOKEN=%s\n' "$_token"
