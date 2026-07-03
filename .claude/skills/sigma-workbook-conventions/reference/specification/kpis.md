# KPIs

The `kpi-chart` element — single-value stat card.

```bash
jq '.components.schemas.KpiChart' /tmp/sigma-api.json
```

Typically a KPI points at a table as its source and computes one
aggregated value.

> ⚠️ The docs sometimes call this `kpi` — the API rejects with
> `Invalid kind: "kpi"`. Use `kpi-chart`.

## Shape

```json
{
  "id": "total-sales",
  "kind": "kpi-chart",
  "name": "Total Sales",
  "source": { "kind": "table", "elementId": "sales-table" },
  "columns": [
    {
      "id": "kpi-val",
      "formula": "[Metrics/Total Revenue]",
      "format": { "kind": "number", "formatString": "$,.0f" }
    }
  ],
  "value": { "columnId": "kpi-val" }
}
```

- `columns` — define at least one column (the value to display).
  More columns are allowed but only `value.columnId` is rendered as
  the headline.
- `value.columnId` — the column ID to show in the card.
  **Verified 2026-07-02 across all harvested KPIs (26 instances):
  the field is `columnId`, not `id`.** Sending `value.id` will be
  silently ignored or rejected depending on the server version.
- `format` on the column controls displayed format. See
  `formatting.md`.

## With sparkline / period-over-period comparison

The KPI's `columns` array should include a date-dimension column.
Sigma renders the sparkline + period comparison automatically from
that column:

```json
{
  "id": "kpi-revenue",
  "kind": "kpi-chart",
  "name": "Total Revenue",
  "source": { "kind": "table", "elementId": "sales-table" },
  "columns": [
    { "id": "kpi-rev-value", "formula": "[Metrics/Total Revenue]",
      "format": { "kind": "number", "formatString": "$,.0f" } },
    { "id": "kpi-rev-month", "formula": "DateTrunc(\"month\", [Date])",
      "name": "Month" }
  ],
  "value": { "columnId": "kpi-rev-value" }
}
```

**KPIs without a date-dimension column lose the most analytical
value.** A naked number with no comparison context is hard to
interpret. Include the date dimension in `columns` even if it's not
the `value.columnId`.

## Title styling (styled-name object form)

`name` is polymorphic — accepts a plain string OR a styled object:

```json
"name": {
  "text": "Total Revenue",
  "color": "#3A2E26",
  "fontSize": 32,
  "fontWeight": "bold"
}
```

Or hide the title bar entirely:

```json
"name": { "visibility": "hidden" }
```

Verified fields: `text`, `color` (hex), `fontWeight` (`"bold"`,
`"normal"`, likely `"600"` etc.), `fontSize` (pixel number),
`visibility` (`"hidden"` so far). See `examples/styled-card-dashboard.json`
for KPI tiles using the styled-name form with `fontSize: 32`.

## Element-level styling

KPI tiles accept the same top-level `style` object as other viz
elements:

```json
"style": {
  "borderRadius": "round",
  "borderColor":  "#E8DFD3",
  "borderWidth":  1
}
```

`backgroundColor` is also accepted but often omitted on KPI tiles so
the container behind shows through. See `containers.md` →
"Common style recipes" for the full recipe catalog.

## Element-level `layout` object

Distinct from the top-level layout XML. On KPIs, a `layout` object
controls in-tile anchor positioning of the value:

```json
"layout": { "anchor": "middle" }
```

Observed values: `"middle"`. Presumably `"start"` / `"end"` supported;
inspect the OpenAPI. Verified 2026-07-02 across `sales-mbr-sentinel`
(18 KPIs).

See `layout.md` → "Two flavors: XML layout vs. element-level `layout`
object" for the distinction.

## Description must be an object

`description` on KPIs is **object-only**. A plain-string
`description` is rejected at POST with `Invalid object: string`.

Correct shapes:

```json
"description": { "text": "Current-month bookings from Opps table" }
```

```json
"description": { "visibility": "hidden" }
```

Setting `visibility: "hidden"` removes the description line from the
tile entirely. Verified 2026-07-02 across `sales-mbr-sentinel` KPIs
and `inventory-health` build (1 POST retry on string-form rejection).
Same rule applies to tables — see `tables.md` → "Styled name +
description + noDataText."

## Formula qualification

Every KPI sources another element, so the column's formula must use
either:

- `[Metrics/<Name>]` for data-model metrics (when sourcing a DM
  element via a sibling table)
- `[<SourceName>/<column>]` for warehouse-table or sibling-element
  references

