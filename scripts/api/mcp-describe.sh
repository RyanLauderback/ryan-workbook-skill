#!/usr/bin/env bash
# Call the Sigma MCP server's `describe` tool and print its DDL output.
#
# The MCP server returns SQL CREATE TABLE-style DDL with column types,
# descriptions, source formulas, and a labeled metrics catalog — richer
# than the JSON spec from /v2/dataModels/{id}/spec.
#
# Usage:
#   scripts/api/mcp-describe.sh table             <inodeId>
#   scripts/api/mcp-describe.sh datamodel         <dataModelId>
#   scripts/api/mcp-describe.sh datamodel-element <dataModelId> <elementId>
#   scripts/api/mcp-describe.sh workbook          <workbookId>
#   scripts/api/mcp-describe.sh workbook-element  <workbookId>     <elementId>
#
# Env:    self-bootstrapped via _env.sh (loads .env, caches OAuth token)
# Output: The DDL text (stdout). The MCP `url` field is appended as a comment.
set -euo pipefail
source "$(dirname "$0")/_env.sh"

if [ "$#" -lt 2 ]; then
  cat >&2 <<'USAGE'
usage:
  mcp-describe.sh table             <inodeId>
  mcp-describe.sh datamodel         <dataModelId>
  mcp-describe.sh datamodel-element <dataModelId> <elementId>
  mcp-describe.sh workbook          <workbookId>
  mcp-describe.sh workbook-element  <workbookId>  <elementId>
USAGE
  exit 2
fi

python3 - "$SIGMA_BASE_URL" "$SIGMA_API_TOKEN" "$@" <<'PY'
import json, re, sys, urllib.request

base, tok, kind, *ids = sys.argv[1:]

# Build the object argument per the MCP tool's input schema.
arg_specs = {
    "table":              ("inodeId",),
    "datamodel":          ("dataModelId",),
    "datamodel-element":  ("dataModelId", "elementId"),
    "workbook":           ("workbookId",),
    "workbook-element":   ("workbookId", "elementId"),
}
if kind not in arg_specs:
    sys.stderr.write(f"mcp-describe: unknown kind '{kind}'\n")
    sys.exit(2)
fields = arg_specs[kind]
if len(ids) != len(fields):
    sys.stderr.write(f"mcp-describe: '{kind}' needs {len(fields)} id(s): {' '.join(fields)}\n")
    sys.exit(2)

obj = {"type": kind, **dict(zip(fields, ids))}
body = {
    "jsonrpc": "2.0",
    "id": 1,
    "method": "tools/call",
    "params": {"name": "describe", "arguments": {"object": obj}},
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

# SSE frame: `event: message\ndata: {...json...}\n\n` — extract the JSON payload.
m = re.search(r"data:\s*(\{.+\})", raw, re.DOTALL)
if not m:
    sys.stderr.write(f"mcp-describe: unexpected response shape:\n{raw[:500]}\n")
    sys.exit(1)
envelope = json.loads(m.group(1))

if envelope.get("error"):
    sys.stderr.write(f"mcp-describe: server error: {envelope['error']}\n")
    sys.exit(1)
result = envelope["result"]
if result.get("isError"):
    for c in result.get("content", []):
        if c.get("type") == "text":
            sys.stderr.write(c["text"] + "\n")
    sys.exit(1)

# `describe` returns content[].text containing a JSON blob: {ddl, url}.
for c in result.get("content", []):
    if c.get("type") != "text":
        continue
    try:
        payload = json.loads(c["text"])
    except json.JSONDecodeError:
        print(c["text"])
        break
    ddl = payload.get("ddl", "")
    url = payload.get("url")
    print(ddl.rstrip())
    if url:
        print(f"\n-- Open in Sigma: {url}")
    break
PY
