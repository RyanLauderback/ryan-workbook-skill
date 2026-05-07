#!/usr/bin/env bash
# Push a local Sigma data model spec back to Sigma.
#
# Usage:
#   scripts/push-workbook.sh create <spec-path>                  # POST new model
#   scripts/push-workbook.sh update <data-model-id> <spec-path>  # PUT existing model
#
# Requires:
#   - $SIGMA_BASE_URL and $SIGMA_API_TOKEN exported.
#   - jq available on PATH.
#
# Notes:
#   - Sigma's create/update endpoints require the COMPLETE spec; partial updates
#     are not supported. See the sigma-data-models skill's reference/workflows
#     for ID-semantics rules (CREATE remaps, GET is source-of-truth, UPDATE preserves).
#   - This script is a thin wrapper. Read the skill before iterating on it.

set -euo pipefail

: "${SIGMA_BASE_URL:?SIGMA_BASE_URL not set; eval \"\$(scripts/load-env.sh)\" then run the sigma-api skill to get a token}"
: "${SIGMA_API_TOKEN:?SIGMA_API_TOKEN not set; run the sigma-api skill to obtain one}"

cmd="${1-}"
case "$cmd" in
  create)
    spec_path="${2-}"
    [ -n "$spec_path" ] || { echo "usage: $0 create <spec-path>" >&2; exit 2; }
    [ -f "$spec_path" ] || { echo "spec not found: $spec_path" >&2; exit 1; }
    echo "POST $SIGMA_BASE_URL/v2/data-models  (body=$spec_path)" >&2
    curl -sf -X POST \
      -H "Authorization: Bearer $SIGMA_API_TOKEN" \
      -H "Content-Type: application/json" \
      -H "Accept: application/json" \
      --data-binary "@$spec_path" \
      "$SIGMA_BASE_URL/v2/data-models" \
      | jq .
    ;;
  update)
    model_id="${2-}"
    spec_path="${3-}"
    [ -n "$model_id" ] && [ -n "$spec_path" ] || { echo "usage: $0 update <data-model-id> <spec-path>" >&2; exit 2; }
    [ -f "$spec_path" ] || { echo "spec not found: $spec_path" >&2; exit 1; }
    echo "PUT $SIGMA_BASE_URL/v2/data-models/$model_id  (body=$spec_path)" >&2
    curl -sf -X PUT \
      -H "Authorization: Bearer $SIGMA_API_TOKEN" \
      -H "Content-Type: application/json" \
      -H "Accept: application/json" \
      --data-binary "@$spec_path" \
      "$SIGMA_BASE_URL/v2/data-models/$model_id" \
      | jq .
    ;;
  *)
    echo "usage: $0 {create <spec-path>|update <data-model-id> <spec-path>}" >&2
    exit 2
    ;;
esac
