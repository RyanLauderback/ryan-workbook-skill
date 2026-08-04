# Input tables (editable data & writeback)

New 2026-08-04 (Wave 3 / C5). The `input-table` element is an editable
table — users type values directly into cells, backed by a provisioned
warehouse table. Split out of `tables.md` because it's the only element
kind where the workbook holds state *the user typed*, which changes
correctness reasoning globally (idempotency, seeding, latest-row-wins) —
see `reference/history.md` → "2026-08-04 — Wave 3 / C5+C6" for the full
probe.

**Every shape below is live-POST verified** (`workbookId:
b7fead6d-504e-48e7-b623-e41576ce8eb5`, "Claude Testing" folder) — a
correction over the prior status, where all 27 harvested instances
across 5 production workbooks were GET-spec (read) confirmation only.
Authored from scratch (both `empty` and `linked` source variants, all
six column shapes, both `insert-rows` and `delete-rows` writeback via a
button) and round-tripped byte-for-byte through POST → GET.

```bash
jq --arg k input-table 'first(.. | objects | select((.allOf? and any(.allOf[]?; .properties?.kind?.enum==[$k])) or .properties?.kind?.enum==[$k]))' /tmp/sigma-api.json
```

## Shape

Required fields: `id`, `kind: input-table`, `source`, `inputMode`.

```json
{
  "id": "input-forecast",
  "kind": "input-table",
  "inputMode": "explore",
  "source": { "kind": "empty", "connectionId": "<connection-id>" },
  "columns": [
    { "id": "col-region",   "name": "Region",   "type": "text" },
    { "id": "col-forecast", "name": "Forecast", "type": "number" },
    { "id": "col-approved", "name": "Approved", "type": "checkbox" },
    { "id": "UPDATED_AT" },
    { "id": "UPDATED_BY" }
  ]
}
```

- `inputMode`: `"explore"` (live-POST verified) and `"view"` observed in
  the harvest; `"edit"` documented upstream but not yet harvested or
  probed. `explore` = users with explore permission or greater can edit,
  in published view; `view` = all users can edit, in published view;
  `edit` (per upstream) = workbook editors only, in draft mode.
- `source.kind`:
  - `"empty"` + **required** `connectionId` — provisions a fresh, blank
    warehouse table. **Live-POST verified** — a real connection id
    (BigQuery, in the probe) round-tripped unchanged.
  - `"linked"` + `from: "<elementId>"` — rows are linked to **another
    workbook element** (not directly to a warehouse table); editable
    rows are matched to that element's rows by the `key` columns below.
    **Live-POST verified.**

## Six column shapes

All six confirmed live-POST (previously: harvest-only, with `dropdown`
and `file` not documented at all by upstream):

- **System** — `{id}` where `id` is one of `ID`, `CREATED_AT`,
  `CREATED_BY`, `UPDATED_AT`, `UPDATED_BY`. Protocol-managed; do not set
  a `type` or pass a value for these in a writeback effect. **Live-POST
  verified** — all five round-tripped as bare `{id}` objects with no
  other fields added by the server.
- **Key** — `{id, key}`, e.g. `{"id": "col-link-key", "key":
  "col-sku"}` — binds to a source column on `source.from` for a
  `linked` table. Immutable once created. **Corrected 2026-08-04**:
  previously documented as `key: "inode-<id>/SKU_NUMBER"` (an
  inode-prefixed path) from harvest evidence alone. Live-POST testing
  shows **`key` is just the bare column `id` of the referenced
  `source.from` element's own column** — no inode prefix needed. The
  inode-style value in the original harvest was an artifact of that
  particular `from` element being a raw data-model passthrough table
  whose own column IDs happened to be inode-style strings, not a
  required format for `key` itself.
- **Editable data** — `{id, type, name}` where
  `type ∈ text | number | datetime | checkbox | file`. `file` observed
  only in Bergey's Unified Insights (harvest-only; not independently
  probed — no file-upload connection available in this session).
  **text/number/datetime/checkbox live-POST verified.**
- **Dropdown** — an editable `type: "text"` column plus `values: [...]`
  (the fixed option list) and `pills: "color-by-option"` for colored
  pill rendering. **Live-POST verified**, both fields round-tripped
  unchanged.
- **Formula** — `{id, formula, name}` — a computed column, same shape
  as on any other table. **Live-POST verified.**
- Also supports `filters`, `sort`, and `conditionalFormats` with
  `condition: "formula"` — same shapes as `table`. Not independently
  re-probed this wave; carried over from harvest evidence.

## Writeback

**Live-POST verified** (via a button's `on-click` action, and
separately via an agent tool step — see `agents.md`):

```json
{
  "effect": "insert-rows",
  "table": "input-tbl-scenarios",
  "values": {
    "col-name": { "type": "constant", "value": { "type": "text", "value": "Probe Scenario" } },
    "col-forecast": { "type": "constant", "value": { "type": "number", "value": 1000 } }
  }
}
```

```json
{
  "effect": "delete-rows",
  "table": "input-tbl-scenarios",
  "whichRows": { "type": "formula", "formula": "[Status] = \"Draft\"" }
}
```

`table` is the `input-table` element's own `id`. `insert-rows.values` is
keyed by column `id`, each a dynamic-value object (see
`dynamic-values.md`) — do not pass values for system columns (`ID`,
`CREATED_AT`, `CREATED_BY`, `UPDATED_AT`, `UPDATED_BY`), they're
protocol-managed. `delete-rows.whichRows` is a formula evaluated against
each existing row; matching rows are removed. The formula's bare
`[Status]` resolves against the input-table's own column **names**
(`"Status"`, the `name` on `col-status`) — same bare-ref resolution
rules as any other element.

**`update-rows` does not exist** — the working pattern is append-only
inserts plus a `Coalesce`/latest-row-wins read formula.

Full effect vocabulary and referential semantics: see `actions.md`.
`validate-spec.py`'s `action-refs-resolve` check verifies `table`
resolves to a real `kind:"input-table"` element and that
`insert-rows.values` keys match real column IDs on that table.

## GET-back normalization — column order is not preserved

**Caution, found during this wave's probe.** POSTing columns in the
order `[editable, editable, ..., system×5, formula]` came back on GET
reordered to `[editable columns first, then system columns, then
formula columns]` — grouped by category, not by submission order. Field
content is unaffected (every field on every column round-tripped
correctly), only array position. Don't diff a re-fetched spec's
`columns` array positionally against what you sent; diff by column
`id`.

## Cross-references

- `reference/conventions.md` → "Passthrough mandate" — every table
  that's a source for downstream elements should declare full
  passthrough columns.
- `reference/conventions.md` → "Explicit-`name` rule" — every
  passthrough column needs an explicit `name`.
- `actions.md` — the full effect vocabulary, including `insert-rows`/
  `delete-rows` referential semantics.
- `agents.md` — agent tools write to input tables via the same
  `insert-rows`/`delete-rows` effects, plus the `agent-input` dynamic
  value form for model-supplied values.
- `formulas.md` — column reference rules + the #1 mistake.
