# Tables

The `table` and `pivot-table` element kinds.

```bash
jq '.components.schemas.Table, .components.schemas.PivotTable' /tmp/sigma-api.json
```

The `table` element is the most common element kind and the primary way
data enters a workbook — charts, KPIs, and other elements usually point
their `source` at a table.

## Basic shape

```json
{
  "id": "sales-table",
  "kind": "table",
  "name": "Sales Data",
  "source": {
    "kind": "warehouse-table",
    "connectionId": "<conn-uuid>",
    "path": ["DATABASE", "SCHEMA", "TABLE"]
  },
  "columns": [
    { "id": "col-1", "name": "Column Name", "formula": "[TABLE/column_name]" },
    { "id": "col-2", "name": "Total", "formula": "Sum([Column Name])" }
  ],
  "order": ["col-1", "col-2"]
}
```

See `sources.md` for all source kinds and `formulas.md` for
column-reference rules. Every column needs `id`, `name`, `formula`;
optional `format` (see `formatting.md`).

## Styled `name` + `description` + `noDataText`

`name` accepts either a plain string OR a styled object for headers
— same shape as KPI / chart titles:

```json
"name": {
  "text": "Sales Data",
  "fontSize": 18,
  "fontWeight": "bold"
}
```

Tables also accept optional `description` and `noDataText`:

```json
"description": {
  "text": "Latest quarter"
},
"noDataText": "No rows in range"
```

The shape mirrors chart titles; fetch `TitleSection` from the
OpenAPI for the full styling enum.

## Common optional fields

### `order`

Array of column IDs controlling left-to-right display order.
Defaults to declaration order.

### `groupings` — multi-level aggregation

Creates a hierarchical / pivot view without changing element kind.
Each entry is one **level** in the hierarchy:

```json
"groupings": [
  {
    "id": "by-region",
    "groupBy": ["col-region"],
    "calculations": ["col-total", "col-profit"]
  },
  {
    "id": "by-product",
    "groupBy": ["col-product-line"],
    "calculations": ["col-line-rev", "col-pct-of-total"]
  }
]
```

The shape `{id, groupBy: [<col-id>], calculations: [<col-id>]}` is
canonical. Legacy `{id, columnId}` and `{id}`-only forms are
render-hint serializations from older GET-backs — they don't
aggregate. Use the canonical shape for any new authoring. See
`reference/history.md` → "2026-05-13 — Cohort iteration."

Multi-level groupings produce real `GROUP BY` SQL — one per level,
joined so each detail row carries the aggregates from its ancestor
levels. Canonical example:
`examples/data-model-sourced-multi-level-aggregated-table.json`.

### `summary` — summary-bar pattern

A top-level field on the table element (singular `summary`, NOT
`summaries`). Each entry is a column id whose formula is evaluated
at the summary-bar grain (across all rows of the table). The
summary value is broadcast to every row.

```json
"summary": ["col-median-margin"]
```

Use cases: median/mean/percentile thresholds for downstream
bucketing columns. Full pattern + rationale in
`reference/conventions.md` → "Summary-bar pattern."

### `filters` — top-N, element-level row filters

```json
"filters": [
  {
    "id": "top-20",
    "columnId": "col-revenue",
    "kind": "top-n",
    "rankingFunction": "rank",
    "mode": "top-n",
    "rowCount": 20,
    "includeNulls": "when-no-value-is-selected"
  }
]
```

> **`rowCount` takes a number literal only** — cannot be parametrized
> by a control. `rowCount: "[TopN]"` is rejected. Control bindings
> apply to filter **values**, not structural fields like `rowCount`,
> `rankingFunction`, `mode`, or `kind`. To vary the cap interactively,
> duplicate the element per cap.

### `visibleAsSource`

Boolean. Whether this table is exposed as a source for other
elements on the page. Defaults to `false` (often) — set explicitly
to `true` for parent tables that downstream KPIs/charts source from.

### `folders` — column folder groupings

```json
"folders": [
  { "id": "store-fields", "name": "Store Fields",
    "items": ["col-store-key", "col-store-name", "col-store-region"] },
  { "id": "customer-fields", "name": "Customer Fields",
    "items": ["col-cust-key", "col-cust-name"] }
]
```

UI-side organization for tables with many columns. Doesn't affect
render or downstream references; just collapses column groups in
the table header.

## Conditional formatting — `conditionalFormats`

Threshold-based cell coloring. Verified 2026-05-21 against the
official skill — round-trips through GET unchanged; PUT-based edits
are stable.

```bash
jq '.components.schemas.ConditionalFormatSingle, .components.schemas.ConditionalFormatBackgroundScale, .components.schemas.ConditionalFormatFontScale, .components.schemas.ConditionalFormatDataBars' /tmp/sigma-api.json
```

Four variants: `single` (threshold rules), `backgroundScale`
(gradient scale on cell bg), `fontScale` (gradient on font color),
`dataBars` (inline data bars in the cell).

