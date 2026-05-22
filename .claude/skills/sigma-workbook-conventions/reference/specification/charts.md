# Charts

Chart element kinds: `bar-chart`, `line-chart`, `area-chart`,
`combo-chart`, `scatter-chart`, `pie-chart`, `donut-chart`. This file
is a recipe book for chart specs and the style choices that go with
each kind.

```bash
jq '.components.schemas.LineChart, .components.schemas.BarChart, .components.schemas.AreaChart, .components.schemas.ComboChart, .components.schemas.ScatterChart, .components.schemas.PieChart, .components.schemas.DonutChart' /tmp/sigma-api.json
```

All Cartesian charts (bar/line/area/combo/scatter) share the same
skeleton: `source`, `columns[]`, `xAxis`, `yAxis`. Donut/pie use
`value` + `color` instead. Formulas on a chart that sources another
element must use the source's prefix (`[<SourceName>/col]`) — see
`formulas.md`.

## Axis shape — canonical

```json
"xAxis": { "columnId": "<col-id>", "sort": { "by": "<col-id>", "direction": "ascending|descending" } },
"yAxis": { "columnIds": ["<col-id-1>", "<col-id-2>"] }
```

- `xAxis` — single object with `columnId` (string) and optional
  `sort` + `format`.
- `yAxis` — single object with `columnIds` (array of string IDs).
  For combo-chart, entries may be `{ columnId, type }` for per-
  series shape (see "Combo chart" below).
- Optional `format` on each axis configures title, labels, marks,
  and scale — fetch `CartesianAxisFormat` from the OpenAPI for the
  full shape.

> **Legacy axis form** — existing exemplars in this skill (created
> before 2026-05-21) use `xAxis: {id}` / `yAxis: [{id}]` (array of
> objects). Both forms POST cleanly; GET returns the modern
> `columnId` / `columnIds` form. New authoring should prefer the
> modern form. `scripts/workbook-manifest.py` recognizes both.

## Line chart

```json
{
  "id": "sales-over-time",
  "kind": "line-chart",
  "name": "Sales over time",
  "source": { "kind": "table", "elementId": "sales-table" },
  "columns": [
    { "id": "col-month",
      "name": "Month",
      "formula": "DateTrunc(\"month\", [Master/Date])",
      "format": { "kind": "datetime", "formatString": "%b %Y" } },
    { "id": "col-sales",
      "name": "Sales",
      "formula": "Sum([Master/Sales Amount])",
      "format": { "kind": "number", "formatString": "$,.0f" } }
  ],
  "xAxis": { "columnId": "col-month" },
  "yAxis": { "columnIds": ["col-sales"] }
}
```

## Bar chart

Same axis shape as line-chart. Adds `stacking` and the
`orientation` field.

```json
{
  "id": "sales-by-region",
  "kind": "bar-chart",
  "name": "Sales by region",
  "source": { "kind": "table", "elementId": "sales-table" },
  "columns": [
    { "id": "col-region", "name": "Region", "formula": "[Master/Store Region]" },
    { "id": "col-sales", "name": "Sales",
      "formula": "Sum([Master/Sales Amount])",
      "format": { "kind": "number", "formatString": "$,.0f" } }
  ],
  "xAxis": {
    "columnId": "col-region",
    "sort": { "by": "col-sales", "direction": "descending" }
  },
  "yAxis": { "columnIds": ["col-sales"] },
  "stacking": "none",
  "orientation": "horizontal"
}
```

`stacking`: `none` | `stacked` | `"100"` (the percent-stacked variant
must be quoted in JSON/YAML to keep it a string).

### Orientation + categorical-axis sort rule

Bar charts accept `orientation: "horizontal" | "vertical"` (default
vertical). **Bar charts only** — line/area/combo/scatter use time-on-x
or metric-on-x by design.

