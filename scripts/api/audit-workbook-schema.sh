#!/usr/bin/env bash
# audit-workbook-schema.sh — post-POST/PUT gate that catches formula
# errors at Sigma's DATA layer, not just at the compiled-SQL layer.
#
# Why this exists: verify-workbook.sh greps compiled SQL for markers
# like `Unknown column "..."` / `Circular column reference to [...]`.
# It MISSES the class of failure where a formula compiles into
# structurally-valid SQL but references an already-errored column, or
# uses a function / argument shape Sigma rejects at query time. In the
# schema returned by `mcp-describe workbook-element`, these columns
# show `type: error`. The UI renders them as `Reference to errored
# column "[X]"` or leaves the cell blank.
#
# Recent examples this catches (that verify-workbook.sh missed):
#   - `NTile([col], 5)` — unrecognized function, arg1 error
#   - `Percentile([<GroupedSource>/<col>], 0.2)` — cross-boundary
#     aggregation of a grouped column
#   - `Rollup(<agg>, <partition>, <non-partition-col>)` — arg3 mismatch
#   - Inline `Percentile(sibling)` mixed with per-row If on a table
#     sourcing a grouped element
#
# For each element with columns (skips controls, containers, text, and
# other non-queryable elements), this script calls `mcp-describe
# workbook-element`, parses the DDL for `error`-typed columns, and
# reports element + column + display name + formula so the failure is
# fixable without opening the workbook in the UI.
#
# Usage:  scripts/api/audit-workbook-schema.sh <workbook-id>
# Exit codes:
#   0 — no error-typed columns (a genuine clean pass)
#   1 — one or more error-typed columns detected
#   2 — setup / input error
#   3 — INCOMPLETE: one or more elements could not be checked because
#       mcp-describe.sh failed at the transport level (its own exit 3 —
#       e.g. a stale/wrong-scope token, a 403/5xx/connection failure).
#       This is deliberately NOT folded into exit 0 — a total MCP
#       outage must not read as "audit passed clean." Found via a live
#       build-mode test 2026-08-03: this exact case previously printed
#       "0 queryable element(s) checked, no error-typed columns,"
#       indistinguishable from a real clean audit of a workbook with no
#       queryable elements. Under this skill's current browser-login.sh
#       auth path, mcp-describe is expected to succeed, so hitting exit
#       3 here now is unexpected — a signal something's actually wrong
#       (stale token, real outage), not a routine/permanent condition —
#       but it's still handled the same defensive way: never folded
#       into exit 0.
#
# publish-workbook.sh invokes this automatically after POST and PUT.
# Call directly to re-audit a workbook without republishing.
set -euo pipefail
source "$(dirname "$0")/_env.sh"

WB_ID="${1:-}"
if [ -z "$WB_ID" ]; then
  cat >&2 <<'USAGE'
usage: audit-workbook-schema.sh <workbook-id>
USAGE
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required. Install with: brew install jq (macOS) or apt install jq (Debian/Ubuntu)." >&2
  exit 2
fi

script_dir="$(dirname "$0")"

# Pull the workbook's element list. Same endpoint verify-workbook.sh uses.
set +e
ELEMENTS_JSON=$(sigma_curl "$SIGMA_BASE_URL/v2/workbooks/$WB_ID/elements")
list_exit=$?
set -e
if [ "$list_exit" -ne 0 ]; then
  echo "audit-workbook-schema: could not fetch elements for workbook $WB_ID (exit=$list_exit)." >&2
  echo "Response: $ELEMENTS_JSON" >&2
  exit 2
fi

TOTAL_ELEMENTS=0
CHECKED_ELEMENTS=0
TOTAL_ERRORS=0
DESCRIBE_FAILURES=0
HEADER_SHOWN=0

describe_err_file="$(mktemp "${TMPDIR:-/tmp}/audit-describe-err.XXXXXX")"
trap 'rm -f "$describe_err_file"' EXIT