### `single` — red/green threshold

```json
"conditionalFormats": [
  {
    "type": "single",
    "columnIds": ["col-revenue"],
    "condition": ">",
    "value": 1000,
    "style": { "backgroundColor": "#22c55e" }
  },
  {
    "type": "single",
    "columnIds": ["col-revenue"],
    "condition": "<",
    "value": 100,
    "style": { "backgroundColor": "#ef4444" }
  }
]
```

Condition operators: `=`, `!=`, `>`, `>=`, `<`, `<=`, `IsNull`,
`IsNotNull`, `Contains`, `NotContains`, `StartsWith`, `EndsWith`,
`Between`, `NotBetween`, and `formula` (arbitrary boolean).

Style block supports `backgroundColor`, `color`, `bold`, `italic`,
`underline`, and column-level `format` override.

### `backgroundScale` — heatmap-style gradient

```json
{
  "type": "backgroundScale",
  "columnIds": ["col-revenue"],
  "scheme": ["#fef3c7", "#fbbf24", "#dc2626"],
  "domain": [0, 5000, 10000]
}
```

### `fontScale` — gradient on text color

```json
{
  "type": "fontScale",
  "columnIds": ["col-margin"],
  "scheme": ["#ef4444", "#fbbf24", "#22c55e"]
}
```

### `dataBars` — inline horizontal bars

```json
{
  "type": "dataBars",
  "columnIds": ["col-revenue"],
  "color": "#3b82f6"
}
```

### Round-trip status — verify before relying

> ⚠️ **2026-05-21 update.** The upstream `sigma-workbooks` skill
> claims `conditionalFormats` round-trips cleanly. **This skill's
> earlier observation that pivot cell heatmaps break GET-spec was
> from prior platform behavior.** The retest is part of Stage 7 of
> the migration plan — if confirmed fixed, the warning in
> `scope-and-edge-cases.md` will be amended.
>
> Until confirmed: assume `conditionalFormats` on `table` works (per
> official); on `pivot-table` may still trigger the
> `service_error` 500 on GET-spec — apply LAST after all spec
> round-tripping is done.

---

# Pivot tables

The `pivot-table` element is a sibling of `table` for cross-tab
analysis — measure cells aggregated across one or more row/column
dimensions.

## Shape

```json
{
  "id": "deployments-pivot",
  "kind": "pivot-table",
  "name": "Deployments by cloud and env",
  "source": { "kind": "table", "elementId": "deployments-source" },
  "columns": [
    { "id": "piv-cloud", "name": "Cloud", "formula": "[Deployments/Cloud]" },
    { "id": "piv-env", "name": "Environment", "formula": "[Deployments/Environment]" },
    { "id": "piv-count", "name": "Deployments",
      "formula": "CountDistinct([Deployments/Deployment UUID])",
      "format": { "kind": "number", "formatString": ",.0f" } }
  ],
  "values": ["piv-count"]
}
```

`values` is the measure column array (the cells of the pivot). The
remaining columns act as row/column dimensions.

## Round-trip quirks

- **Column reordering.** Sigma reorders the `columns` array on
  round-trip — value columns first, then dimensions — regardless of
  submission order. GET → edit → PUT will show a non-substantive
  diff in `columns`. The `values` array preserves IDs, so rendered
  output is unchanged.
- **Row vs. column dimension placement.** The OpenAPI surfaces only
  `columns` and `values`; there is no separate `rows` / `pivotRows`
  / `pivotColumns` field. Sigma infers row vs. column dimensions
  from the non-`values` columns. To control layout further, today
  the UI is the path.

## Pivot conditional formatting — status

Pivot `conditionalFormats` historically broke GET-spec (returns
`service_error` 500). Per the 2026-05-21 official-skill merger, the
upstream skill claims this is fixed. **Retest before relying.**
Apply pivot conditional formatting LAST in the iteration cycle so
that if GET-spec breaks, you don't lose the rest of your work.

## Cohort pivot pattern

For weeks-since-first-action / cohort retention analyses, build a
two-tier source structure and pivot the derived table by cohort
week × age week. Canonical example:
`examples/data-model-sourced-cohort-pivot.json`.

The pivot's columns include both dimensions (cohort dim + age dim)
and aggregated values (`Sum([Revenue])`, `CountDistinct([Cust Key])`).
See `reference/conventions.md` → "Two-tier sourcing."

## Cross-references

- `reference/conventions.md` → "Passthrough mandate" — every table
  that's a source for downstream elements should declare full
  passthrough columns.
- `reference/conventions.md` → "Explicit-`name` rule" — every
  passthrough column needs an explicit `name`.
- `reference/conventions.md` → "Summary-bar pattern" — use
  `summary` for aggregate-then-categorize compositions.
- `formulas.md` — column reference rules + the #1 mistake.