| X-axis type | Examples | `orientation` | `xAxis.sort` |
|---|---|---|---|
| Categorical | Segment, Tenure, Region | `"horizontal"` | `{by: "<y-col-id>", direction: "descending"}` |
| Time-series | Month, Week, Day | omit (vertical) | `{by: "<x-col-id>", direction: "ascending"}` |

**Why categorical → horizontal + descending:** dodges Sigma's auto-
label-rotation (labels read left-aligned on Y axis) AND ranks
largest→smallest, the conventional categorical read order. Horizontal
on time-series compresses the time scale.

### Color channel

`bar-chart` accepts an optional `color` channel with three variants:

```json
"color": { "by": "single", "value": "#3b82f6" }
```

```json
"color": {
  "by": "category",
  "column": "col-region",
  "scheme": ["#3b82f6", "#ef4444", "#10b981", "#f59e0b"]
}
```

```json
"color": {
  "by": "scale",
  "column": "col-sales",
  "scheme": ["#fef3c7", "#fbbf24", "#dc2626"],
  "domain": [0, 5000, 10000]
}
```

**`scheme` is a positional array.** Sigma assigns colors to categories
in the order they appear on the axis, not by category name. To pin
Electronics → blue, Apparel → red, Home → green, control the sort
order alongside the color array. For category-by-name binding, use a
derived column with an `If(...)` that emits categories in a known
order, then sort by that order.

## Area chart

Same axis shape as line/bar. Adds `stacking` modes:

```json
{
  "id": "sales-over-time-stacked",
  "kind": "area-chart",
  "name": "Sales over time by region",
  "stacking": "stacked"
}
```

`stacking` values for area-chart: `"none"` (overlay), `"stacked"`
(default), `"100"` (100% normalized).

## Combo chart

Mixes bar + line on the same chart. `yAxis.columnIds` entries can
be plain strings (default chart kind) or objects with a `type`
override:

```json
"yAxis": {
  "columnIds": [
    "col-bar-revenue",
    { "columnId": "col-line-margin", "type": "line" }
  ]
}
```

`type` values: `"line"`, `"bar"`, `"area"`, `"scatter"`.

## Scatter / bubble chart

Both axes are metrics (not categorical). Optional `size` makes it a
bubble chart:

```json
{
  "id": "stores-scatter",
  "kind": "scatter-chart",
  "name": "Stores: Revenue vs Profit Margin",
  "xAxis": { "columnId": "sc-revenue" },
  "yAxis": { "columnIds": ["sc-margin"] },
  "size": { "id": "sc-units" },
  "color": { "by": "category", "column": "sc-region" }
}
```

## Pie / donut chart

Uses `value` + `color` instead of `xAxis` / `yAxis`:

```json
{
  "id": "sales-by-family",
  "kind": "donut-chart",
  "name": "Sales by product family",
  "source": { "kind": "table", "elementId": "sales-table" },
  "columns": [
    { "id": "col-family", "name": "Family", "formula": "[Master/Product Family]" },
    { "id": "col-sales", "name": "Sales", "formula": "Sum([Master/Sales Amount])" }
  ],
  "value": { "id": "col-sales" },
  "color": {
    "id": "col-family",
    "sort": { "by": "col-sales", "direction": "descending" }
  }
}
```

### `holeValue` on donut

Optional. References one of the donut's columns by ID — that
column's aggregated value drives the hole label:

```json
"holeValue": { "id": "col-sales" }
```

`holeValue` is **not a literal number** — it must reference a
column. To display a custom calculated value, define a column for
it and reference its id.

### Pie chart — same shape as donut

```json
{ "id": "...", "kind": "pie-chart", "value": {...}, "color": {...} }
```

## Cartesian-only optional features

These apply to `bar-chart`, `line-chart`, `area-chart`,
`scatter-chart`, and `combo-chart`. Fetch the full schemas:

```bash
jq '.components.schemas.ReferenceMark, .components.schemas.Trendline, .components.schemas.DataLabel' /tmp/sigma-api.json
```

### `refMarks` — reference lines and bands