while IFS=$'\t' read -r EID NAME; do
  TOTAL_ELEMENTS=$((TOTAL_ELEMENTS + 1))

  # mcp-describe.sh exit 1 means "MCP responded but this element isn't
  # describable" — the normal case for controls/containers/text, skipped
  # silently. Exit 3 means the MCP call itself failed at the HTTP/transport
  # level (e.g. a stale/wrong-scope token) — that is NOT the same as
  # "nothing to check" and must not be swallowed the same way, or a total
  # MCP outage reads as a clean audit. (Bug found 2026-08-03 via a live
  # build-mode test predating this skill's browser-login.sh auth path,
  # when every mcp-describe call hit this case; the audit previously
  # reported "0 queryable element(s) checked, no error-typed columns" —
  # indistinguishable from a real clean pass. Under the current auth path
  # this is unexpected rather than routine, but still handled the same
  # defensive way.)
  set +e
  DDL=$("$script_dir/mcp-describe.sh" workbook-element "$WB_ID" "$EID" 2>"$describe_err_file")
  desc_exit=$?
  set -e
  desc_err="$(cat "$describe_err_file")"

  if [ "$desc_exit" -eq 3 ]; then
    DESCRIBE_FAILURES=$((DESCRIBE_FAILURES + 1))
    if [ "$DESCRIBE_FAILURES" -eq 1 ]; then
      echo "" >&2
      echo "WARNING: mcp-describe failed at the transport level for element $EID ($NAME):" >&2
      echo "$desc_err" | sed 's/^/  /' >&2
    fi
    continue
  fi

  if [ "$desc_exit" -ne 0 ] || [ -z "$DDL" ]; then
    continue
  fi

  CHECKED_ELEMENTS=$((CHECKED_ELEMENTS + 1))

  # DDL column lines look like:  `  "<col-id>" <type>[,] -- "<Display>" | Formula: <expr>`
  # Match ONLY lines whose type is `error` (with a trailing space, comma, or newline).
  ERR_LINES=$(printf '%s' "$DDL" | grep -E '^[[:space:]]*"[^"]+"[[:space:]]+error[[:space:]]*[,-]' || true)

  if [ -z "$ERR_LINES" ]; then
    continue
  fi

  N=$(printf '%s\n' "$ERR_LINES" | wc -l | tr -d ' ')
  TOTAL_ERRORS=$((TOTAL_ERRORS + N))

  if [ "$HEADER_SHOWN" -eq 0 ]; then
    echo ""
    echo "==========================================================="
    echo "  audit-workbook-schema: FORMULA ERRORS AT DATA LAYER"
    echo "==========================================================="
    HEADER_SHOWN=1
  fi

  echo ""
  printf 'Element: %s  (%s)\n' "$NAME" "$EID"
  while IFS= read -r line; do
    col_id=$(printf '%s' "$line" | sed -E 's/^[[:space:]]*"([^"]+)".*/\1/')
    display=$(printf '%s' "$line" | sed -nE 's/.*--[[:space:]]+"([^"]+)".*/\1/p')
    formula=$(printf '%s' "$line" | sed -nE 's/.*Formula:[[:space:]]+(.*)$/\1/p')
    if [ -n "$display" ]; then
      printf '  [ERR] %s  ("%s")\n' "$col_id" "$display"
    else
      printf '  [ERR] %s\n' "$col_id"
    fi
    if [ -n "$formula" ]; then
      printf '        formula: %s\n' "$formula"
    fi
  done <<< "$ERR_LINES"
done < <(echo "$ELEMENTS_JSON" | jq -r '.entries[]? | [.elementId, .name] | @tsv')

echo ""
if [ "$TOTAL_ERRORS" -gt 0 ]; then
  echo "$TOTAL_ERRORS error-typed column(s) detected across $CHECKED_ELEMENTS queryable element(s)."
  echo ""
  echo "These formulas produced a valid POST/PUT response but will render as"
  echo "\"Reference to errored column\" or blank in the UI. Fix and re-PUT."
  echo ""
  echo "Common causes (see reference/specification/formulas.md):"
  echo "  - Unknown function (e.g. NTile is not a Sigma function; use a DM metric)"
  echo "  - Percentile / Sum / Avg across an element boundary on a grouped-source column"
  echo "  - Rollup arg3 that isn't the partition column or an ordering column"
  echo "  - Inline aggregation mixed with per-row refs on a table sourcing a grouped element"
  exit 1
fi

if [ "$DESCRIBE_FAILURES" -gt 0 ]; then
  echo "" >&2
  echo "audit-workbook-schema: INCOMPLETE — $DESCRIBE_FAILURES of $TOTAL_ELEMENTS element(s) could not be" >&2
  echo "  checked (mcp-describe failed at the transport level, not \"not describable\")." >&2
  echo "  $CHECKED_ELEMENTS element(s) that WERE reachable show no error-typed columns, but" >&2
  echo "  this is NOT a clean audit — the gate could not inspect everything it should have." >&2
  echo "  Under this skill's current browser-login.sh auth path mcp-describe is expected" >&2
  echo "  to succeed, so this is unexpected — most likely a stale/wrong-scope token; re-run" >&2
  echo "  scripts/api/browser-login.sh. See reference/workflows/discover.md for the REST" >&2
  echo "  fallback, though that fallback does not cover this script's own DDL-based" >&2
  echo "  error-column detection." >&2
  echo "  Do not report this workbook as built-and-verified on this signal alone —" >&2
  echo "  fall back to a manual UI check of the elements above. Suppress this exit with" >&2
  echo "  SIGMA_SKIP_AUDIT=1 only if you understand the gate did not actually run." >&2
  exit 3
fi

echo "audit-workbook-schema: $CHECKED_ELEMENTS queryable element(s) checked, no error-typed columns."
exit 0
