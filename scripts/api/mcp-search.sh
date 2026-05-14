#!/usr/bin/env bash
# Call the Sigma MCP server's `search` tool to find content in the existing
# Sigma workspace (workbooks, data models, data model elements, tables) by
# name or topic. Returns a JSON array of {type, id, name, url, description}.
#
# Use this as the first call for any prompt that references existing Sigma
# content by name or topic — it indexes the whole workspace in one shot.
#
# Usage:
#   scripts/api/mcp-search.sh <query> [--types <list>] [--limit N]
#
#   <query>   Search string (e.g. "sales dashboard", "PLUGS Data Model")
#   --types   Comma-separated subset of:
#             workbook, dataModel, dataModelElement, table.
#             Default: all four.
#   --limit   Max results (1-20). Default: 10.
#
# Env:    self-bootstrapped via _env.sh (loads .env, caches OAuth token)
set -euo pipefail
source "$(dirname "$0")/_env.sh"

QUERY=""
TYPES="workbook,dataModel,dataModelElement,table"
LIMIT=10

while [ "$#" -gt 0 ]; do
  case "$1" in
    --types) TYPES="$2"; shift 2 ;;
    --limit) LIMIT="$2"; shift 2 ;;
    -h|--help)
      cat <<USAGE
usage: mcp-search.sh <query> [--types <list>] [--limit N]
  --types  comma-separated subset of: workbook, dataModel, dataModelElement, table
  --limit  1-20 (default 10)
USAGE
      exit 0
      ;;
    *)
      if [ -z "$QUERY" ]; then QUERY="$1"; else
        echo "mcp-search: unexpected argument '$1'" >&2; exit 2
      fi
      shift
      ;;
  esac
done

if [ -z "$QUERY" ]; then
  echo "usage: mcp-search.sh <query> [--types <list>] [--limit N]" >&2
  exit 2
fi

python3 - "$SIGMA_BASE_URL" "$SIGMA_API_TOKEN" "$QUERY" "$TYPES" "$LIMIT" <<'PY'
import json, re, sys, urllib.request

base, tok, query, types_csv, limit_s = sys.argv[1:]
types = [t.strip() for t in types_csv.split(",") if t.strip()]
limit = int(limit_s)

body = {
    "jsonrpc": "2.0",
    "id": 1,
    "method": "tools/call",
    "params": {
        "name": "search",
        "arguments": {"query": query, "entityTypes": types, "limit": limit},
    },
}

req = urllib.request.Request(
    f"{base}/mcp/v2",
    data=json.dumps(body).encode(),
    headers={
        "Authorization": f"Bearer {tok}",
        "Content-Type": "application/json",
        "Accept": "application/json, text/event-stream",
    },
)
raw = urllib.request.urlopen(req).read().decode()

# SSE: `event: message\ndata: {...json...}\n\n`
m = re.search(r"data:\s*(\{.+\})", raw, re.DOTALL)
if not m:
    sys.stderr.write(f"mcp-search: unexpected response shape:\n{raw[:500]}\n")
    sys.exit(1)
envelope = json.loads(m.group(1))

if envelope.get("error"):
    sys.stderr.write(f"mcp-search: server error: {envelope['error']}\n")
    sys.exit(1)
result = envelope["result"]
if result.get("isError"):
    for c in result.get("content", []):
        if c.get("type") == "text":
            sys.stderr.write(c["text"] + "\n")
    sys.exit(1)

for c in result.get("content", []):
    if c.get("type") != "text":
        continue
    try:
        payload = json.loads(c["text"])
    except json.JSONDecodeError:
        print(c["text"])
        break

    results = payload.get("results", [])
    if not results:
        print("[]")
        sys.stderr.write(f"mcp-search: no matches for '{query}' [types={','.join(types)}]\n")
        break

    # Normalize to a flat {type, id, name, url, description} shape so callers
    # don't have to know that workbook IDs come from `inodeId` while
    # data-model elements expose both `dataModelId` + `elementId`.
    out = []
    for r in results:
        rid = (
            r.get("inodeId")
            or r.get("workbookId")
            or r.get("dataModelId")
            or r.get("elementId")
        )
        item = {
            "type": r.get("type"),
            "id": rid,
            "name": r.get("name"),
            "url": r.get("url"),
            "description": r.get("description"),
        }
        # Data-model elements need both IDs to be addressable downstream.
        if r.get("type") == "dataModelElement":
            item["dataModelId"] = r.get("dataModelId")
            item["elementId"] = r.get("elementId")
        out.append(item)
    print(json.dumps(out, indent=2))
    sys.stderr.write(
        f"mcp-search: {len(out)} match(es) for '{query}' [types={','.join(types)}]\n"
    )
    break
PY
