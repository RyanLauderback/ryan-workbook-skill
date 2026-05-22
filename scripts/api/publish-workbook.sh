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
# `post` (calls scripts/validate-spec.py). No `delete` subcommand here —
# deletion stays on the direct-curl path so it always hits the DELETE ask
# pattern in .claude/settings.json.
set -euo pipefail
source "$(dirname "$0")/_env.sh"

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
    sigma_curl -X POST \
      -H "Content-Type: application/json" \
      --data-binary "@$spec" \
      "$SIGMA_BASE_URL/v2/workbooks/spec"
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
    sigma_curl -X PUT \
      -H "Content-Type: application/json" \
      --data-binary "@$spec" \
      "$SIGMA_BASE_URL/v2/workbooks/$wb_id/spec"
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
USAGE
    exit 2
    ;;
esac
