#!/usr/bin/env bash
# List columns of a warehouse table by its inodeId.
# Usage:  scripts/api/list-table-columns.sh <inodeId>
# Output: JSON array [{name, type}]
# Env:    SIGMA_BASE_URL, SIGMA_API_TOKEN
set -euo pipefail

: "${SIGMA_BASE_URL:?run scripts/load-env.sh first}"
: "${SIGMA_API_TOKEN:?run get-token.sh from the sigma-api skill first}"

if [ "$#" -ne 1 ]; then
  echo "usage: list-table-columns.sh <inodeId>" >&2
  exit 2
fi

curl -fsS -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  "$SIGMA_BASE_URL/v2/connections/tables/$1/columns?pageSize=200" \
  | python3 -c '
import sys, json
d = json.load(sys.stdin)
out = [{"name": c.get("name"), "type": (c.get("type") or {}).get("type")} for c in d.get("entries", [])]
json.dump(out, sys.stdout, indent=2); print()
'
