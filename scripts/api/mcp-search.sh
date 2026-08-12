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
# Env:    self-bootstrapped via _env.sh
#
# Exit codes:
#   0 — success (including "no matches", which prints `[]`)
#   1 — MCP responded but reported an error
#   2 — usage error (bad args)
#   3 — MCP endpoint itself failed at the HTTP/transport level. Most
#       likely cause now: a stale or wrong-scope token (e.g. minted
#       before mcp:access was added, or a client_credentials token —
#       Sigma's /mcp/v2 only accepts interactive user OAuth, confirmed
#       by Sigma's MCP engineering team — see reference/history.md →
#       "2026-08-07"). Re-run scripts/api/browser-login.sh first; fall
#       back to scripts/api/search-files.sh (REST, substring not
#       semantic match) if MCP still isn't available.
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
import json, re, sys, urllib.error, urllib.request

base, tok, query, types_csv, limit_s = sys.argv[1:]

def to_kebab(t):
    # The MCP `search` tool's entityTypes enum is kebab-case (data-model,
    # data-model-element) -- confirmed live 2026-08-12 against a real org,
    # which rejects the camelCase forms this script's own --help text and
    # default previously used (dataModel, dataModelElement). Translate so
    # both spellings work rather than silently 400ing on the documented
    # camelCase usage.
    return re.sub(r"(?<!^)(?=[A-Z])", "-", t).lower()

types = [to_kebab(t.strip()) for t in types_csv.split(",") if t.strip()]
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
try:
    raw = urllib.request.urlopen(req).read().decode()
except urllib.error.HTTPError as e:
    err_body = e.read().decode(errors="replace")[:500]
    sys.stderr.write(
        f"mcp-search: MCP endpoint returned HTTP {e.code} for query '{query}'.\n"
        f"  This is a transport-level failure, not \"no matches\" — most likely\n"
        f"  a stale or wrong-scope token. Re-run scripts/api/browser-login.sh\n"
        f"  first (this skill's /mcp/v2 access requires an interactive-OAuth\n"
        f"  token with mcp:access scope, not a client_credentials one —\n"
        f"  confirmed by Sigma's MCP engineering team, see reference/history.md).\n"
        f"  If MCP still isn't available after that, fall back to\n"
        f"  scripts/api/search-files.sh \"{query}\" — REST-based, substring\n"
        f"  match rather than semantic search.\n"
        f"  Response body: {err_body}\n"
    )
    sys.exit(3)
except urllib.error.URLError as e:
    sys.stderr.write(f"mcp-search: could not reach MCP endpoint: {e.reason}\n")
    sys.exit(3)

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
    #
    # `data-model-element` results (confirmed live 2026-08-12) have a
    # genuinely different shape from every other type: no `name` key (the
    # element's own display name is `elementTitle`; `dataModelName` names
    # the parent for context) and no `dataModelId` key (the parent data
    # model's id -- same id space as GET /v2/dataModels/{id} -- rides on
    # `inodeId` instead). A previous version of this normalizer assumed
    # `name`/`dataModelId` keys that don't exist on this result type, which
    # silently produced `"name": null` and a missing `dataModelId` on every
    # data-model-element match -- not the occasional server omission
    # discover.md's "known gap" note described, but this bug, every time.
    out = []
    for r in results:
        rtype = r.get("type")
        if rtype == "data-model-element":
            item = {
                "type": rtype,
                "id": r.get("elementId"),
                "name": r.get("elementTitle") or r.get("name"),
                "url": r.get("url"),
                "description": r.get("description"),
                "dataModelId": r.get("inodeId"),
                "elementId": r.get("elementId"),
            }
        else:
            rid = (
                r.get("inodeId")
                or r.get("workbookId")
                or r.get("dataModelId")
                or r.get("elementId")
            )
            item = {
                "type": rtype,
                "id": rid,
                "name": r.get("name"),
                "url": r.get("url"),
                "description": r.get("description"),
            }
        out.append(item)
    print(json.dumps(out, indent=2))
    sys.stderr.write(
        f"mcp-search: {len(out)} match(es) for '{query}' [types={','.join(types)}]\n"
    )
    break
PY