A bare `[col]` is only valid for referencing another column defined
in this KPI's own `columns[]` array. This is the single most common
mistake — see `formulas.md`.

Run `scripts/validate-spec.py` before publishing to catch it.

## Value formula pitfall: can't reference sibling aggregation columns

A `value.columnId` formula that uses bare `[Sibling]` refs to other
columns in the same KPI **renders as `null`** when those siblings
themselves contain aggregation functions (`Sum`, `Avg`, `Count`,
`CountDistinct`, `Median`, `Percentile`, etc.).

**Why it fails:** Sigma evaluates the value formula per-row of the
source table first, then aggregates. Bare `[Sibling]` refs resolve
to the sibling's per-row value — but an aggregation column has no
per-row value, so the ref evaluates to `null` and the whole
expression collapses to `null`.

### Wrong — silently renders null

```json
"columns": [
  { "id": "kpi-lift",
    "formula": "([Promo AOV] - [Non-Promo AOV]) / [Non-Promo AOV]",
    "name": "Lift %" },
  { "id": "kpi-promo-aov",
    "formula": "Sum(If([Promo Flag]=\"Promo\",[Rev],0)) / CountDistinct(If([Promo Flag]=\"Promo\",[Order],Null))",
    "name": "Promo AOV" },
  { "id": "kpi-nonpromo-aov",
    "formula": "Sum(If([Promo Flag]=\"Non-Promo\",[Rev],0)) / CountDistinct(If([Promo Flag]=\"Non-Promo\",[Order],Null))",
    "name": "Non-Promo AOV" }
],
"value": { "columnId": "kpi-lift" }
```

Verified 2026-07-02 against `Marketing-and-Promotions-Performance`:
`Promo Lift vs Non-Promo AOV` KPI rendered `null` because
`kpi-lift`'s formula referenced two sibling aggregation columns
via bare refs.

### Right — self-contained value formula

Inline the aggregations directly in the value column's formula so
it evaluates as a single scalar over the source table:

```json
"columns": [
  { "id": "kpi-lift",
    "formula": "(Sum(If([Promo Flag]=\"Promo\",[Rev],0)) / CountDistinct(If([Promo Flag]=\"Promo\",[Order],Null))) / (Sum(If([Promo Flag]=\"Non-Promo\",[Rev],0)) / CountDistinct(If([Promo Flag]=\"Non-Promo\",[Order],Null))) - 1",
    "name": "Lift %",
    "format": { "kind": "number", "formatString": ".1%" } }
],
"value": { "columnId": "kpi-lift" }
```

Verbose but correct — each aggregation evaluates over the whole source
table, and the ratio computes over the resulting scalars.

### Alternatives when the formula gets unwieldy

- **Promote the ratio to a data-model metric.** Define `Promo Lift %`
  on the DM element and reference `[Metrics/Promo Lift %]` in the
  KPI. Keeps the KPI spec small and reuses the definition across
  workbooks.
- **Compute upstream in a derived table.** Create a sibling table
  element with one row per (dimension) and pre-aggregated Promo/
  Non-Promo columns, then source the KPI from that. The KPI can
  reference its columns without hitting the aggregation-nesting
  problem because the source is already at the right grain.

`scripts/validate-spec.py`'s `kpi-value-references-aggregation`
check (added 2026-07-02) warns pre-POST when a KPI value formula
uses bare refs to sibling columns whose formulas contain
aggregation functions. Warn-level, not fail — a false positive is
possible when the sibling's aggregation happens to evaluate to a
single valid scalar (rare); inspect flagged cases.

## Passthrough columns

The KPI's `columns` array should include the source table's
passthrough columns alongside the headline `value` and date
dimension. This enables drill-down from the KPI to detail.

KPIs are intentionally **excluded from `validate-spec.py`'s
`passthrough-coverage` check** because their col count varies a lot
based on whether the user wants drill-down support. Use judgment.

## Known limitations

- **No `delta` / comparison field on the KPI element.** The spec
  carries the date-dimension column that *enables* comparison mode;
  the specific period (vs prior month / quarter / year) is UI-side
  state and isn't represented in the code spec. To force a specific
  comparison period, stack two `kpi-chart` elements side-by-side via
  layout XML.
- **No `target` / `goal` field.** To show a value vs. a target,
  build a chart with two columns (value + target) instead.

## Tile sizing

A KPI with a sparkline needs ~8-10 grid rows of vertical space. A
3-row KPI with timeline comparison renders the sparkline too small
to read. See `layout.md` for grid placement.
