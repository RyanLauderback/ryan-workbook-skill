#!/usr/bin/env bash
# Look up a fully-qualified path under a connection.
# Usage:  scripts/api/lookup-path.sh <connectionId> <path1> <path2> [<path3>]
# Output: JSON {kind, inodeId, url, path} on success, {error, code, message} on 4xx.
# Env:    self-bootstrapped via _env.sh (loads .env, caches OAuth token)
set -euo pipefail
source "$(dirname "$0")/_env.sh"

if [ "$#" -lt 3 ] || [ "$#" -gt 4 ]; then
  echo "usage: lookup-path.sh <connectionId> <path1> <path2> [<path3>]" >&2
  exit 2
fi

CONN="$1"; shift
PATH_JSON=$(python3 -c "import json,sys; print(json.dumps(sys.argv[1:]))" "$@")

HTTP_CODE=0
RESP=$(curl -sS -o /tmp/.lookup-path.$$ -w "%{http_code}" \
  -X POST -H "Authorization: Bearer $SIGMA_API_TOKEN" -H "Content-Type: application/json" \
  "$SIGMA_BASE_URL/v2/connection/$CONN/lookup" -d "{\"path\":$PATH_JSON}") || HTTP_CODE=$?
BODY=$(cat /tmp/.lookup-path.$$); rm -f /tmp/.lookup-path.$$
HTTP_CODE="$RESP"

if [ "$HTTP_CODE" = "200" ]; then
  echo "$BODY" | python3 -c "
import sys, json
d = json.load(sys.stdin)
out = {'kind': d.get('kind'), 'inodeId': d.get('inodeId'), 'url': d.get('url'), 'path': $PATH_JSON}
json.dump(out, sys.stdout, indent=2); print()
"
else
  echo "$BODY" | python3 -c "
import sys, json
d = json.load(sys.stdin)
json.dump({'error': True, 'code': d.get('code'), 'message': d.get('message')}, sys.stdout, indent=2); print()
"
  exit 1
fi
