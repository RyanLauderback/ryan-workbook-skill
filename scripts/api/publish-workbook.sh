#!/usr/bin/env bash
# Publish workbook specs to Sigma — POST a new workbook, GET back the spec,
# fetch URL/metadata. Wraps the publish pipeline so callers don't compose
# eval/export/curl chains by hand.
#
# Usage:
#   scripts/api/publish-workbook.sh post     <spec-file>
#   scripts/api/publish-workbook.sh put      <workbook-id> <spec-file>
#   scripts/api/publish-workbook.sh get-spec <workbook-id>
#   scripts/api/publish-workbook.sh get-meta <workbook-id>
#
# Auth, Accept: application/json header, and 401 auto-retry are all handled
# by the sigma_curl helper in _env.sh. Spec validation runs automatically on
# `post`/`put` (calls scripts/validate-spec.py). After a successful POST or
# PUT, audit-workbook-schema.sh runs automatically to catch formula errors
# at Sigma's DATA layer — the class of failure that verify-workbook.sh
# misses because the compiled SQL is structurally valid but references an
# errored column. Suppress the audit by setting SIGMA_SKIP_AUDIT=1.
#
# No `delete` subcommand here — deletion stays on the direct-curl path so
# it always hits the DELETE ask pattern in .claude/settings.json.
set -euo pipefail
source "$(dirname "$0")/_env.sh"

script_dir="$(dirname "$0")"

run_audit() {
  # $1 = workbook id
  # Runs audit-workbook-schema.sh unless SIGMA_SKIP_AUDIT=1. Exits with the
  # audit's exit code so the caller sees the failure signal.
  local wb_id="$1"
  if [ "${SIGMA_SKIP_AUDIT:-0}" = "1" ]; then
    return 0
  fi
  echo ""
  "$script_dir/audit-workbook-schema.sh" "$wb_id"
}

cmd="${1:-}"
case "$cmd" in
  post)
    spec="${2:?usage: publish-workbook.sh post <spec-file>}"
    if [ ! -f "$spec" ]; then
      echo "publish-workbook: spec file not found: $spec" >&2
      exit 2
    fi
    repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
    python3 "$repo_root/scripts/validate-spec.py" "$spec"
    # Capture the response so we can parse the workbook ID for the audit,
    # then echo it back so callers still see the JSON they expect.
    response=$(sigma_curl -X POST \
      -H "Content-Type: application/json" \
      --data-binary "@$spec" \
      "$SIGMA_BASE_URL/v2/workbooks/spec")
    echo "$response"
    wb_id=$(echo "$response" | jq -r '.workbookId // empty' 2>/dev/null || true)
    if [ -n "$wb_id" ] && [ "$wb_id" != "null" ]; then
      run_audit "$wb_id"
    fi
    ;;
  put)
    wb_id="${2:?usage: publish-workbook.sh put <workbook-id> <spec-file>}"
    spec="${3:?usage: publish-workbook.sh put <workbook-id> <spec-file>}"
    if [ ! -f "$spec" ]; then
      echo "publish-workbook: spec file not found: $spec" >&2
      exit 2
    fi
    repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
    python3 "$repo_root/scripts/validate-spec.py" "$spec"
    response=$(sigma_curl -X PUT \
      -H "Content-Type: application/json" \
      --data-binary "@$spec" \
      "$SIGMA_BASE_URL/v2/workbooks/$wb_id/spec")
    echo "$response"
    # PUT response echoes the workbookId back; if the caller passed a
    # bogus id and PUT returned an error, skip the audit.
    if echo "$response" | jq -e '.success == true' >/dev/null 2>&1; then
      run_audit "$wb_id"
    fi
    ;;
  get-spec)
    wb_id="${2:?usage: publish-workbook.sh get-spec <workbook-id>}"
    sigma_curl "$SIGMA_BASE_URL/v2/workbooks/$wb_id/spec"
    ;;
  get-meta)
    wb_id="${2:?usage: publish-workbook.sh get-meta <workbook-id>}"
    sigma_curl "$SIGMA_BASE_URL/v2/workbooks/$wb_id"
    ;;
  *)
    cat >&2 <<'USAGE'
usage:
  publish-workbook.sh post     <spec-file>
  publish-workbook.sh put      <workbook-id> <spec-file>
  publish-workbook.sh get-spec <workbook-id>
  publish-workbook.sh get-meta <workbook-id>

After a successful POST or PUT, audit-workbook-schema.sh runs automatically
to catch data-layer formula errors. Set SIGMA_SKIP_AUDIT=1 to suppress.
USAGE
    exit 2
    ;;
esac
