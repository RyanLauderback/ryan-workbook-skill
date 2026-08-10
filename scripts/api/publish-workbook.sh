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

# jq parses the POST/PUT response to decide whether to run the post-publish
# audit gate (run_audit, below). Without this preflight, a missing jq made
# that decision fail silently — wb_id came back empty and the audit just
# never ran, with no error at all. verify-workbook.sh and
# audit-workbook-schema.sh already check for jq; this brings publish-workbook.sh
# in line with them.
if ! command -v jq >/dev/null 2>&1; then
  echo "publish-workbook: jq is required (used to parse POST/PUT responses" >&2
  echo "  and decide whether to run the post-publish audit gate)." >&2
  exit 1
fi

# Sigma's live POST/PUT wire format (confirmed 2026-08-04 via direct testing,
# independent of and following up on a build-mode session's report) nests
# schemaVersion/kind/pages/layout/themeOverrides/folders/agents under a
# top-level "document" key -- only name/folderId/description stay top-level
# siblings, e.g.:
#   {"name":"...", "folderId":"...", "document":{"schemaVersion":1,"kind":"workbook","pages":[...],"layout":"..."}}
# This skill's tooling (validate-spec.py, workbook-manifest.py, every example
# in examples/) authors and validates the FLAT shape (schemaVersion/pages/
# layout as top-level siblings) -- POSTing that flat shape as-is is rejected
# with a large union-type validation error naming paths like
# "0.document.0.0.0", which reads like unrelated schema drift rather than
# "wrap this in a document key". `document.kind` is REQUIRED and always
# "workbook" -- since no example or prior spec in this repo ever set a
# top-level `kind` field (it was previously response-only metadata), the
# wrap defaults it to "workbook" rather than requiring every caller to add it.
#
# Rather than push this wrapping requirement onto every caller/example/
# validator, these helpers wrap flat -> wire shape on POST/PUT and unwrap
# wire -> flat on GET, so the flat shape stays the one stable authoring
# convention everywhere else in the skill. See reference/specification/
# schema.md and reference/history.md -> "2026-08-04 -- document wrapper"
# for the full incident and verification trail.
#
# NOTE on response format: a build-mode session separately reported that
# successful POST/PUT responses come back as plain "key: value" text, not
# JSON, and patched jq-based parsing to fall back to text scanning. Verified
# 2026-08-04 that this is NOT the case via this skill's actual sigma_curl
# path -- sigma_curl already sends `Accept: application/json` (see _env.sh),
# and Sigma's API honors it for both GET and POST/PUT responses; the
# plain-text response only appears when that header is omitted (e.g. a raw
# curl call made outside sigma_curl during ad-hoc bisection). No dual-format
# response parsing was added here — the existing jq-based parsing already
# works correctly through the real script path.
wrap_flat_to_wire() {
  # $1 = path to a flat-shape spec file, $2 = path to write the wire-shape
  # JSON to. Writes to a file (not stdout captured into a shell variable) so
  # `--data-binary "@<file>"` avoids ARG_MAX limits on large specs, matching
  # the existing @-file pattern below. Passes through unchanged if the input
  # already has a top-level "document" key.
  python3 -c '
import json, sys
spec = json.load(open(sys.argv[1]))
if "document" in spec:
    json.dump(spec, open(sys.argv[2], "w"))
    sys.exit(0)
TOP_KEYS = ("name", "folderId", "description")
# "elements"/"overlays"/"settings" added 2026-08-10, "themeOverrides"
# removed: the live API now rejects several previously-valid top-level
# document shapes outright -- pages[].elements ("Move elements to
# document.elements instead"), a per-page type:"modal" page ("modals
# now live in document.overlays[]"), and document.themeOverrides ("Use
# document.settings.theme.overrides instead"). See reference/history.md
# -> "2026-08-10 -- document.elements flattening" for the full incident.
DOC_KEYS = ("schemaVersion", "kind", "pages", "layout", "settings", "folders", "agents", "elements", "overlays")
top = {k: spec[k] for k in TOP_KEYS if spec.get(k) is not None}
doc = {k: spec[k] for k in DOC_KEYS if spec.get(k) is not None}
doc.setdefault("kind", "workbook")
top["document"] = doc
json.dump(top, open(sys.argv[2], "w"))
' "$1" "$2"
}

unwrap_wire_to_flat() {
  # Reads wire-shape JSON on stdin (a GET /v2/workbooks/{id}/spec response).
  # Prints the flat shape on stdout: document's keys hoisted to the top
  # level, alongside the response-only fields (workbookId, url, etc.)
  # unchanged. Passes through unchanged if there's no top-level "document" key.
  #
  # Must take the script as an argv-passed -c string, NOT a heredoc on stdin
  # (`python3 - <<'PY' ... PY`) -- the heredoc form makes the heredoc content
  # itself python's stdin (the script source), leaving nothing for the piped
  # response body to land on when the script then tries to read sys.stdin.
  python3 -c '
import json, sys
d = json.load(sys.stdin)
doc = d.pop("document", None)
if isinstance(doc, dict):
    d.update(doc)
print(json.dumps(d, indent=2))
'
}

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
    #
    # `response=$(sigma_curl ...)` is a plain assignment from a command
    # substitution — under `set -e`, sigma_curl returning non-zero (any
    # HTTP >=400) makes THIS LINE ITSELF the failing command, and the
    # script exits immediately, before the `echo "$response"` below ever
    # runs. sigma_curl still prints the error body into $response, but it
    # was silently discarded — a failed POST reported nothing about why.
    # Bug found 2026-08-03 via a live Wave 1 probe. Fix: suspend `set -e`
    # around the call so the echo always runs, then propagate the real
    # exit code afterward.
    wire_file="$(mktemp "${TMPDIR:-/tmp}/publish-wire.XXXXXX")"
    trap 'rm -f "$wire_file"' EXIT
    wrap_flat_to_wire "$spec" "$wire_file"
    set +e
    response=$(sigma_curl -X POST \
      -H "Content-Type: application/json" \
      --data-binary "@$wire_file" \
      "$SIGMA_BASE_URL/v2/workbooks/spec")
    post_exit=$?
    set -e
    echo "$response"
    if [ "$post_exit" -ne 0 ]; then
      exit "$post_exit"
    fi
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
    # See the matching comment in the `post` case above — set +e around
    # the capture so a failed PUT's error body still gets echoed before
    # the script exits, instead of set -e silently discarding it.
    wire_file="$(mktemp "${TMPDIR:-/tmp}/publish-wire.XXXXXX")"
    trap 'rm -f "$wire_file"' EXIT
    wrap_flat_to_wire "$spec" "$wire_file"
    set +e
    response=$(sigma_curl -X PUT \
      -H "Content-Type: application/json" \
      --data-binary "@$wire_file" \
      "$SIGMA_BASE_URL/v2/workbooks/$wb_id/spec")
    put_exit=$?
    set -e
    echo "$response"
    if [ "$put_exit" -ne 0 ]; then
      exit "$put_exit"
    fi
    # PUT response echoes the workbookId back; if the caller passed a
    # bogus id and PUT returned an error, skip the audit.
    if echo "$response" | jq -e '.success == true' >/dev/null 2>&1; then
      run_audit "$wb_id"
    fi
    ;;
  get-spec)
    wb_id="${2:?usage: publish-workbook.sh get-spec <workbook-id>}"
    sigma_curl "$SIGMA_BASE_URL/v2/workbooks/$wb_id/spec" | unwrap_wire_to_flat
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
