#!/usr/bin/env bash
# Probe a schema for table existence by trying a list of likely names via lookup-path.
# Used when the API has no "list children of a schema scope" endpoint.
# Usage:  scripts/api/probe-schema-tables.sh <connectionId> <db> <schema> [names...]
# Output: JSON array [{name, inodeId}] for hits.
# Env:    self-bootstrapped via _env.sh (loads .env, caches OAuth token)
set -euo pipefail
source "$(dirname "$0")/_env.sh"

if [ "$#" -lt 3 ]; then
  echo "usage: probe-schema-tables.sh <connectionId> <db> <schema> [names...]" >&2
  exit 2
fi

CONN="$1"; DB="$2"; SCHEMA="$3"; shift 3

# Default name list — common warehouse-sample table names.
if [ "$#" -eq 0 ]; then
  set -- \
    TRIP TRIPS STATION STATIONS WEATHER \
    CUSTOMER CUSTOMERS USER USERS \
    ORDER ORDERS PRODUCT PRODUCTS \
    SALES TRANSACTIONS PAYMENTS RENTALS \
    EVENT EVENTS SESSIONS RIDES BIKES \
    ACCOUNTS ACCOUNT INVOICES INVOICE \
    EMPLOYEE EMPLOYEES STORE STORES
fi

python3 - "$SIGMA_BASE_URL" "$SIGMA_API_TOKEN" "$CONN" "$DB" "$SCHEMA" "$@" <<'PY'
import json, sys, urllib.parse, urllib.request, urllib.error
from concurrent.futures import ThreadPoolExecutor

base, tok, conn, db, schema, *names = sys.argv[1:]

def probe(name):
    body = json.dumps({"path": [db, schema, name]}).encode()
    req = urllib.request.Request(
        f"{base}/v2/connection/{conn}/lookup",
        data=body, method="POST",
        headers={"Authorization": f"Bearer {tok}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r:
            d = json.loads(r.read())
            if d.get("kind") == "table":
                return {"name": name, "inodeId": d.get("inodeId")}
    except urllib.error.HTTPError:
        return None
    return None

found = []
with ThreadPoolExecutor(max_workers=8) as ex:
    for r in ex.map(probe, names):
        if r: found.append(r)
json.dump(found, sys.stdout, indent=2); print()
PY
