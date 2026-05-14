#!/usr/bin/env bash
# List warehouse connections in the org.
# Usage:  scripts/api/list-connections.sh
# Output: JSON array [{connectionId, name, type}]
# Env:    self-bootstrapped via _env.sh (loads .env, caches OAuth token)
set -euo pipefail
source "$(dirname "$0")/_env.sh"

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
