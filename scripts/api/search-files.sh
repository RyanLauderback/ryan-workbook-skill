#!/usr/bin/env bash
# REST-only workspace search by name/topic — the fallback discovery path
# for "find X by name or topic" prompts when MCP isn't available.
#
# mcp-search.sh (Sigma's /mcp/v2 `search` tool) is semantic/fuzzy and
# richer, and is the default discovery tool under this skill's current
# browser-login.sh auth path — see reference/workflows/discover.md → "MCP
# status" for current guidance. Reach for this script when MCP isn't
# available (e.g. a client_credentials session, where Sigma's /mcp/v2 only
# accepts interactive user OAuth — confirmed by Sigma's MCP engineering
# team, see reference/history.md → "2026-08-07") or as a fallback if
# mcp-search.sh fails.
#
# Usage:
#   scripts/api/search-files.sh <query> [--types <list>] [--limit N]
#
#   <query>   Case-insensitive substring match against file name AND
#             description. Empty string matches everything (browse mode).
#   --types   Comma-separated subset of:
#             workbook, data-model, dataset, folder, report.
#             Default: workbook,data-model,dataset (skips folder/report —
#             pass --types explicitly to include them).
#   --limit   Max results returned. Default: 20.
#
# Output: JSON array of {type, id, urlId, name, description, path}.
#
# Differences from mcp-search.sh's output shape:
#   - No `url` field — /v2/files doesn't return one. Resolve a clickable
#     URL via scripts/api/find-file-by-urlid.sh <urlId> if needed.
#   - No `dataModelElement`/table results — /v2/files indexes files
#     (workbooks, data models, datasets, folders, reports), not elements
#     inside a data model or warehouse tables. For those, use
#     scripts/api/probe-schema-tables.sh / scripts/api/list-table-columns.sh,
#     or scripts/api/mcp-describe.sh datamodel <id> once you have the
#     data model's id from this search.
#   - Substring match, not semantic — "sales" won't surface a workbook
#     named "Q3 Revenue" the way MCP's fuzzy search might.
#
# Env:    self-bootstrapped via _env.sh (uses already-exported creds, caches OAuth token)
set -euo pipefail
source "$(dirname "$0")/_env.sh"

QUERY=""
QUERY_SET=false
TYPES="workbook,data-model,dataset"
LIMIT=20

while [ "$#" -gt 0 ]; do
  case "$1" in
    --types) TYPES="$2"; shift 2 ;;
    --limit) LIMIT="$2"; shift 2 ;;
    -h|--help)
      cat <<USAGE
usage: search-files.sh <query> [--types <list>] [--limit N]
  --types  comma-separated subset of: workbook, data-model, dataset, folder, report
  --limit  max results (default 20)
USAGE
      exit 0
      ;;
    *)
      if ! $QUERY_SET; then QUERY="$1"; QUERY_SET=true; else
        echo "search-files: unexpected argument '$1'" >&2; exit 2
      fi
      shift
      ;;
  esac
done

if ! $QUERY_SET; then
  echo "usage: search-files.sh <query> [--types <list>] [--limit N]" >&2
  exit 2
fi

python3 - "$SIGMA_BASE_URL" "$SIGMA_API_TOKEN" "$QUERY" "$TYPES" "$LIMIT" <<'PY'
import json, sys, urllib.error, urllib.parse, urllib.request

base, tok, query, types_csv, limit_s = sys.argv[1:]
types = [t.strip() for t in types_csv.split(",") if t.strip()]
limit = int(limit_s)
query_lc = query.lower().strip()

out, page = [], None
while len(out) < limit:
    # typeFilters is an array param — Sigma wants repeated keys
    # (typeFilters=workbook&typeFilters=data-model), NOT one comma-joined
    # value (confirmed live: a comma-joined value 400s with "Expecting
    # Array<...> at typeFilters.0 but instead got: <the whole string>").
    qs = [("typeFilters", t) for t in types] + [("limit", "1000")]
    if page:
        qs.append(("page", page))
    req = urllib.request.Request(
        f"{base}/v2/files?" + urllib.parse.urlencode(qs, doseq=True),
        headers={"Authorization": f"Bearer {tok}", "Accept": "application/json"},
    )
    try:
        d = json.load(urllib.request.urlopen(req))
    except urllib.error.HTTPError as e:
        body = e.read().decode(errors="replace")[:500]
        sys.stderr.write(f"search-files: HTTP {e.code} from /v2/files: {body}\n")
        sys.exit(1)

    for e in d.get("entries", []):
        name = e.get("name") or ""
        desc = e.get("description") or ""
        if query_lc and query_lc not in name.lower() and query_lc not in desc.lower():
            continue
        out.append({
            "type": e.get("type"),
            "id": e.get("id"),
            "urlId": e.get("urlId"),
            "name": e.get("name"),
            "description": e.get("description"),
            "path": e.get("path"),
        })
        if len(out) >= limit:
            break

    page = d.get("nextPage")
    if not page:
        break

print(json.dumps(out, indent=2))
sys.stderr.write(
    f"search-files: {len(out)} match(es) for '{query}' [types={','.join(types)}]\n"
)
PY
