# Workbook Spec CRUD

POST / GET / PUT against `/v2/workbooks/spec`. Load this when creating,
retrieving, or updating a workbook.

The endpoints are straightforward; the value is calling out the
**non-obvious behaviors**: PUT being full-replacement, response-only
fields returned by GET, and how ryan's `publish-workbook.sh` wrapper
layers validation + auth on top of curl. IDs you send on POST are
preserved verbatim — see the "ID preservation" section below.

## OpenAPI reference

```bash
curl -sf https://help.sigmacomputing.com/openapi/sigma-computing-public-rest-api.json > /tmp/sigma-api.json
jq '.paths."/v2/workbooks/spec".post, .paths."/v2/workbooks/{workbookId}/spec".get, .paths."/v2/workbooks/{workbookId}/spec".put' /tmp/sigma-api.json
```

## The ryan wrapper — `publish-workbook.sh`

Prefer this over direct curl for POST / GET / metadata:

```bash
scripts/api/publish-workbook.sh post     workbooks/<name>/spec.json   # POST (auto-validates first)
scripts/api/publish-workbook.sh get-spec <workbookId> > workbooks/<name>/spec.json
scripts/api/publish-workbook.sh get-meta <workbookId>                 # url, name, path, folderId
```

The wrapper:
- Sources `_env.sh` for auth (caches OAuth token at `/tmp/.sigma_token`)
- Runs `scripts/validate-spec.py` before POST (fails fast on the
  passthrough-coverage and controlid-collision gotchas)
- Uses `sigma_curl` for auth-injected, 401-retrying requests
- Reports the HTTP status alongside the body

**No `delete` subcommand** — DELETE goes via direct curl on purpose so
it triggers the `ask` pattern in `.claude/settings.json`. See
`reference/workflows/plan.md` → "Approval model" for the rationale.

## PUT — use the wrapper

```bash
scripts/api/publish-workbook.sh put <workbook-id> workbooks/<name>/spec.json
```

Validates first (fail-fast), then PUTs via `sigma_curl` (auth-injected,
401-retrying). Same shape as `post` plus the workbook id. Strip the
response-only fields from a GET-back first — see "Response-only fields to
strip on PUT" below.

## DELETE — direct curl (intentional)

```bash
curl -sS -X DELETE -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  "$SIGMA_BASE_URL/v2/workbooks/<workbook-id>"
```

DELETE stays on the direct-curl path so it hits the `ask` pattern in
`.claude/settings.json` (`Bash(curl * -X DELETE *)`). Any deletion wrapper
must be named `scripts/api/delete-*` so the corresponding `ask` rule
catches it — see `reference/workflows/plan.md` → "Approval model."

The API accepts both `application/json` and `application/yaml`. This
skill's exemplars are JSON for tooling consistency with
`validate-spec.py` and `workbook-manifest.py`, but YAML POSTs work
identically. Use `--data-binary @file` (NOT `-d @file`) — `-d` strips
newlines and breaks multi-line specs.

## Required fields on CREATE

The POST body must include:

- `name` (string)
- `folderId` (string — usually the user's `homeFolderId` or a folder
  resolved via `scripts/sigma-resolve.py`)
- `schemaVersion` (number — see below)
- `pages` (array — at least one page with at least one element)

Optional: `description`, `layout` (top-level layout XML).

### schemaVersion — don't hardcode

Sigma's `schemaVersion` evolves. Hardcoding `1` works today (every
canonical exemplar in `examples/` uses `1`) but is brittle. The
official skill recommends reading the value back from a recent
reference GET:

```bash
scripts/api/publish-workbook.sh get-spec <reference-workbook-id> \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['schemaVersion'])"
```

When the server rejects a spec for `schemaVersion mismatch`, pull
the current value from any working workbook and use it.

## Response-only fields to strip on PUT

`GET /v2/workbooks/<id>/spec` returns extra server-managed fields.
When you take a GET response and PUT it back (the standard iteration
flow), strip these before submitting:

