#!/usr/bin/env bash
# verify-workbook.sh — confirm a workbook's elements compile to valid SQL.
#
# Why this exists: POST /v2/workbooks/spec is generous. It accepts specs
# whose column formulas don't actually resolve, then surfaces the failures
# at query time as string literals embedded in the compiled SQL — e.g.
#   select 'Unknown column "[ORDER_TOTAL]"' V_44 from ...
#   select 'Circular column reference to [Quarter]' V_11 ...
# The UI renders these elements as empty. Catching this from the spec
# text alone is impossible; only Sigma's compiler knows.
#
# For each element on the workbook, fetches the compiled SQL via
#   GET /v2/workbooks/{id}/elements/{eid}/query
# and greps the markers. Any hit means a formula doesn't resolve.
#
# Adapted from the upstream sigma-workbooks skill's verify-workbook.sh
# to use ryan's _env.sh sourcing + sigma_curl 401-retry helper.
#
# Usage: scripts/api/verify-workbook.sh <workbook-id>
# Exit codes:
#   0 — every element compiled clean
#   1 — one or more elements have unresolved/circular references
#   2 — setup / input error

set -euo pipefail
source "$(dirname "$0")/_env.sh"

WB_ID="${1:-}"
if [ -z "$WB_ID" ]; then
  echo "Usage: $0 <workbook-id>" >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required. Install with: brew install jq (macOS) or apt install jq (Debian/Ubuntu)." >&2
  exit 2
fi

# Pull the workbook's element list. sigma_curl handles auth + 401 retries.
set +e
ELEMENTS_JSON=$(sigma_curl "$SIGMA_BASE_URL/v2/workbooks/$WB_ID/elements")
list_exit=$?
set -e

if [ "$list_exit" -ne 0 ]; then
  echo "Error: could not fetch elements for workbook $WB_ID (exit=$list_exit)." >&2
  echo "Response: $ELEMENTS_JSON" >&2
  exit 2
fi

ERRORS=0
TOTAL=0
while IFS=$'\t' read -r EID NAME; do
  TOTAL=$((TOTAL + 1))

  # /elements/{id}/query 4xx's on controls and similar non-queryable
  # elements — don't let the inner fetch kill the loop.
  set +e
  RAW=$(sigma_curl "$SIGMA_BASE_URL/v2/workbooks/$WB_ID/elements/$EID/query")
  set -e
  SQL=$(printf '%s' "$RAW" | jq -r '.sql // ""' 2>/dev/null || true)

  if [ -z "$SQL" ]; then
    printf '  [skip] %-40s (%s) — no SQL (control or non-queryable element)\n' "$NAME" "$EID"
    continue
  fi

  # grep exits 1 when no matches, which would trip `set -o pipefail` —
  # swallow that case explicitly so a clean element doesn't kill the loop.
  BAD=$(printf '%s' "$SQL" \
    | grep -oE "(Unknown column \"[^\"]+\"|Circular column reference to \[[^]]+\])" \
    | sort -u | paste -sd '; ' - || true)
  if [ -n "$BAD" ]; then
    printf '  [FAIL] %-40s (%s) — %s\n' "$NAME" "$EID" "$BAD"
    ERRORS=$((ERRORS + 1))
  else
    printf '  [ok]   %-40s (%s)\n' "$NAME" "$EID"
  fi
done < <(echo "$ELEMENTS_JSON" | jq -r '.entries[]? | [.elementId, .name] | @tsv')

echo ""
if [ "$ERRORS" -gt 0 ]; then
  echo "$ERRORS of $TOTAL element(s) have unresolved formula references."
  echo "Fix the offending columns in the spec (see reference/specification/formulas.md)"
  echo "and re-PUT the spec, then re-verify."
  exit 1
fi
echo "All $TOTAL element(s) compile cleanly."
exit 0
