#!/usr/bin/env bash
# Validate Sigma auth end-to-end. Used by the build-mode kickoff to confirm the
# OAuth token actually works against the live API — not just that _env.sh
# bootstrapped successfully. Fails loud when credentials are wrong, the
# SIGMA_BASE_URL region is mismatched, or the API user lacks permissions.
#
# Why probe /v2/files (not /v2/members):
#   /v2/members is admin-only — non-admin tokens would 403 here even when
#   they're perfectly valid for workbook authoring. /v2/files works for any
#   user role and returns content the user can confirm visually ("yes, that's
#   my org's data").
#
# Usage:  scripts/api/whoami.sh
# Output: one-line auth confirmation + up to 5 recent files accessible to the
#         authenticated account.
# Exit:   0 on 2xx; 1 on non-2xx (sigma_curl surfaces the error body).
set -euo pipefail
source "$(dirname "$0")/_env.sh"

_resp=$(sigma_curl "$SIGMA_BASE_URL/v2/files?limit=5") || {
  echo "" >&2
  echo "Auth check failed. _env.sh fetched a token but /v2/files rejected it." >&2
  echo "Common causes: wrong SIGMA_BASE_URL region, revoked OAuth client," >&2
  echo "expired credentials, or insufficient permissions on the API user." >&2
  exit 1
}

_org=$(echo "$SIGMA_BASE_URL" | sed -E 's#^https?://([^/]+).*#\1#')
echo "Authenticated to $_org."
echo "Recent files accessible to this account (up to 5):"
echo "$_resp" | python3 -c '
import sys, json
d = json.load(sys.stdin)
entries = d.get("entries", [])[:5]
if not entries:
    print("  (no files visible — token is valid but the account has no accessible content)")
for e in entries:
    name = e.get("name", "<unnamed>")
    kind = e.get("type", "?")
    path = e.get("path", "")
    print(f"  - {name[:48]:<48s} [{kind:<10s}] {path}")
'
