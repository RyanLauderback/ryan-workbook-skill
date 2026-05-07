#!/usr/bin/env bash
# Export a Sigma data model spec (workbook structure) to a local file.
#
# Usage:  scripts/export-workbook.sh <data-model-id> [output-path]
# Defaults output to workbooks/_exemplars/<data-model-id>.json
#
# Requires:
#   - $SIGMA_BASE_URL and $SIGMA_API_TOKEN exported in the environment.
#     Get a token first via the sigma-api skill (loaded as a plugin).
#   - jq available on PATH.
#
# Notes:
#   - This script is a thin wrapper. The authoritative endpoints, IDs semantics,
#     and edge cases live in the sigma-data-models skill — read that skill's
#     reference/workflows when iterating on this script.
#   - Never commit responses that contain secrets; specs themselves are normally safe.

set -euo pipefail

if [ "${1-}" = "" ]; then
  echo "usage: $0 <data-model-id> [output-path]" >&2
  exit 2
fi

: "${SIGMA_BASE_URL:?SIGMA_BASE_URL not set; eval \"\$(scripts/load-env.sh)\" then run the sigma-api skill to get a token}"
: "${SIGMA_API_TOKEN:?SIGMA_API_TOKEN not set; run the sigma-api skill to obtain one}"

MODEL_ID="$1"
OUT_PATH="${2:-workbooks/_exemplars/${MODEL_ID}.json}"
mkdir -p "$(dirname "$OUT_PATH")"

echo "GET $SIGMA_BASE_URL/v2/data-models/$MODEL_ID -> $OUT_PATH" >&2

curl -sf \
  -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  -H "Accept: application/json" \
  "$SIGMA_BASE_URL/v2/data-models/$MODEL_ID" \
  | jq . > "$OUT_PATH"

echo "Wrote $OUT_PATH" >&2
