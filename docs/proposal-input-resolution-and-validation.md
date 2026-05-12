# Proposal: Input Resolution & Spec Validation

**Status:** approved (2026-05-11), implementing in same change.

## Background

Two failure modes observed during the FUN.BIKES viz-catalog session:

1. **Source-ID friction.** User gave `BIKES-2jPgY5cxsfNZeeMcD2WLgi` (a schema-page URL slug). The skill had no resolver for it — agent burned six iterations probing `GET /v2/dataModels/`, `GET /v2/connections/{id}/schemas`, paginated `connections/paths`, and incorrect lookup paths before the user clarified "Sigma Sample DB, FUN.BIKES schema." Compounded by: `connections/paths` `connectionId` query param is silently ignored; pagination is alphabetical by connectionId; no documented "list children of a schema scope" endpoint; no documented "Sigma URL → API id" reverse lookup.

2. **Silent layout drop.** Agent placed `layout` under each `pages[i]` per a misread of the skill reference. POST returned 200; Sigma quietly stored only a single top-level auto-generated layout that stacked every element in a 1/13-wide single column with empty containers above. No validation error.

Target UX: user supplies sources + target as URLs, slugs, or prose (mixed), and the skill resolves everything without exposing endpoint-level confusion. Never asks "which API?" — only asks "did you mean A or B?" with concrete names.

## Changes

### 1. Thin API primitives — `scripts/api/`

Bash one-purpose wrappers around Sigma REST endpoints. The skill (and the main resolver) compose these instead of writing curl. Each reads `SIGMA_BASE_URL` and `SIGMA_API_TOKEN` from env, prints JSON to stdout, errors to stderr.

| Script | Wraps | Returns |
|---|---|---|
| `list-connections.sh` | `GET /v2/connections` | `[{connectionId, name, type}]` |
| `list-folders.sh [--name PATTERN]` | `GET /v2/files?typeFilters=folder` (paginated) + grep | `[{id, urlId, name, path}]` |
| `lookup-path.sh <connId> <p1> <p2> [<p3>]` | `POST /v2/connection/{id}/lookup` | `{kind, inodeId, url, path}` or `{error}` |
| `list-table-columns.sh <inodeId>` | `GET /v2/connections/tables/{id}/columns` | columns array |
| `find-file-by-urlid.sh <urlId>` | `GET /v2/files` paginated, match | matching file metadata |
| `probe-schema-tables.sh <connId> <db> <schema> [names...]` | parallel `lookup-path` against default name list | found tables with inodeIds |

### 2. Main resolver — `scripts/sigma-resolve.py <freetext>`

Single entry the skill calls first. Accepts mixed input:

- Sigma URLs: `/workbook/<urlId>`, `/b/<urlId>`, `/t/<urlId>`, `/s/<urlId>`, bare-slug folder URL
- URL-slug fragments: `BIKES-<urlId>`, `Claude-Testing-<urlId>`
- Prose: `"the sigma sample connection, FUN.BIKES schema, claude testing folder"`
- Any mix of the above in one string

Internal flow:

1. Regex-extract URLs and `<Name>-<urlId>` slug pairs.
2. For `/s/<id>` and `/t/<id>` URLs — schema/table urlIds are *not reversible* via the public API. Captured as `unresolved` unless prose hints (db + schema names) let us resolve via `lookup-path`.
3. For bare-slug URLs (`/<org>/<Name>-<urlId>`) — try `find-file-by-urlid.sh` first (folders/datasets); if no hit, fall through to schema/table resolution using the slug's name part.
4. Prose hint extraction: `"X db"`, `"X schema"`, `"X folder"`, `"X connection"`.
5. Compose: fuzzy-match connection name, resolve `(db, schema)` via `lookup-path`, probe tables via `probe-schema-tables.sh`, list columns.
6. Output JSON: `{"sources": [...], "folder": {...}|null, "candidates": {...}, "unresolved": [...], "hints": {...}}`. Populated `candidates` = agent asks user to pick (with names, not raw IDs).

### 3. SKILL.md — new "Input resolution" workflow section

Goes above the existing plan-first workflow. Tells the agent:

```
1. Always run `scripts/sigma-resolve.py <user-prompt>` first.
2. If sources + folder fully resolved → write the plan with concrete (connection, path, folder UUID) values.
3. If candidates returned → ask user to pick, using names not IDs.
4. Never run raw curl during resolution — sigma-resolve.py is the contract.
5. Never surface endpoint-level errors ("HTTP 400", "Unknown connection object") to the user.
```

### 4. `reference/workbook-spec-api.md` — layout rules callout

Promoted to top of file:

> **Layout rules — read before authoring multi-page**
>
> 1. `layout` is a **top-level workbook field**. `pages[].layout` is silently discarded by the API (verified 2026-05-11).
> 2. Multi-page = one `<?xml>` declaration + multiple `<Page>` siblings under it. No outer wrapper element.
> 3. Container children **must be nested inside `<GridContainer>`** in the XML. `pages[].elements` array order does NOT define visual structure. A flat layout with empty `<GridContainer>` tags stacks every element in a 1/13-wide single column.

### 5. Pre-POST validator — `scripts/validate-spec.py <spec.json>`

Static checks (no API calls):

- `pages[].layout` is present anywhere → error (silently dropped by API).
- Every `pages[].elements[].id` appears at least once in the top-level layout XML.
- Every `container`-kind element has a matching `<GridContainer elementId=...>` with at least one nested child.
- No `format` field on any column.
- `controlId` is unique workbook-wide.

Exits non-zero on any failure. Skill workflow runs this before any POST/PUT.

## Out of scope (not implementing)

- **Post-POST GET-back diff.** Mentioned in v1 retro; skipped per user — overkill once the validator catches the structural issues that cause silent rewrites.
- **Reverse url-id → path lookup for `/s/` and `/t/` URLs.** Sigma's public API doesn't support this; the resolver captures these as `unresolved` and asks for the path hint.

## Files

New:
- `scripts/api/list-connections.sh`
- `scripts/api/list-folders.sh`
- `scripts/api/lookup-path.sh`
- `scripts/api/list-table-columns.sh`
- `scripts/api/find-file-by-urlid.sh`
- `scripts/api/probe-schema-tables.sh`
- `scripts/sigma-resolve.py`
- `scripts/validate-spec.py`
- `docs/proposal-input-resolution-and-validation.md` (this file)

Modified:
- `.claude/skills/sigma-workbook-conventions/SKILL.md` — adds "Input resolution" section
- `.claude/skills/sigma-workbook-conventions/reference/workbook-spec-api.md` — adds layout rules callout
