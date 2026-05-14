#!/usr/bin/env bash
# List folders in the org, optionally filtered by case-insensitive substring of name.
# Usage:  scripts/api/list-folders.sh [name-substring]
# Output: JSON array [{id, urlId, name, path}]
# Env:    self-bootstrapped via _env.sh (loads .env, caches OAuth token)
set -euo pipefail
source "$(dirname "$0")/_env.sh"

NAME_FILTER="${1:-}"

# Paginate; Sigma returns up to 1000 per page on /v2/files.
python3 - "$SIGMA_BASE_URL" "$SIGMA_API_TOKEN" "$NAME_FILTER" <<'PY'
import json, os, sys, urllib.parse, urllib.request

base, tok, name_filter = sys.argv[1], sys.argv[2], sys.argv[3]
name_lc = name_filter.lower().strip()
out, page = [], None
while True:
    qs = {"typeFilters": "folder", "limit": "1000"}
    if page: qs["page"] = page
    req = urllib.request.Request(
        f"{base}/v2/files?" + urllib.parse.urlencode(qs),
        headers={"Authorization": f"Bearer {tok}"})
    d = json.load(urllib.request.urlopen(req))
    for e in d.get("entries", []):
        if name_lc and name_lc not in (e.get("name") or "").lower():
            continue
        out.append({k: e.get(k) for k in ("id", "urlId", "name", "path")})
    page = d.get("nextPage")
    if not page: break
json.dump(out, sys.stdout, indent=2)
print()
PY
