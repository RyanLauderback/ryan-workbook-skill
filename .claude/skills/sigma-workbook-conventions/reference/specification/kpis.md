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
  "value": { "id": "kpi-val" }
}
```

- `columns` — define at least one column (the value to display).
  More columns are allowed but only `value.id` is rendered as the
  headline.
- `value.id` — the column ID to show in the card.
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
  "value": { "id": "kpi-rev-value" }
}
```

**KPIs without a date-dimension column lose the most analytical
value.** A naked number with no comparison context is hard to
interpret. Include the date dimension in `columns` even if it's not
the `value.id`.

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