```json
"refMarks": [
  {
    "type": "line",
    "axis": "series",
    "value": 1000,
    "line": { "color": "#ef4444", "width": 2 },
    "label": { "text": "Threshold" }
  },
  {
    "type": "band",
    "axis": "series",
    "value": 800,
    "endValue": 1200
  }
]
```

`axis` values: `axis` | `series` | `series2`. `value` can be a
number, column ID, or formula string. Bands require `endValue`.

### `trendlines` — regression overlays

```json
"trendlines": [
  {
    "columnId": "col-sales",
    "model": "linear",
    "line": { "color": "#336699", "width": 2 },
    "label": { "visibility": "shown", "text": "Sales trend" }
  }
]
```

`model` values: `linear` | `quadratic` | `polynomial` |
`exponential` | `logarithmic` | `power`.

Trendlines are rejected when the chart has no `xAxis`, uses
stacking on bar/area/combo, or has a `color` channel — discover
those constraints by submitting and reading the error.

### `dataLabel` — value labels on marks

```json
"dataLabel": {
  "labels": "shown",
  "labelDisplay": "all-points",
  "valueFormat": "percent",
  "totals": { "display": "shown" }
}
```

`labels` values: `shown` | `hidden`. `labelDisplay` values:
`all-points` | `maximum` | `min-max` | etc.

For `combo-chart`, optional `seriesDataLabel` is a map keyed by
layer shape (`bar`, `line`, `area`, `scatter`) with per-shape
overrides:

```json
"seriesDataLabel": {
  "bar":  { "labelDisplay": "maximum" },
  "line": { "labelDisplay": "all-points" }
}
```

## Element-level filters (top-N, etc.)

Charts take the same `filters` array as tables. Top 10 by sales:

```json
"filters": [
  {
    "id": "top-10",
    "columnId": "col-sales",
    "kind": "top-n",
    "rankingFunction": "rank",
    "mode": "top-n",
    "rowCount": 10,
    "includeNulls": "when-no-value-is-selected"
  }
]
```

> **`rowCount` takes a number literal only** — it cannot be bound to
> a control. `rowCount: "[TopN]"` is rejected. Control bindings apply
> to filter **values**, not structural fields. To vary a top-N cap
> interactively, duplicate the element per cap.

## Title styling (styled-name object form)

`name` is polymorphic — accepts a string OR a styled object with
`text`, `color`, `fontSize`, `fontWeight`, and `visibility`. See
`kpis.md` → "Title styling" for the shape; the rules are identical
across all chart kinds.

## Element-level frame (`style`)

Every chart kind accepts a top-level `style` object — see
`containers.md` → "Common style recipes." Card style is the default:

```json
"style": {
  "backgroundColor": "#FFFFFF",
  "borderRadius": "round",
  "borderColor": "#E8DFD3",
  "borderWidth": 1
}
```

## Legend

```json
"legend": { "visibility": "hidden" }
```

```json
"legend": { "position": "bottom" }
```

- `visibility`: `"hidden"` hides the legend entirely. Use on
  single-series charts where the legend adds no information.
- `position`: `"bottom"` (observed). Other positions (`"top"`,
  `"left"`, `"right"`) likely accepted — verify via UI-toggle + GET-back.

## Cross-references

- `reference/conventions.md` → "Passthrough mandate" — every chart
  must carry the source table's passthrough column set.
- `reference/conventions.md` → "Bar-chart orientation" — the
  categorical-vs-time-series rule.
- `formulas.md` → "Column reference rules" — how to qualify column
  refs inside a chart sourcing another element.

## What's NOT spec-able

- **Comparison period / delta** on KPIs — see `kpis.md`.
- **Axis label rotation** — UI-only.
- **Chart marker shapes** beyond what `dataLabel` controls — UI-only.
- **Per-series colors** outside the `color.scheme` palette — UI-only
  (the workbook theme's categorical palette is the source).

When the docs and the API disagree, trust the API error. When you're
not sure whether a field exists, fetch the OpenAPI schema for the
relevant element kind.
