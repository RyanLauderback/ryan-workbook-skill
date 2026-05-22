# Source Discovery

Finding connections, tables, columns, data models, metrics, and existing
workbooks via the Sigma REST API + this skill's MCP wrappers. Load before
composing any new spec.

## The routing decision

What the user's prompt contains determines which discovery tool to reach
for first:

| Prompt contains | Use first |
|---|---|
| Names or topics ("the PLUGS data model", "find the sales workbook") | `scripts/api/mcp-search.sh "<query>" [--types workbook,dataModel,dataModelElement,table] [--limit N]` |
| URL slugs (`/b/<id>`, `…-<urlId>`) | `scripts/api/find-file-by-urlid.sh <urlId>` |
| Warehouse paths (`<DB>.<SCHEMA>.<table>`), `/s/<id>` or `/t/<id>` schema URLs, or mixed prose | `scripts/sigma-resolve.py "<prompt-verbatim>"` |

After resolution, use `scripts/api/mcp-describe.sh` against the resolved
id to inspect — returns SQL DDL with column types, descriptions,
formulas, and the metrics catalog. Replaces hand-walking `GET
/v2/dataModels/{id}/spec` JSON.

## Discovery via MCP (preferred — richer output, less plumbing)

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

## Discovery via REST primitives (fallbacks)

The MCP wrappers cover ~90% of discovery needs. Reach for these only
when MCP doesn't:

```bash
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

These hit `/v2/connections`, `/v2/connection/<id>/lookup`,
`/v2/connections/tables/<inode>/columns`, `/v2/files`, etc. Auth is
self-bootstrapped via `_env.sh`.

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
and `/t/<id>` schema URLs too — these are NOT reversible via Sigma's
public API, so if unresolved, ask the user for the warehouse path.

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

- **MCP `search` returns nothing**: try broader query terms or
  switch to `find-file-by-urlid.sh` if you have a URL slug.
- **`mcp-describe` 404s on a known-good ID**: the resource may
  require a different `kind` argument. Try `workbook` vs `workbook-element`,
  `datamodel` vs `datamodel-element`.
- **`/v2/connection/<id>/lookup` returns ambiguous results**: ask
  the user for the full database/schema path. Don't guess.
- **Schema URL slugs (`/s/<id>`, `/t/<id>`)** are not reversible via
  Sigma's public API. Ask the user for `<DB>.<SCHEMA>` and the
  connection name.

When in doubt, surface to the user. The plan's "Open decisions"
section is the right place to log discovery gaps.
