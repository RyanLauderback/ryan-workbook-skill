#!/usr/bin/env bash
# Harvest a Sigma workbook spec + generate a manifest.
#
# Usage:
#   scripts/api/harvest-workbook.sh <workbook-id-or-urlId> [slug]
#
# Resolves urlId → workbook-id if needed (via find-file-by-urlid.sh),
# pulls the spec via publish-workbook.sh get-spec, saves to
# workbooks/harvest/<slug>/spec.json, runs workbook-manifest.py and
# saves manifest.md alongside. <slug> defaults to the workbook's name
# (lowercased, slugified) — pass it explicitly to override.
#
# workbooks/harvest/ is gitignored (workbooks/*/ pattern with allow-list).
set -euo pipefail
source "$(dirname "$0")/_env.sh"

if [ "$#" -lt 1 ]; then
  echo "usage: harvest-workbook.sh <workbook-id-or-urlId> [slug]" >&2
  exit 2
fi

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
input="$1"
slug_override="${2:-}"

# Workbook IDs are UUIDs (8-4-4-4-12 hex). Anything else is treated as a urlId.
is_uuid() { [[ "$1" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; }

if is_uuid "$input"; then
  wb_id="$input"
  # Need the name for the slug — pull metadata.
  wb_name=$("$(dirname "$0")/publish-workbook.sh" get-meta "$wb_id" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("name",""))')
else
  echo "Resolving urlId '$input'…" >&2
  meta=$("$(dirname "$0")/find-file-by-urlid.sh" "$input")
  if [ "$meta" = "null" ]; then
    echo "harvest-workbook: urlId '$input' not found via /v2/files scan" >&2
    exit 1
  fi
  wb_id=$(echo "$meta" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("id",""))')
  wb_name=$(echo "$meta" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("name",""))')
  if [ -z "$wb_id" ]; then
    echo "harvest-workbook: could not extract workbook id from /v2/files entry" >&2
    exit 1
  fi
fi

# Compute slug. lowercase, replace non-alnum with -, collapse, trim.
default_slug=$(echo "$wb_name" | python3 -c '
import re, sys
s = sys.stdin.read().strip().lower()
s = re.sub(r"[^a-z0-9]+", "-", s).strip("-")
print(s or "workbook")
')
slug="${slug_override:-$default_slug}"

out_dir="$repo_root/workbooks/harvest/$slug"
mkdir -p "$out_dir"

echo "Harvesting workbook id=$wb_id name='$wb_name' → workbooks/harvest/$slug/" >&2

# Pull spec. Suspend `set -e` so we can inspect a 500 body — sigma_curl
# exits non-zero on HTTP error, which would otherwise kill the script
# before we can show the user what came back.
set +e
"$(dirname "$0")/publish-workbook.sh" get-spec "$wb_id" > "$out_dir/spec.json"
get_exit=$?
set -e

# If the body parses as a service_error envelope, abort with a useful
# message. Sigma returns 500 with `code: service_error` on workbooks
# whose UI features the spec serializer can't represent (confirmed
# trigger: pivot conditional formatting; suspected: maps, color-by).
if python3 -c "import json,sys; d=json.load(open('$out_dir/spec.json')); sys.exit(0 if d.get('code')=='service_error' else 1)" 2>/dev/null; then
  err_msg=$(python3 -c "import json; print(json.load(open('$out_dir/spec.json')).get('message',''))" 2>/dev/null)
  echo "" >&2
  echo "✗ GET-spec returned service_error for this workbook (exit=$get_exit):" >&2
  echo "    $err_msg" >&2
  echo "" >&2
  echo "  Typical cause: the workbook contains a UI feature the spec serializer" >&2
  echo "  can't represent. See reference/scope-and-edge-cases.md → \"GET-spec can 500" >&2
  echo "  when UI features aren't representable\" for the known triggers." >&2
  echo "" >&2
  echo "  Removing spec.json so it doesn't seed downstream work." >&2
  rm "$out_dir/spec.json"
  exit 1
fi

# Spec pulled cleanly but get-spec exited non-zero for another reason.
if [ "$get_exit" -ne 0 ]; then
  echo "✗ publish-workbook.sh get-spec exited $get_exit" >&2
  exit "$get_exit"
fi

# Save metadata sidecar for traceability (workbook id, url, harvested-at).
cat > "$out_dir/source.json" <<EOF
{
  "workbookId": "$wb_id",
  "name": "$wb_name",
  "harvestedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "input": "$input"
}
EOF

# Generate manifest.
python3 "$repo_root/scripts/workbook-manifest.py" "$out_dir/spec.json" --out "$out_dir/manifest.md"

echo "" >&2
echo "✓ harvested to workbooks/harvest/$slug/" >&2
echo "  - spec.json     ($(wc -c < "$out_dir/spec.json" | tr -d ' ') bytes)" >&2
echo "  - manifest.md   ($(wc -l < "$out_dir/manifest.md" | tr -d ' ') lines)" >&2
echo "  - source.json   (workbook id + harvest metadata)" >&2
echo "" >&2

# Surface unknown_keys / UNKNOWN ELEMENT KIND lines from the manifest — these
# are the gaps in our extraction.
gaps=$(grep -E "⚠️|UNKNOWN" "$out_dir/manifest.md" | grep -v "_Manifest generated" || true)
if [ -n "$gaps" ]; then
  echo "GAPS DETECTED (fields/kinds the manifest schema doesn't recognize yet):" >&2
  echo "$gaps" | sed 's/^/  /' >&2
else
  echo "No gaps — manifest fully recognized every field." >&2
fi
