#!/usr/bin/env bash
# Look up a file (folder, workbook, dataset, datamodel) by its url-id slug.
# Usage:  scripts/api/find-file-by-urlid.sh <urlId-or-full-workbook-url>
# Output: JSON metadata for the match, or "null" if not found.
# Env:    self-bootstrapped via _env.sh (loads .env, caches OAuth token)
#
# Accepts a bare urlId, a full pasted Sigma URL, or a bare "pretty slug"
# path segment. The API's own urlId (confirmed via a live /v2/files
# lookup, 2026-08-04) is only the short trailing token (e.g.
# "3R528WqcM6uEqxWIaJe6sN"), but Sigma's browser address bar shows a
# human-readable slug prepended to that same token (e.g.
# "Marketing-Control-Center-Analytics-and-Application-vREL-3R528WqcM6uEqxWIaJe6sN")
# -- exactly the kind of link a user pastes. Previously the entire pasted
# string was compared against each entry's urlId verbatim, so both the
# full-URL and bare-pretty-slug cases matched nothing. Found 2026-08-03
# via a real build-mode session where the user pasted a full workbook
# URL; root-caused 2026-08-04. Fix: take the last path segment (if a
# URL), then split off everything before the last hyphen -- a genuine
# bare urlId has no hyphens, so this is a no-op for that case.
set -euo pipefail
source "$(dirname "$0")/_env.sh"

if [ "$#" -ne 1 ]; then
  echo "usage: find-file-by-urlid.sh <urlId-or-full-workbook-url>" >&2
  exit 2
fi

python3 - "$SIGMA_BASE_URL" "$SIGMA_API_TOKEN" "$1" <<'PY'
import json, sys, urllib.parse, urllib.request

base, tok, target = sys.argv[1], sys.argv[2], sys.argv[3]
if target.startswith("http://") or target.startswith("https://"):
    target = urllib.parse.urlparse(target).path
target = target.rstrip("/").rsplit("/", 1)[-1].rsplit("-", 1)[-1]
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
