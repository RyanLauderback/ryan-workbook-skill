# Warehouse table source

The `warehouse-table` source is the most common source kind — raw data
from a warehouse connection. Virtually every workbook starts with at
least one element sourced from a warehouse table (or from an element
that is, via `kind: "table"` or `kind: "join"`).

```bash
jq '.components.schemas.WarehouseTableSource' /tmp/sigma-api.json
```

This file covers: path formats per warehouse, formula-prefix
conventions, and the special-character / friendly-name pitfalls.

See `reference/workflows/discover.md` for how to find the
`connectionId` and `path` via the REST API + this skill's MCP wrappers.

## Shape

```json
{
  "kind": "warehouse-table",
  "connectionId": "<conn-uuid>",
  "path": ["DATABASE", "SCHEMA", "TABLE"]
}
```

## Formula references

Column formulas reference warehouse columns via the **last segment of
the path array**:

- Path `["SALES_DB", "PUBLIC", "ORDERS"]` → `[ORDERS/revenue]`,
  `[ORDERS/order_date]`
- Path `["ANALYTICS", "CORE", "USERS"]` → `[USERS/email]`

Inside a `join` source, warehouse path segments are **not** used as
prefixes — use the join leg's `name` instead. See
`sources.md` → "join."

## Path formats by warehouse

| Warehouse | Path format |
|---|---|
| Snowflake | `["DATABASE", "SCHEMA", "TABLE"]` |
| BigQuery | `["PROJECT", "DATASET", "TABLE"]` |
| Databricks | `["CATALOG", "SCHEMA", "TABLE"]` |
| Redshift | `["SCHEMA", "TABLE"]` |
| PostgreSQL / MySQL | `["SCHEMA", "TABLE"]` |

A warehouse table's path must be exactly the depth its warehouse
uses (e.g., Snowflake is always 3; Postgres is always 2). Use
`scripts/api/lookup-path.sh` to resolve ambiguity.

## Friendly vs. raw column names

Sigma's formula DSL references columns by their **friendly name**,
not their raw warehouse name. The two diverge:

| Raw warehouse name | Friendly name used in formulas |
|---|---|
| `DATE` | `Date` |
| `UNIT PRICE` | `Unit Price` |
| `ORDER_ID` | `Order ID` |
| `V userId` | `V User Id` |
| `Net/Gross` | `Net Gross` |

The trap: `GET /v2/connections/tables/{inodeId}/columns` returns
**raw warehouse names**. Formulas written against those raw names
will silently fail to resolve — Sigma is permissive at POST time
and even auto-normalizes some simple cases (`[ORDERS/DATE]` →
`[ORDERS/Date]`), but the auto-fix doesn't cover everything.

See `reference/workflows/discover.md` → "Column names — friendly vs
raw warehouse" for the reliable workflow.

## Common pitfalls

- **Column names with special characters** — `/`, `-`, `.`, brackets,
  leading/trailing whitespace all get normalized by Sigma. Never
  hand-transform a raw warehouse name; let the verify pass surface
  the canonical friendly name.
- **Inventing column names** — don't. Only reference columns the
  user has supplied or confirmed.
- **Wrong path depth** — a warehouse table's path must be exactly
  the depth its warehouse uses. Use
  `scripts/api/lookup-path.sh <conn-id> "<DB>.<SCHEMA>.<TABLE>"` to
  resolve.

## When to use `warehouse-table` vs `data-model`

**Prefer `data-model`** when the user's org has a relevant data
model — it inherits the data model's joins, filters, metrics, and
column-level security. See `sources.md` → "data-model."

**Fall back to `warehouse-table`** when no data model fits or the
user explicitly wants raw warehouse access. Don't manufacture a
data model just to avoid `warehouse-table`.

The schema-drift fallback in
`reference/scope-and-edge-cases.md` → "Falling back to
`warehouse-table` source" covers the case where a data-model-sourced
spec fails at POST and the recovery path is to re-source from the
underlying warehouse table.