- `workbookId`
- `url`
- `documentVersion`
- `latestDocumentVersion`
- `ownerId`
- `createdBy`
- `updatedBy`
- `createdAt`
- `updatedAt`

`workbook-manifest.py` recognizes these as response-only and won't
flag them as unknown keys.

## ID preservation on CREATE

The `id` values you send in `POST /v2/workbooks/spec` — for pages,
elements, columns — are **preserved verbatim**. Layout `elementId`
references stay valid across POST/PUT. You can save the spec, edit
it, and `PUT` it back directly using the same IDs.

Verified 2026-07-02 against skill-authored workbooks: kebab-case IDs
(`page-overview`, `tbl-transactions-master`, `k1-value`) survived
POST → GET round-trip unchanged in every harvested exemplar.

Layout `elementId` references still need to match the actual element
`id` on that page (case-sensitive). A mismatch silently drops the
element from the page — but the mismatch comes from typos, not
server-side remapping.

The canonical iteration pattern:

```bash
# 1. Edit workbooks/<name>/spec.json on disk (using your original IDs)

# 2. Validate
scripts/validate-spec.py workbooks/<name>/spec.json

# 3. PUT (uses the wrapper for validation + auth)
scripts/api/publish-workbook.sh put <wb-id> workbooks/<name>/spec.json

# 4. Verify
scripts/api/verify-workbook.sh <wb-id>
```

If you're editing a GET-back spec (rather than your own saved
version), strip the response-only fields first — see the section
above.

## Persisting the spec

This skill's convention is one folder per workbook under `workbooks/`:

```
workbooks/<name>/
├── spec.json           # latest spec (overwritten each GET-back)
├── prompts/            # one .md per session
│   └── 2026-05-21T22-30-00.md
├── iterations/         # archive of attempts
│   └── 2026-05-21T22-30-00.json
└── notes.md            # ad-hoc observations
```

After CREATE, immediately `get-spec` and overwrite `spec.json` with
the server's IDs. This avoids the "old external IDs" trap on the
next PUT. The official skill's `/tmp/workbook-spec-<id>.yaml`
convention is an alternative when you don't want repo state; this
skill's per-workbook folder is preferred for iteration audit trails.

## Common errors

| Error | Cause | Fix |
|---|---|---|
| `401 Unauthorized` | Token missing or expired | Delete `/tmp/.sigma_token`, re-run any `scripts/api/*.sh` to re-fetch |
| `403 Forbidden` on POST | Credential can't create in this folder | Ask user's Sigma admin to check folder permissions |
| `schemaVersion mismatch` | Hardcoded `1` against a newer API | Read `schemaVersion` from a reference GET, use that value |
| `Invalid kind: pages[0].elements[N], got "..."` | Inner element shape mismatch (NOT kind unsupported) | See `reference/workflows/validate.md` → "Decoding cryptic errors" |
| Body returned as `service_error` 500 | UI feature in workbook can't serialize | See `reference/scope-and-edge-cases.md` → "GET-spec can 500 when UI features aren't representable" |

## Schema drift — when this skill goes stale

If a POST/PUT fails with `invalid argument`, `unknown field`,
`unexpected property`, `missing required field`, `unrecognized
parameter`, or a 400 about request *shape* rather than data — the API
has evolved since this skill was written. Apply the bounded fallback:

1. **Tell the user.** Print:

   > ⚠️ This error looks like a schema mismatch between this skill
   > and the current Sigma API. The skill may be out of date —
   > consider updating it. I'll consult the live OpenAPI in the
   > meantime.

2. **Fetch the current OpenAPI** (see top of this file).
3. **Diff** the live schema vs. what the skill assumed — renamed
   fields, new required fields, removed fields, type changes.
4. **One automated retry** with the corrected shape. If it succeeds,
   tell the user exactly what changed.
5. **Do not loop.** One retry, then stop. Surface the diff and let
   the user decide.

When the OpenAPI and this skill disagree, the OpenAPI wins.
