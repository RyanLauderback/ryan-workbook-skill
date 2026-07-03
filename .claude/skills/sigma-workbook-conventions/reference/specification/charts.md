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

## Table of contents

- [Axis shape — canonical](#axis-shape--canonical) (modern + legacy forms)
- Chart kinds:
  - [Line chart](#line-chart)
  - [Bar chart](#bar-chart) (with orientation + categorical-sort rule)
  - [Area chart](#area-chart)
  - [Combo chart](#combo-chart)
  - [Scatter / bubble chart](#scatter--bubble-chart)
  - [Pie / donut chart](#pie--donut-chart) (with `holeValue` distinct-column rule)
- Cartesian-only optional features:
  - [`refMarks` — reference lines and bands](#refmarks--reference-lines-and-bands)
  - [`trendlines` — regression overlays](#trendlines--regression-overlays)
  - [`dataLabel` — value labels on marks](#datalabel--value-labels-on-marks)
- [Element-level filters (top-N, etc.)](#element-level-filters-top-n-etc)
- [Bar/column bar spacing — `gap`](#barcolumn-bar-spacing--gap) (with `betweenSets` clustered-set precondition)
- [Title styling (styled-name object form)](#title-styling-styled-name-object-form)
- [Element-level frame (`style`)](#element-level-frame-style)
- [Legend](#legend)
- [Period-comparison patterns (`color.by: category`)](#period-comparison-patterns-colorby-category) (date-part vs synthetic Period Tag)
- [What's NOT spec-able](#whats-not-spec-able)

---

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

Bar charts accept `orientation: "horizontal"` OR omit-for-default.
Explicit `orientation: "vertical"` is **rejected at POST** — the
default IS vertical, so leave the field out. **Bar charts only** —
line/area/combo/scatter use time-on-x or metric-on-x by design.

| X-axis type | Examples | `orientation` | `xAxis.sort` |
|---|---|---|---|
| Categorical | Segment, Tenure, Region | `"horizontal"` | `{by: "<y-col-id>", direction: "descending"}` |
| Time-series | Month, Week, Day | omit (defaults to vertical) | `{by: "<x-col-id>", direction: "ascending"}` |

**Why categorical → horizontal + descending:** dodges Sigma's auto-
label-rotation (labels read left-aligned on Y axis) AND ranks
largest→smallest, the conventional categorical read order. Horizontal
on time-series compresses the time scale.

Verified 2026-07-02 against `exec-scorecard-v2` build (1 POST retry
on explicit-`"vertical"` before this rule was documented).

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

Optional. References a donut column by ID — that column's aggregated
value drives the hole label.

**`holeValue.id` MUST reference a different column than `value.id`.**
POST rejects same-column reuse with:

> `Column '<col-id>' is referenced from both 'value' and 'holeValue';
> a column can only be on one channel at a time`

Pattern: add a second aggregation column, then wire each channel to
its own column:

```json
{
  "id": "sales-by-family",
  "kind": "donut-chart",
  "columns": [
    { "id": "col-family",     "formula": "[Master/Product Family]" },
    { "id": "col-sales",      "formula": "Sum([Master/Sales Amount])",  "name": "Sales" },
    { "id": "col-order-count","formula": "CountDistinct([Master/Order Id])", "name": "Orders" }
  ],
  "value":     { "id": "col-sales" },
  "holeValue": { "id": "col-order-count" },
  "color": {
    "id": "col-family",
    "sort": { "by": "col-sales", "direction": "descending" }
  }
}
```

`holeValue` is **not a literal number** — it must reference a column.
To display a custom calculated value, define a separate column for it
and reference its id.

Verified 2026-07-02: the distinct-column rule was surfaced when a
`sales-command-center` donut POST-rejected on same-column reuse.

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

Charts take the same `filters` array as tables. Each filter entry has
a `kind` that determines its shape. The most common is `top-n`:

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

| Field | Notes |
|---|---|
| `id` | Unique within the filters array |
| `kind` | `"top-n"` |
| `columnId` | Column ID on this element to rank by |
| `rankingFunction` | Observed: `"rank"`. Others likely per SQL window function |
| `mode` | `"top-n"` (observed); presumably `"bottom-n"` supported |
| `rowCount` | Integer literal — how many rows to keep |
| `includeNulls` | `"always"`, `"never"`, or `"when-no-value-is-selected"` |

Verified 2026-07-02 against `plugs-geography-yoy` (bar chart with
top-10 states filter).

> **`rowCount` takes a number literal only** — it cannot be bound to
> a control. `rowCount: "[TopN]"` is rejected. Control bindings apply
> to filter **values**, not structural fields. To vary a top-N cap
> interactively, duplicate the element per cap.

## Title styling (styled-name object form)

`name` is polymorphic — accepts a string OR a styled object with
`text`, `color`, `fontSize`, `fontWeight`, and `visibility`. See
`kpis.md` → "Title styling" for the shape; the rules are identical
across all chart kinds.

## Bar/column bar spacing — `gap`

Bar and column charts accept a `gap` object controlling spacing.

### Safe default

Use only `gap.width` — works on every bar/column chart regardless of
series count or grouping:

```json
"gap": { "width": "medium" }
```

### `gap.betweenSets` — clustered-set precondition (LOAD-BEARING)

`betweenSets` controls spacing between **grouped/clustered sets**.
POST **rejects** it on charts that don't have clustered sets, with:

> `betweenSets is only supported when the chart has clustered bar sets
> (color channel or multiple bar series with clustered stacking)`

Only include `betweenSets` when the chart has one of:

- A category `color` channel with multiple grouped series
  (`color.by: "category"` with a grouping column)
- Multiple bar series with `stacking: "clustered"` (or equivalent)

Safe combined shape (when precondition holds):

```json
"gap": {
  "width": "medium",
  "betweenSets": "medium"
}
```

Observed value: `"medium"`. Other d3-style values (`"small"`,
`"large"`) likely accepted; pull the enum from the OpenAPI:

```bash
jq '.components.schemas | to_entries[] | select(.value | .. | .properties?.gap? != null) | .key' /tmp/sigma-api.json
```

Verified 2026-07-02 against `sales-mbr-sentinel` (bar chart with
per-set groupings — worked) and `sales-command-center` iteration
(single-series bar + combo — rejected `betweenSets`).

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

## Period-comparison patterns (`color.by: category`)

When the ask is "compare current vs prior" or "year-over-year," the
color channel is what carries the comparison dimension. Two patterns —
pick based on how the data spans time.

### Prefer date-part color when data spans multiple periods

If the source data has multiple years (or quarters, months) in it,
use the actual date-part column as the color channel. The chart draws
one series per date-part value automatically.

```json
"columns": [
  { "id": "col-year",  "formula": "DatePart(\"year\", [Date])", "name": "Year" },
  { "id": "col-month", "formula": "DatePart(\"month\", [Date])", "name": "Month" },
  { "id": "col-rev",   "formula": "Sum([Rev])", "name": "Revenue",
    "format": { "kind": "number", "formatString": "$,.0f" } }
],
"xAxis":  { "columnId": "col-month", "sort": {"by": "col-month", "direction": "ascending"} },
"yAxis":  { "columnIds": ["col-rev"] },
"color":  { "by": "category", "column": "col-year",
            "scheme": ["#8FA6B2", "#ce785c"] }
```

Two years in the data → two lines. Three years → three lines. Reader
sees actual year labels in the legend (`2025`, `2026`) rather than
abstract tags.

**Why prefer this:** the color legend shows meaningful values the
reader recognizes. A viewer looking at a "2025 vs 2026" line chart
knows exactly what they're comparing.

### Synthesize a Period Tag only for bounded-window comparisons

When the ask is "last 30 days vs prior 30 days" or "current quarter
vs same-quarter-last-year" — bounded windows that don't map to a
single date-part — synthesize a tag column:

```json
{
  "id": "col-period-tag",
  "name": "Period",
  "formula": "If([Date] >= DateAdd(\"day\", -30, Today()), \"Current\", If([Date] >= DateAdd(\"day\", -60, Today()) And [Date] < DateAdd(\"day\", -30, Today()), \"Prior\", Null))"
}
```

Then color by `col-period-tag` with a curated 2-color scheme.

**When NOT to use Period Tag:** if the user's data spans years and
they want year-over-year, using a Period Tag to bucket into
"Current"/"Prior" throws away the year granularity — the viewer
can't tell whether "Prior" means last year or the year before. Use
date-part color instead.

Verified 2026-07-02 against a `Marketing-and-Promotions-Performance`
UI edit: the user replaced `Period Tag` with `Year` on the current-vs-
prior line chart to expose the year values directly, confirming the
preference above.

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
- **Small multiples** — not a native element kind. Build a container
  grid of small line/bar charts (one per metric); each is a normal
  chart element positioned in layout XML. Canonical example lives in
  `data-model-sourced-exec-kpi-scorecard.json` (Page 1 five-tile grid).

When the docs and the API disagree, trust the API error. When you're
not sure whether a field exists, fetch the OpenAPI schema for the
relevant element kind.
