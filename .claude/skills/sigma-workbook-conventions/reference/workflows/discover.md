# Source Discovery

Finding connections, tables, columns, data models, metrics, and existing
workbooks via the Sigma REST API. Load before composing any new spec.

**MCP status (2026-08-12): MCP is the default discovery tool.** Sigma's
`/mcp/v2` endpoint requires a user-delegated OAuth token —
`client_credentials` tokens are categorically rejected, confirmed
directly by Sigma's MCP engineering team (2026-07-30, see
`reference/history.md` → "2026-08-07"). `scripts/api/browser-login.sh`
(interactive OAuth 2.1 + PKCE — see CLAUDE.md → "Authentication") is
this skill's only CLI-facing auth path and mints exactly the token type
`/mcp/v2` needs, so `mcp-search.sh` / `mcp-describe.sh` are the first
tools to reach for below — for workbooks, data models, *and* raw
warehouse tables.

**Confirmed live 2026-08-12** (real org, `Healthcare Claims Transactions`
data model): a `browser-login.sh`-authenticated session's
`mcp-search.sh`/`mcp-describe.sh` calls both succeeded end-to-end,
returning richer output than the REST fallback (DDL + metrics catalog in
one call). Getting there took two real bug fixes, both on
`oauth-token-exchange`:

- `67090eb` — `browser-login.sh` was discovering its OAuth scope solely
  from `GET /v2/whoami`'s challenge, which only advertises
  `scope="api:access"` — the REST API's own protected-resource metadata,
  not `/mcp/v2`'s. `/mcp/v2` is a *separate* protected resource requiring
  `scope="mcp:access"`, never requested, so the resulting token 403'd on
  every MCP call regardless of grant type — silently defeating the whole
  reason the script exists. Fixed by also probing `/mcp/v2` (POST, since
  it only challenges that way — GET just 405s) and unioning its scope
  into the authorize/registration request.
- `555e945` — once the token actually carried `mcp:access`, first real
  contact with the live `search` tool surfaced two more bugs in
  `mcp-search.sh`: it sent camelCase `entityTypes` (`dataModel`,
  `dataModelElement`) matching its own docs/defaults, but the live
  enum is kebab-case (`data-model`, `data-model-element`) — rejected
  with a validation error. And `data-model-element` results have no
  `name`/`dataModelId` keys (real keys are `elementTitle`/`inodeId`) —
  the existing normalizer assumed keys that don't exist on that result
  type. See "Known gap" below — this is what that note was actually
  describing, not an occasional server omission.

**REST primitives remain the documented fallback** —
`search-files.sh`, `lookup-path.sh`, `list-table-columns.sh`, and
`probe-schema-tables.sh` are all still fully described below, not
deleted, just no longer the first thing to reach for. If
`mcp-search.sh`/`mcp-describe.sh` exit 3, that's now a real signal
something's wrong, not an expected permanent condition — a stale or
wrong-scope cached token, or a genuine MCP-side outage. Fall back to the
REST primitives to keep discovery moving, but surface the exit 3 to the
user as unexpected rather than shrugging it off — see "When discovery
fails" below.

## Table of contents

