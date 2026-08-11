#!/usr/bin/env bash
# Diagnose whether this environment can run the skill's scripts.
#
# Usage:  bash scripts/doctor.sh
#
# Checks required binaries, resolves the python/bash interpreters that
# would actually be used, reports the OS, and does a cheap auth-config
# sanity check (does NOT mint a token — see scripts/api/whoami.sh for
# that). Run this first on an unfamiliar host before anything else in
# scripts/ or scripts/api/.
#
# This repo currently targets macOS, Linux, and WSL. Native Windows
# (outside WSL) is not supported — see docs/conventions.md.

set -uo pipefail  # not -e: we want to keep checking after a failure

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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
for b in jq yq; do
  if command -v "$b" >/dev/null 2>&1; then
    ok "$b -> $(command -v "$b")"
  else
    warn "$b not found — jq is required for publish-workbook.sh/verify-workbook.sh/audit-workbook-schema.sh; yq is only needed for YAML spec input to validate-spec.py (PyYAML also works)"
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
if [ -f "$repo_root/.env" ]; then
  ok ".env found at $repo_root/.env"
elif [ -n "${SIGMA_BASE_URL:-}" ] && [ -n "${SIGMA_API_TOKEN:-}" ]; then
  ok "no .env, but SIGMA_BASE_URL/SIGMA_API_TOKEN already exported (web/CI mode)"
else
  warn "no .env at $repo_root/.env and SIGMA_* not exported — copy .env.example to .env and fill in credentials"
fi

if [ "$fail" -eq 0 ]; then
  echo ""
  echo "All required checks passed. Try: bash scripts/api/whoami.sh"
else
  echo ""
  echo "One or more required checks failed — fix those before running any scripts/api/*.sh."
fi
exit "$fail"
