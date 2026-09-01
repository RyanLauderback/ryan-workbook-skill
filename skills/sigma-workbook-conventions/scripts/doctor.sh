#!/usr/bin/env bash
# Diagnose whether this environment can run the skill's scripts.
#
# Usage:  bash doctor.sh   (run from wherever this script lives — this repo's
#         skills/sigma-workbook-conventions/scripts/, or ${CLAUDE_PLUGIN_ROOT}/skills/sigma-workbook-conventions/scripts/
#         when installed as a plugin elsewhere)
#
# Checks required binaries, resolves the python/bash interpreters that
# would actually be used, reports the OS, and does a cheap auth-config
# sanity check (does NOT mint a token — see api/whoami.sh, alongside this
# script, for that). Run this first on an unfamiliar host before anything
# else in this directory or its api/ subfolder.
#
# This repo targets macOS, Linux, WSL, and Git Bash/MSYS2 on native
# Windows for this bash-based scripts/api/ layer (the pure-Python tools —
# validate-spec.py, workbook-manifest.py, sigma-resolve.py,
# sync-cortex-mirror.py — also run under a native Windows `python`/`py -3`
# with no bash at all). See docs/conventions.md -> "Platform support".

set -uo pipefail  # not -e: we want to keep checking after a failure

# Resolve relative to THIS script's own location, not cwd — doctor.sh may be
# invoked from this repo's skills/sigma-workbook-conventions/scripts/ or from
# a plugin install's ${CLAUDE_PLUGIN_ROOT}/skills/sigma-workbook-conventions/scripts/, so any advice we print
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
  MINGW*|MSYS*|CYGWIN*)
    # Git Bash (Git for Windows) and MSYS2 report uname -s as
    # MINGW64_NT-..., MSYS_NT-..., or CYGWIN_NT-... depending on the
    # environment. This is a fully recognized, supported host for the
    # scripts/api/*.sh bash layer (see docs/conventions.md -> "Platform
    # support") -- not the generic "unrecognized platform" case below.
    ok "Windows via Git Bash/MSYS ($(uname -s))" ;;
  *) warn "Unrecognized uname -s: $(uname -s) — this repo targets macOS/Linux/WSL/Git Bash." ;;
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
  # SIGMA_PYTHON: same shim as scripts/api/_env.sh's -- doctor.sh doesn't
  # source _env.sh (it's meant to run standalone, first, before anything
  # else), so resolve it locally for the actual invocations below.
  SIGMA_PYTHON="${SIGMA_PYTHON:-$(command -v python3)}"
  ok "python3 -> $("$SIGMA_PYTHON" --version 2>&1)"
  if "$SIGMA_PYTHON" -c "import yaml" 2>/dev/null; then
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

# Egress preflight -- Claude Cowork runs shell commands behind a forward
# proxy with an org-controlled domain allowlist; a blocked host fails
# closed with 403 + `X-Proxy-Error: blocked-by-allowlist` (confirmed live in
# a real Cowork session — see reference/workflows/cowork.md). Catching that
# signature here turns a mid-build mystery 403 into a first-10-seconds
# actionable message. Skipped entirely (no false failure) when
# SIGMA_BASE_URL isn't set -- that's already covered by the warn above.
if [ -n "${SIGMA_BASE_URL:-}" ]; then
  echo ""
  echo "== Network egress =="
  _doctor_egress=$(curl -sS -m 10 -D - -o /dev/null "$SIGMA_BASE_URL" 2>&1)
  _doctor_egress_rc=$?
  if [ "$_doctor_egress_rc" -ne 0 ]; then
    bad "Could not reach $SIGMA_BASE_URL (curl exit $_doctor_egress_rc) — looks like a host-unreachable/DNS/firewall problem, not Cowork's allowlist (that fails with a 403 response, not a connection error). Check connectivity/DNS/proxy settings."
  else
    _doctor_status=$(printf '%s' "$_doctor_egress" | awk 'NR==1{print $2}' | tr -d '\r')
    if [ "$_doctor_status" = "403" ] && printf '%s' "$_doctor_egress" | tr -d '\r' | grep -qi '^x-proxy-error:[[:space:]]*blocked-by-allowlist'; then
      bad "Network egress to $SIGMA_BASE_URL is blocked by Cowork's org-level allowlist (403, X-Proxy-Error: blocked-by-allowlist). A Team/Enterprise org Owner must add this host in Admin settings → Capabilities. See reference/workflows/cowork.md for the full host list."
    else
      ok "Reached $SIGMA_BASE_URL (HTTP $_doctor_status)"
    fi
  fi
  unset _doctor_egress _doctor_egress_rc _doctor_status
fi

if [ "$fail" -eq 0 ]; then
  echo ""
  echo "All required checks passed. Try: bash \"$script_dir/api/whoami.sh\""
else
  echo ""
  echo "One or more required checks failed — fix those before running any script under $script_dir/api/."
fi
exit "$fail"