- [Prefer data models over raw tables](#prefer-data-models-over-raw-tables)
- [The routing decision](#the-routing-decision)
- [Routing: raw warehouse tables](#routing-raw-warehouse-tables)
- [Discovery via MCP (default discovery path)](#discovery-via-mcp-default-discovery-path)
  - [Searching the workspace](#searching-the-workspace)
  - [Describing a resolved object](#describing-a-resolved-object)
  - [Discovering data-model metrics](#discovering-data-model-metrics)
- [Discovery via REST primitives (fallback)](#discovery-via-rest-primitives-fallback)
- [Path formats per warehouse](#path-formats-per-warehouse)
- [Resolving messy / mixed-input prompts](#resolving-messy--mixed-input-prompts)
- [Column names — friendly vs raw warehouse](#column-names--friendly-vs-raw-warehouse)
- [When discovery fails](#when-discovery-fails)

## Prefer data models over raw tables

When a data model plausibly covers the request, resolve to it instead of
a raw warehouse table — it carries information no raw table lookup will,
MCP or REST. `mcp-search.sh --types dataModel` → `mcp-describe.sh
datamodel-element <dm-id> <element-id>` returns friendly column names,
descriptions, and the full metrics catalog in one call. The REST
fallback, `GET /v2/dataModels/{id}/spec` (raw `curl`, self-bootstrapped
auth via `source scripts/api/_env.sh` — no dedicated wrapper script yet),
returns the same tree, just more verbose. Confirmed live via REST
(2026-08-07, a real 117-column, 28-metric data model, see
`reference/history.md`) and via MCP (2026-08-12, the `Healthcare Claims
Transactions` data model, see "MCP status" above) — both return that
full element/column/metric tree in a single call.

A raw warehouse table has no equivalent enrichment either way: even
resolved via `mcp-search.sh --types table` → `mcp-describe.sh table
<inode-id>` (see "Routing: raw warehouse tables" below), what comes back
is DDL-level — real warehouse column names/types, no friendly-name
mapping, no metrics (metrics only exist on data models). The REST
fallback for the same table, `list-table-columns.sh`, returns **only
raw warehouse column names** (`STORE_KEY`, not `Store Key`) — no
descriptions, no metrics either. This mirrors the existing rule in
`reference/specification/sources.md`: "If no data model fits, fall back
to `warehouse-table` — don't manufacture a model." Raise this at kickoff
(`SKILL.md` → Q2) rather than defaulting straight to table-level
discovery when a data model might fit.

> ⚠️ **Not independently verified — a 2026-08-11 build session reported
> `GET /v2/dataModels/{id}/spec` 500ing** (`service_error: Data model
> spec contains unsupported dataset source: <name>.csv`) **on a data
> model with a CSV-uploaded dataset source.** One data source type, one
> session — logged in `reference/capability-ledger.md` → "Unverified —
> probe pending," not asserted as a general recon-path failure. If you
> hit this on the REST fallback, `mcp-describe.sh datamodel-element`
> is a different code path that may not share the bug — worth trying,
> though untested against this specific CSV-source failure mode. If both
> fail: `GET /v2/dataModels/{id}/elements` + `GET
> /v2/dataModels/{id}/columns` return full column/type schema without
> hitting the broken serialization path — just not the `metrics`
> catalog, which only lives in `/spec`. That gap matters for the
> "Inference anchor" rule (`reference/conventions.md`) — a formula that
> would normally trace to a confirmed `[Metrics/<Name>]` has no
> `metrics` array to check against on this fallback, so treat any metric
> the user implies as an Open Decision instead of assuming it exists.

## The routing decision

What the user's prompt contains determines which discovery tool to reach
for first — MCP search, then describe the resolved id:

| Prompt contains | Use first |
|---|---|
| Names or topics ("the PLUGS data model", "find the sales workbook") | `scripts/api/mcp-search.sh "<query>" --types workbook,dataModel [--limit N]` — fallback: `search-files.sh` (see "Discovery via REST primitives" below) |
| Warehouse table name(s), schema/DB confirmed or not | `scripts/api/mcp-search.sh "<table-name>" --types table [--limit N]` — semantic search resolves it without needing a confirmed schema first; see "Routing: raw warehouse tables" below for what happens when it doesn't resolve cleanly |
| URL slugs (`/b/<id>`, `…-<urlId>`) | `scripts/api/find-file-by-urlid.sh <urlId>` — REST only, no MCP equivalent |
| `/s/<id>`/`/t/<id>` schema URLs, or messy/mixed prose | `scripts/sigma-resolve.py "<prompt-verbatim>"` — and if the schema still can't be resolved, ask the user rather than guessing (see below) |

After resolution, inspect the resolved id:
- **Data model**: `mcp-describe.sh datamodel-element <dm-id> <element-id>`
  (or `datamodel <dm-id>` for the element list first) — REST fallback:
  `GET /v2/dataModels/{id}/spec`, same information, more verbose.
- **Warehouse table**: `mcp-describe.sh table <inode-id>` — REST
  fallback, only once the schema/DB is confirmed: `lookup-path.sh` →
  `list-table-columns.sh` (raw warehouse column names — see "Column
  names — friendly vs raw warehouse" below).
- **Workbook**: `mcp-describe.sh workbook <wb-id>` — REST fallback:
  `scripts/api/publish-workbook.sh get-spec <wb-id>`.

If `mcp-search.sh`/`mcp-describe.sh` exit 3, that means something's
actually wrong (stale/wrong-scope token, or a genuine MCP outage — see
"MCP status" above), not that MCP is unavailable by design. Fall back to
the REST tools above to keep moving, but surface the exit 3 to the user
rather than silently treating it as routine.

## Routing: raw warehouse tables

**Confirmed live 2026-08-12** (see "MCP status" above): `mcp-search.sh
--types table` resolves a bare table name via semantic search across the
org, with no confirmed schema/DB needed first. Try this before anything
else:

```bash
scripts/api/mcp-search.sh "<table-name>" --types table --limit 10
```

- Confirm the match the same way as any MCP search result — surface
  ambiguous matches to the user rather than picking the top hit blind
  (see "Searching the workspace" below).
- Once resolved, `scripts/api/mcp-describe.sh table <inode-id>` returns
  DDL-level column info for it.

**If MCP search doesn't resolve the table with confidence** (ambiguous
matches, no match, or an exit 3), fall back to the REST 3-way split
below — this was the only option before MCP was available, and it's now
what happens after MCP doesn't resolve it:

Confirmed via live testing (2026-08-07, `reference/history.md`): there
is no REST "list tables in a schema" endpoint, and guessing names is
expensive. What matters for the REST fallback is whether the **schema is
confirmed**, not whether table names were given:

| Prompt gives | Do this | Cost (measured) |
|---|---|---|
| Table name(s) **and** confirmed schema/DB | `scripts/api/lookup-path.sh <connection-id> "<DB>.<SCHEMA>.<TABLE>"` per table → `scripts/api/list-table-columns.sh <inode-id>` | 2 calls/table, no guessing |
| Table name(s), schema/DB **not** confirmed | **Ask the user to confirm the schema/DB before attempting REST resolution.** Do not cascade into guessing sibling schemas. | One live test cascading through guessed schemas cost 29 calls chasing 2 tables — zero hits |
| Schema/DB only, no table names | `scripts/api/probe-schema-tables.sh <connection-id> "<DB>.<SCHEMA>"` — guessed-name probing, but bounded to one schema | 11 calls found 3/3 real tables in one live run |

The middle row is exactly why this REST fallback is worse than MCP
search: naming specific tables is **not** automatically cheaper than
schema-level probing under REST — it's only cheaper when the schema is
also right, and guessing the schema on top of guessing the table
compounds badly (worse than schema-only probing, not a shortcut).
`mcp-search.sh --types table` sidesteps this whole tradeoff by searching
instead of guessing, which is why it's the first thing to try — this
table only matters once MCP hasn't resolved the table with confidence.

## Discovery via MCP (default discovery path)

`scripts/api/mcp-search.sh` and `mcp-describe.sh` call Sigma's MCP
server (`/mcp/v2`) using the session's OAuth token. Since
`browser-login.sh` is this skill's only CLI-facing auth path and mints
the token type `/mcp/v2` requires, these succeed by default — reach for
them first for workbooks, data models, and raw warehouse tables alike.
See "MCP status" above.

### Searching the workspace

```bash
# Find a workbook by name
scripts/api/mcp-search.sh "Sales Performance" --types workbook --limit 5

# Find data models matching a topic
scripts/api/mcp-search.sh "transactions" --types dataModel --limit 10

# Find a raw warehouse table by name (no confirmed schema needed)
scripts/api/mcp-search.sh "ORDERS" --types table --limit 10

# Find all element kinds across a topic
scripts/api/mcp-search.sh "claims" --types workbook,dataModel,dataModelElement --limit 20
```

Rules:

- **MCP search is semantic / fuzzy** — it returns top matches even
  when relevance is low. Always confirm a match against the user's
  stated name/intent before building on it.
- Surface ambiguous matches: "I found two named 'Sales Performance'
  — A in `My Documents/Demo`, B in `Org Shared/Q4`. Which?"
- **Fixed 2026-08-12 (commit `555e945`), not a lingering gap:** results
  of type `data-model-element` were previously missing `name`/
  `dataModelId` on every match — not an occasional server omission as
  earlier phrasing here implied, but this script's normalizer assuming
  keys (`name`, `dataModelId`) that this result type never carries (the
  real keys are `elementTitle` and `inodeId`). `mcp-search.sh` now reads
  the correct keys, so `dataModelId` is populated on every
  `data-model-element` match — no separate resolve-the-data-model-first
  step needed to chain into `mcp-describe.sh datamodel-element`.
- **Entity-type casing:** the live `search` tool's enum is kebab-case
  (`data-model`, `data-model-element`), confirmed 2026-08-12. `--types`
  accepts either casing — camelCase (`dataModel`, `dataModelElement`,
  shown in the examples above) is translated automatically — but kebab-
  case is what the server actually speaks.

### Describing a resolved object

```bash
# Data model overview (lists elements)
scripts/api/mcp-describe.sh datamodel <dm-id>

# Data model element (returns columns, types, formulas, metrics catalog)
scripts/api/mcp-describe.sh datamodel-element <dm-id> <element-id>

# Workbook (lists pages + elements)
scripts/api/mcp-describe.sh workbook <wb-id>

# Workbook element (returns full element spec)
scripts/api/mcp-describe.sh workbook-element <wb-id> <element-id>

# Warehouse table (by inodeId — from mcp-search.sh --types table, or
# REST's lookup-path.sh)
scripts/api/mcp-describe.sh table <inode-id>
```

**Batch the describes after the first datamodel overview.** The flow:
one `mcp-describe.sh datamodel <id>` (sequential — you need its
output to know which element IDs exist), then **all subsequent
`mcp-describe.sh datamodel-element <dm> <el>` calls in a single
batch** (parallel Bash tool calls). Each element describe is
independent and Sigma's MCP server handles concurrent reads fine.
Don't interleave reasoning between describes — batch them, then
reason once over the combined output.

### Discovering data-model metrics

`mcp-describe.sh datamodel-element` returns a `metrics` array on the
element node, e.g.:

```json
{
  "metrics": [
    { "name": "Total Revenue", "formula": "Sum([Revenue])", "format": {...} },
    { "name": "Total Profit",  "formula": "Sum([Revenue]) - Sum([Cost])" },
    { "name": "AOV",            "formula": "Sum([Revenue]) / CountDistinct([Order ID])" }
  ]
}
```

Those metric names become the right-hand side of `[Metrics/<Name>]`
references in workbook formulas. See
`reference/specification/formulas.md` → "Data-model metrics
(`[Metrics/<Name>]`)" and `reference/conventions.md` →
"`[Metrics/<Name>]` resolution + DM-switch hard rule" for the
referencing rules.

**Always check metrics BEFORE writing a custom calc.** The metric
carries formatting, is the single source of truth, and survives
warehouse-column renames.

## Discovery via REST primitives (fallback)

Reach for these when `mcp-search.sh`/`mcp-describe.sh` exit 3 (see "MCP
status" above), or when there's no MCP equivalent at all
(`find-file-by-urlid.sh`'s URL-slug resolution has none).

```bash
# Find a workbook/data model/dataset by name or topic (substring match)
scripts/api/search-files.sh "<query>" --types workbook,data-model,dataset --limit 10

# List connections
scripts/api/list-connections.sh

# Resolve a warehouse path to inodeId (for column listing)
scripts/api/lookup-path.sh <connection-id> "<DB>.<SCHEMA>.<TABLE>"

# List columns on a warehouse table
scripts/api/list-table-columns.sh <inode-id>

# List folders matching a substring
scripts/api/list-folders.sh "<name-substring>"

# Probe a schema for table inventory
scripts/api/probe-schema-tables.sh <connection-id> "<DB>.<SCHEMA>"
```

These hit `/v2/files`, `/v2/connections`, `/v2/connection/<id>/lookup`,
`/v2/connections/tables/<inode>/columns`, etc. Auth is self-bootstrapped
via `_env.sh`. `search-files.sh` is exact substring match against name
+ description, not semantic — broaden the query rather than expecting
fuzzy/typo-tolerant matching, and it has no `dataModelElement`/table
result kind (it indexes files, not elements inside them — describe the
resolved data-model/workbook id to get to its elements). This is exactly
where MCP search wins: semantic matching across every element kind in
one call, instead of exact-substring file search plus a separate
describe step.

## Path formats per warehouse

| Warehouse | Path format |
|---|---|
| Snowflake | `["DATABASE", "SCHEMA", "TABLE"]` |
| BigQuery | `["PROJECT", "DATASET", "TABLE"]` |
| Databricks | `["CATALOG", "SCHEMA", "TABLE"]` |
| Redshift | `["SCHEMA", "TABLE"]` |
| PostgreSQL / MySQL | `["SCHEMA", "TABLE"]` |

A warehouse table's path must be exactly the depth its warehouse
uses. `lookup-path.sh` resolves ambiguity.

## Resolving messy / mixed-input prompts

When the prompt mixes URLs, warehouse paths, and names ("build a
workbook in /b/abc123 sourcing from PLUGS.PUBLIC.ORDERS"), use:

```bash
scripts/sigma-resolve.py "<prompt-verbatim>"
```

Returns structured JSON:

```json
{
  "sources":    [ {"kind": "warehouse-schema|warehouse-table|workbook|datamodel|folder|...", ...} ],
  "folder":     { "id", "urlId", "name", "path" } | null,
  "candidates": { "folder": [...], "sources": [...] },
  "unresolved": [ ... ],
  "hints":      { "db", "schema", "connection", "folder_name" }
}
```

When `candidates` is populated, surface names to the user; when
`unresolved` has warehouse-path entries, ask for the missing
`<DB>.<SCHEMA>` and connection name. The resolver handles `/s/<id>`
and `/t/<id>` schema URLs too — these are technically reachable via
`/v2/connections/paths` (`scripts/sigma-resolve.py`'s
`find_path_by_urlid`), but confirmed live (2026-08-07) that endpoint is
a full org-wide paginated enumeration — 4,225+ entries and still
paginating in one run, with an unthrottled retry hitting a 429. Not
viable for a single lookup. Ask the user for the warehouse path instead
of trying to reverse the slug.

## Column names — friendly vs raw warehouse

`GET /v2/connections/tables/{inodeId}/columns` returns **raw
warehouse names** (`DATE`, `V userId`, `UNIT_PRICE`). Formulas in
Sigma reference columns by their **friendly name** (`Date`,
`V User Id`, `Unit Price`).

Sigma normalizes:
- Casing — `ALL_CAPS_UNDERSCORE` → `All Caps Underscore`
- Special chars — `/`, `-`, `.`, brackets, leading/trailing
  whitespace get stripped or replaced
- Word boundaries — `camelCase` splits on case (`userId` →
  `User Id`)

Examples observed:

| Raw warehouse name | Friendly name in formulas |
|---|---|
| `DATE` | `Date` |
| `UNIT PRICE` | `Unit Price` |
| `ORDER_ID` | `Order ID` |
| `V userId` | `V User Id` |
| `Net/Gross` | `Net Gross` |

**Don't hand-transform** raw names. The friendly-name normalization
is more aggressive than it looks. Reliable workflow:

1. POST with your best guess (raw names often work for ALL_CAPS).
2. Run `scripts/api/verify-workbook.sh <wb-id>`.
3. If any element compiles to `'Unknown column "[X]"'`, GET the spec
   back — Sigma's readback shows the canonical friendly names.
4. Update formulas in your spec and re-PUT.

See `reference/specification/formulas.md` → "Raw vs. friendly names"
for the full rules.

## When discovery fails

- **`mcp-search.sh`/`mcp-describe.sh` exit 3**: this is now unexpected —
  every session authenticates via `browser-login.sh`, which mints a
  token that should carry `mcp:access` (see "MCP status" above). Don't
  just fall back silently: switch to the REST primitives above to keep
  discovery moving, but surface the exit 3 to the user as a real
  finding. Likely causes are a stale/wrong-scope cached token (try
  re-running `browser-login.sh`) or a genuine MCP-side outage — not an
  expected permanent condition.
- **`search-files.sh` returns nothing**: try a broader/shorter
  substring (it's exact substring match, not fuzzy — this is exactly
  the gap `mcp-search.sh`'s semantic matching covers, so try that first
  if you haven't), or switch to `find-file-by-urlid.sh` if you have a
  URL slug.
- **`mcp-describe` 404s on a known-good id**: the resource may require a
  different `kind` argument. Try `workbook` vs `workbook-element`,
  `datamodel` vs `datamodel-element`.
- **`/v2/connection/<id>/lookup` returns ambiguous results**: ask
  the user for the full database/schema path. Don't guess.
- **Schema URL slugs (`/s/<id>`, `/t/<id>`)**: technically reachable via
  `/v2/connections/paths`, but that's a full org-wide paginated
  enumeration (thousands of entries, real rate-limit risk) — not viable
  for a single lookup. Ask the user for `<DB>.<SCHEMA>` and the
  connection name instead of trying to reverse it.
- **`mcp-search.sh --types table` doesn't resolve a table with
  confidence** (ambiguous matches or no match): fall into the REST
  3-way split in "Routing: raw warehouse tables" above. Don't cascade
  into guessing sibling schemas on the REST fallback when the schema
  isn't confirmed — confirmed costly (29 calls, 0 hits in one live
  test). Ask the user for the schema/DB instead.

When in doubt, surface to the user. The plan's "Open decisions"
section is the right place to log discovery gaps.
