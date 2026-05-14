#!/usr/bin/env bash
# Look up a file (folder, workbook, dataset, datamodel) by its url-id slug.
# Usage:  scripts/api/find-file-by-urlid.sh <urlId>
# Output: JSON metadata for the match, or "null" if not found.
# Env:    self-bootstrapped via _env.sh (loads .env, caches OAuth token)
set -euo pipefail
source "$(dirname "$0")/_env.sh"

if [ "$#" -ne 1 ]; then
  echo "usage: find-file-by-urlid.sh <urlId>" >&2
  exit 2
fi

python3 - "$SIGMA_BASE_URL" "$SIGMA_API_TOKEN" "$1" <<'PY'
import json, sys, urllib.parse, urllib.request

base, tok, target = sys.argv[1], sys.argv[2], sys.argv[3]
page = None
while True:
    qs = {"limit": "1000"}
    if page: qs["page"] = page
    req = urllib.request.Request(
        f"{base}/v2/files?" + urllib.parse.urlencode(qs),
        headers={"Authorization": f"Bearer {tok}"})
    d = json.load(urllib.request.urlopen(req))
    for e in d.get("entries", []):
        if e.get("urlId") == target:
            json.dump(e, sys.stdout, indent=2); print()
            sys.exit(0)
    page = d.get("nextPage")
    if not page: break
print("null")
PY
