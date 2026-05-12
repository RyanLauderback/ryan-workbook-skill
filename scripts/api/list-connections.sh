#!/usr/bin/env bash
# List warehouse connections in the org.
# Usage:  scripts/api/list-connections.sh
# Output: JSON array [{connectionId, name, type}]
# Env:    SIGMA_BASE_URL, SIGMA_API_TOKEN
set -euo pipefail

: "${SIGMA_BASE_URL:?run scripts/load-env.sh first}"
: "${SIGMA_API_TOKEN:?run get-token.sh from the sigma-api skill first}"

curl -fsS -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  "$SIGMA_BASE_URL/v2/connections?limit=200" \
  | python3 -c '
import sys, json
d = json.load(sys.stdin)
out = [{"connectionId": e.get("connectionId"), "name": e.get("name"), "type": e.get("type")}
       for e in d.get("entries", [])]
json.dump(out, sys.stdout, indent=2)
print()
'
