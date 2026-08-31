#!/usr/bin/env bash
# Look up a fully-qualified path under a connection.
# Usage:  scripts/api/lookup-path.sh <connectionId> <path1> <path2> [<path3>]
# Output: JSON {kind, inodeId, url, path} on success, {error, code, message} on 4xx.
# Env:    self-bootstrapped via _env.sh (uses already-exported creds, caches OAuth token)
set -euo pipefail
source "$(dirname "$0")/_env.sh"

if [ "$#" -lt 3 ] || [ "$#" -gt 4 ]; then
  echo "usage: lookup-path.sh <connectionId> <path1> <path2> [<path3>]" >&2
  exit 2
fi

CONN="$1"; shift
PATH_JSON=$("$SIGMA_PYTHON" -c "import json,sys; print(json.dumps(sys.argv[1:]))" "$@")

# mktemp with an explicit template + a trap, not a predictable fixed-prefix
# name in a world-writable dir — the old `/tmp/.lookup-path.$$` was both
# guessable (PIDs collide across containers/PID namespaces) and
# symlink-followable via `curl -o`.
tmp_body="$(mktemp "${TMPDIR:-/tmp}/lookup-path.XXXXXX")"
trap 'rm -f "$tmp_body"' EXIT

HTTP_CODE=$(curl -sS -o "$tmp_body" -w "%{http_code}" \
  -X POST -H "Authorization: Bearer $SIGMA_API_TOKEN" -H "Content-Type: application/json" \
  "$SIGMA_BASE_URL/v2/connection/$CONN/lookup" -d "{\"path\":$PATH_JSON}") || {
  # curl itself failed (DNS/connection/TLS — not an HTTP error status,
  # which curl -w reports with exit 0). Preserve the original behavior of
  # reporting rather than hard-crashing.
  echo '{"error": true, "code": "connection_failed", "message": "curl could not reach the Sigma API"}' >&2
  exit 1
}
BODY=$(cat "$tmp_body")

if [ "$HTTP_CODE" = "200" ]; then
  echo "$BODY" | "$SIGMA_PYTHON" -c "
import sys, json
d = json.load(sys.stdin)
out = {'kind': d.get('kind'), 'inodeId': d.get('inodeId'), 'url': d.get('url'), 'path': $PATH_JSON}
json.dump(out, sys.stdout, indent=2); print()
"
else
  echo "$BODY" | "$SIGMA_PYTHON" -c "
import sys, json
d = json.load(sys.stdin)
json.dump({'error': True, 'code': d.get('code'), 'message': d.get('message')}, sys.stdout, indent=2); print()
"
  exit 1
fi
