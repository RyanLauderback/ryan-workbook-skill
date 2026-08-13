#!/usr/bin/env bash
# Diagnose whether this environment can run the skill's scripts.
#
# Usage:  bash doctor.sh   (run from wherever this script lives — this repo's
#         skills/sigma-workbook-conventions/scripts/, or ${CLAUDE_PLUGIN_ROOT}/scripts/
#         when installed as a plugin elsewhere)
#
# Checks required binaries, resolves the python/bash interpreters that
# would actually be used, reports the OS, and does a cheap auth-config
# sanity check (does NOT mint a token — see api/whoami.sh, alongside this
# script, for that). Run this first on an unfamiliar host before anything
# else in this directory or its api/ subfolder.
#
# This repo currently targets macOS, Linux, and WSL. Native Windows
# (outside WSL) is not supported — see docs/conventions.md.

set -uo pipefail  # not -e: we want to keep checking after a failure

# Resolve relative to THIS script's own location, not cwd — doctor.sh may be
# invoked from this repo's skills/sigma-workbook-conventions/scripts/ or from
# a plugin install's ${CLAUDE_PLUGIN_ROOT}/scripts/, so any advice we print
# below must point at a path that's correct in either context.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fail=0

ok()   { printf "  [ok]   %s\n" "$1"; }
warn() { printf "  [warn] %s\n" "$1"; }
bad()  { printf "  [FAIL] %s\n" "$1"; fail=1; }

echo "== OS =="
case "$(uname -s)" in
  Darwin) ok "macOS ($(uname -r))" ;;
  Linux)
    if grep -qi microsoft /proc/version 2>/dev/null; then
      ok "Linux under WSL ($(uname -r))"
    else
      ok "Linux ($(uname -r))"
    fi
    ;;
  *) warn "Unrecognized uname -s: $(uname -s) — this repo targets macOS/Linux/WSL only." ;;
esac

echo ""
echo "== Required binaries =="
for b in bash curl python3 git; do
  if command -v "$b" >/dev/null 2>&1; then
    ok "$b -> $(command -v "$b")"
  else
    bad "$b not found on PATH"
  fi
done

echo ""
echo "== Recommended binaries (checks degrade without these) =="
for b in jq yq openssl; do
  if command -v "$b" >/dev/null 2>&1; then
    ok "$b -> $(command -v "$b")"
  else
    case "$b" in
      jq) warn "jq not found — required for publish-workbook.sh/verify-workbook.sh/audit-workbook-schema.sh" ;;
      yq) warn "yq not found — only needed for YAML spec input to validate-spec.py (PyYAML also works)" ;;
      openssl) warn "openssl not found — only needed for browser-login.sh's PKCE step; not required for the client_credentials path (e.g. Claude Code web)" ;;
    esac
  fi
done

echo ""
echo "== Python =="
if command -v python3 >/dev/null 2>&1; then
  ok "python3 -> $(python3 --version 2>&1)"
  if python3 -c "import yaml" 2>/dev/null; then
    ok "PyYAML available"
  else
    warn "PyYAML not installed — validate-spec.py/workbook-manifest.py fall back to yq for YAML input"
  fi
else
  bad "python3 not found — see 'Required binaries' above"
fi

echo ""
echo "== Repo-relative paths (should not depend on cwd) =="
if [ -n "${SIGMA_API_TOKEN:-}" ] && [ -n "${SIGMA_BASE_URL:-}" ]; then
  ok "SIGMA_BASE_URL/SIGMA_API_TOKEN already exported (browser-login.sh, refresh-token.sh, or Claude Code web)"
elif [ -n "${SIGMA_BASE_URL:-}" ]; then
  ok "SIGMA_BASE_URL exported, no token yet — run 'eval \"\$(\"$script_dir\"/api/browser-login.sh)\"' to sign in"
else
  warn "SIGMA_* not exported — run 'eval \"\$(\"$script_dir\"/api/browser-login.sh)\"' to sign in (no admin-provisioned credential needed; Claude Code web sets SIGMA_CLIENT_ID/SIGMA_CLIENT_SECRET/SIGMA_BASE_URL automatically — nothing to configure there)"
fi

if [ "$fail" -eq 0 ]; then
  echo ""
  echo "All required checks passed. Try: bash \"$script_dir/api/whoami.sh\""
else
  echo ""
  echo "One or more required checks failed — fix those before running any script under $script_dir/api/."
fi
exit "$fail"
