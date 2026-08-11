# Source Discovery

Finding connections, tables, columns, data models, metrics, and existing
workbooks via the Sigma REST API. Load before composing any new spec.

**MCP status (2026-08-07): not usable with this skill's auth model.**
This skill authenticates with a `client_credentials` API token (see
CLAUDE.md → "Authentication"). As of 2026-07-30, Sigma's `/mcp/v2`
endpoint only accepts interactive user OAuth — confirmed directly by
Sigma's MCP engineering team (see `reference/history.md` →
"2026-08-07"). `mcp-search.sh`/`mcp-describe.sh` will reliably exit 3 on
every call under this auth model; they are not flaky or occasionally
missing a scope, they are categorically blocked until Sigma ships
dedicated client-credentials MCP support (stated as "intended/in
progress," no ETA). **Use the REST tools below as the default, not a
fallback.** The MCP sections further down are kept for when that
changes, not for today's builds.

## Table of contents

- [Prefer data models over raw tables](#prefer-data-models-over-raw-tables)
- [The routing decision](#the-routing-decision)
- [Routing: raw warehouse tables](#routing-raw-warehouse-tables)
- [Discovery via MCP (blocked under client_credentials auth — kept for reference)](#discovery-via-mcp-blocked-under-clientcredentials-auth--kept-for-reference)
  - [Searching the workspace](#searching-the-workspace)
  - [Describing a resolved object](#describing-a-resolved-object)
  - [Discovering data-model metrics](#discovering-data-model-metrics)
- [Discovery via REST primitives (default, not a fallback)](#discovery-via-rest-primitives-default-not-a-fallback)
- [Path formats per warehouse](#path-formats-per-warehouse)
- [Resolving messy / mixed-input prompts](#resolving-messy--mixed-input-prompts)
- [Column names — friendly vs raw warehouse](#column-names--friendly-vs-raw-warehouse)
- [When discovery fails](#when-discovery-fails)

## Prefer data models over raw tables

When a data model plausibly covers the request, resolve to it instead of
a raw warehouse table — this is the seamless path today. Confirmed live
(2026-08-07, see `reference/history.md`): `GET /v2/dataModels/{id}/spec`
on a real 117-column, 28-metric data model returned friendly column
names, descriptions, and the full metrics catalog in **one** REST call —
full parity with what MCP's `describe` used to provide. The REST
equivalent for a raw warehouse table (`list-table-columns.sh`) returns
**only raw warehouse column names** (`STORE_KEY`, not `Store Key`) — no
descriptions, no metrics, and there is no MCP-based enrichment path left
to fill that gap (see "MCP status" above). This mirrors the existing
rule in `reference/specification/sources.md`: "If no data model fits,
fall back to `warehouse-table` — don't manufacture a model." Raise this
at kickoff (`SKILL.md` → Q2) rather than defaulting straight to
table-level discovery when a data model might fit.

## The routing decision

What the user's prompt contains determines which discovery tool to reach
for first:

| Prompt contains | Use first |
|---|---|
| Names or topics ("the PLUGS data model", "find the sales workbook") | `scripts/api/search-files.sh "<query>" [--types workbook,data-model,dataset] [--limit N]` |
| URL slugs (`/b/<id>`, `…-<urlId>`) | `scripts/api/find-file-by-urlid.sh <urlId>` |
| Warehouse table name(s) **with** schema/DB confirmed | See "Routing: raw warehouse tables" below — go straight to `lookup-path.sh`, skip probing. |
| Warehouse table name(s) **without** schema/DB, `/s/<id>`/`/t/<id>` schema URLs, or mixed prose | `scripts/sigma-resolve.py "<prompt-verbatim>"` — and if the schema still can't be resolved, ask the user rather than guessing (see below). |

After resolution, inspect the resolved id via REST:
- **Data model**: `GET /v2/dataModels/{id}/spec` (raw `curl`, self-bootstrapped
  auth via `source scripts/api/_env.sh` — no dedicated wrapper script yet).
  Returns the full JSON element/column/metric tree — more verbose than
  MCP's DDL text, same information.
- **Warehouse table** — only once the schema/DB is confirmed:
  `scripts/api/lookup-path.sh` → `scripts/api/list-table-columns.sh`
  (raw warehouse column names — see "Column names — friendly vs raw
  warehouse" below).
- **Workbook**: `scripts/api/publish-workbook.sh get-spec <wb-id>`.

`scripts/api/mcp-describe.sh` returns the same information as SQL DDL in
one call when it works, but expect exit 3 under this skill's auth model
(see the MCP status note above) — try it opportunistically, don't build
a plan step that depends on it succeeding.

## Routing: raw warehouse tables

Confirmed via live testing (2026-08-07, `reference/history.md`): there
is no REST "list tables in a schema" endpoint, and guessing names is
expensive. What matters is whether the **schema is confirmed**, not
whether table names were given:

| Prompt gives | Do this | Cost (measured) |
|---|---|---|
| Table name(s) **and** confirmed schema/DB | `scripts/api/lookup-path.sh <connection-id> "<DB>.<SCHEMA>.<TABLE>"` per table → `scripts/api/list-table-columns.sh <inode-id>` | 2 calls/table, no guessing |
| Table name(s), schema/DB **not** confirmed | **Ask the user to confirm the schema/DB before attempting resolution.** Do not cascade into guessing sibling schemas. | One live test cascading through guessed schemas cost 29 calls chasing 2 tables — zero hits |
| Schema/DB only, no table names | `scripts/api/probe-schema-tables.sh <connection-id> "<DB>.<SCHEMA>"` — guessed-name probing, but bounded to one schema | 11 calls found 3/3 real tables in one live run |

The middle row is the important one: naming specific tables is **not**
automatically cheaper than schema-level probing — it's only cheaper when
the schema is also right. Guessing the schema on top of guessing the
table compounds badly (worse than schema-only probing, not a shortcut).

## Discovery via MCP (blocked under client_credentials auth — kept for reference)

`scripts/api/mcp-search.sh` and `mcp-describe.sh` call Sigma's MCP
server (`/mcp/v2`) using the same OAuth token as the REST API.

### Searching the workspace

```bash
# Find a workbook by name
scripts/api/mcp-search.sh "Sales Performance" --types workbook --limit 5

# Find data models matching a topic
scripts/api/mcp-search.sh "transactions" --types dataModel --limit 10

# Find all element kinds across a topic
scripts/api/mcp-search.sh "claims" --types workbook,dataModel,dataModelElement --limit 20
```

Rules:

- **MCP search is semantic / fuzzy** — it returns top matches even
  when relevance is low. Always confirm a match against the user's
  stated name/intent before building on it.
- Surface ambiguous matches: "I found two named 'Sales Performance'
  — A in `My Documents/Demo`, B in `Org Shared/Q4`. Which?"
- **Known gap:** `mcp-search.sh` results of type `dataModelElement`
  don't always carry the parent `dataModelId`. If you need to chain
  into `mcp-describe.sh datamodel-element`, resolve the data model
  first via search or `find-file-by-urlid.sh`.

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

# Warehouse table
scripts/api/mcp-describe.sh table <connection-id> <db>.<schema>.<table>
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

## Discovery via REST primitives (default, not a fallback)

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
resolved data-model/workbook id to get to its elements).

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

- **`mcp-search.sh`/`mcp-describe.sh` exit 3 with `Missing required
  scopes: mcp:access`**: expected, not a bug — see the MCP status note
  at the top of this file. Don't retry the MCP call; switch to
  `search-files.sh` / the REST describe recipes above.
- **`search-files.sh` returns nothing**: try a broader/shorter
  substring (it's exact substring match, not fuzzy), or switch to
  `find-file-by-urlid.sh` if you have a URL slug.
- **`mcp-describe` 404s on a known-good ID** (on the rare host where MCP
  access does work): the resource may require a different `kind`
  argument. Try `workbook` vs `workbook-element`, `datamodel` vs
  `datamodel-element`.
- **`/v2/connection/<id>/lookup` returns ambiguous results**: ask
  the user for the full database/schema path. Don't guess.
- **Schema URL slugs (`/s/<id>`, `/t/<id>`)**: technically reachable via
  `/v2/connections/paths`, but that's a full org-wide paginated
  enumeration (thousands of entries, real rate-limit risk) — not viable
  for a single lookup. Ask the user for `<DB>.<SCHEMA>` and the
  connection name instead of trying to reverse it.
- **Table name given without a confirmed schema**: don't cascade into
  guessing sibling schemas — confirmed costly (29 calls, 0 hits in one
  live test). Ask the user for the schema/DB instead. See "Routing: raw
  warehouse tables" above.

When in doubt, surface to the user. The plan's "Open decisions"
section is the right place to log discovery gaps.
