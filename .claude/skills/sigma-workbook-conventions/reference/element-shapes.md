# Element shapes

Per-kind spec shape for every workbook element (charts, KPIs, pivots, controls, containers, text), plus visualization clarity rules and the misleading-`Invalid kind` error pattern. Load when authoring a specific element kind.

## Table of contents

- [Element source kinds](#element-source-kinds)
- [Element kinds — verified against the API](#element-kinds-verified-against-the-api)
- [KPI element shape](#kpi-element-shape)
- [Series breakout / color-by on charts](#series-breakout-color-by-on-charts)
- [Bar / line / area / combo chart shape](#bar-line-area-combo-chart-shape)
- [Bar chart `orientation` + categorical-axis sort rule](#bar-chart-orientation-+-categorical-axis-sort-rule)
- [Pie / donut chart shape](#pie-donut-chart-shape)
- [Scatter / bubble chart shape](#scatter-bubble-chart-shape)
- [Pivot-table element shape](#pivot-table-element-shape)
- [Container element shape](#container-element-shape)
- [Text element shape (titles, headings, narrative)](#text-element-shape-titles-headings-narrative)
- [Visualization clarity (REQUIRED for any chart/KPI)](#visualization-clarity-required-for-any-chartkpi)
- [Control catalog (`controlType` values)](#control-catalog-controltype-values)
- [Controls as formula values (the segmented-control pattern)](#controls-as-formula-values-the-segmented-control-pattern)
- [Control wiring](#control-wiring)

---

## Element source kinds

| `source.kind` | Reference fields | When to use |
|---------------|------------------|-------------|
| `data-model`  | `dataModelId` (UUID), `elementId` (node id from the data model) | Element is fed directly by a data-model node. |
| `table`       | `elementId` (sibling element id) | Element inherits from another workbook element on the same page. |
| `warehouse-table` | `connectionId` (UUID), `path` (`[DB, SCHEMA, TABLE]`) | Element pulls directly from a warehouse table (no data model). |

## Element kinds — verified against the API

All entries below are verified at POST/PUT/GET round-trip against the
Sigma staging API. For each, see the per-kind shape section further
down for the full required-field layout and any gotchas. Reference
example specs live in `examples/`.

| What you want | Spec `kind` | Encoding fields | Notes |
|---------------|-------------|-----------------|-------|
| Bar chart | `bar-chart` | `xAxis: {id}`, `yAxis: [{id}, ...]` | Single or grouped series. See "Bar / line / area / combo chart shape" below. |
| Line chart | `line-chart` | `xAxis: {id}`, `yAxis: [{id}]`, optional `color: {by, column}` | Series breakout uses the `{by, column}` shape with `column` as a bare id string — NOT `{id}`. See "Series breakout / color-by on charts." |
| Area chart | `area-chart` | `xAxis: {id}`, `yAxis: [{id}, ...]`, optional `stacking` | `stacking: "none"` = unstacked overlay, default = stacked, `"normalized"` = 100% stacked. |
| Combo chart | `combo-chart` | `xAxis: {id}`, `yAxis: [{id}, {id, type: "line"}, ...]` | Per-series `type` field on yAxis entries overrides the bar default — that's how you mix bars + lines on the same chart. |
| Scatter / bubble | `scatter-chart` | `xAxis: {id}`, `yAxis: [{id}]`, optional `size: {id}`, optional `color: {by, column}` | Both axes are metrics (not categorical). `size` makes it a bubble chart. |
| Pie chart | `pie-chart` | `color: {id}` (categorical), `value: {id}` (metric) | No xAxis/yAxis. The categorical column drives slice identity; the metric column drives slice size. |
| Donut chart | `donut-chart` | `color: {id}`, `value: {id}` | Same shape as pie-chart; render differs in the UI only. |
| KPI / single-value tile | `kpi-chart` | `value: {id}` plus a date dimension in `columns` for sparkline/comparison | **Docs example says `kpi` — API rejects with `Invalid kind: "kpi"`. Use `kpi-chart`.** See "KPI element shape." |
| Pivot table | `pivot-table` | `rowsBy: [{id}]`, `columnsBy: [{id}]`, `values: ["<col-id>", ...]` | **Only this exact shape — `rows`/`cols`/`values`-as-objects is rejected.** See "Pivot-table element shape." Cell-color conditional formatting is UI-only and breaks GET-spec when present. |
| Table | `table` | `columns: [...]`, optional `groupings`, optional `order` | Plain detail table by default; multi-level aggregating table when `groupings` carries `groupBy` + `calculations`. See "Table groupings." |
| Control | `control` (with `controlType: ...`) | `controlType` + type-specific fields | Catalog of `controlType` values in the "Control catalog" section. |
| Layout container | `container` | (element body is `{id, kind}` only) | Child placement happens in the layout XML via `<GridContainer>`. |
| Markdown text / heading | `text` | `body` (markdown), `verticalAlign` (`top \| middle \| bottom`) | Used for page titles, section headers, narrative blocks. |

When the docs and the API disagree, trust the API error and update this table.

### Unsupported element kinds (do not attempt at POST)

Per Sigma's official workbooks-as-code limitations
(<https://help.sigmacomputing.com/docs/manage-workbooks-as-code>), the
following are **explicitly out of scope** and will be rejected with
`Invalid kind`:

- **Maps** — all variants: `geography`, point maps, region maps. There is no
  workable kind value for spatial visualization in the spec today. If a
  geo view is the right answer for the analysis, build it in the UI; do not
  burn iterations probing kind names.
- Box plot, waterfall, sankey, funnel, gauge.
- Python elements, input tables, buttons, embeds, plugins, page breaks,
  value lists, repeated containers, tabbed containers, modals, popovers,
  navigation elements, forms, single-row containers, action sequences.

When the user asks for one of these viz types, surface the gap during the
plan step and propose a substitute that IS supported (e.g. swap map →
`line-chart` broken out by region, or → `bar-chart` ranked by location).

### GET-spec can 500 when UI features aren't representable

The GET-spec endpoint can return HTTP 500 (`code: service_error`) on a
workbook that's otherwise healthy — open-able in the UI, listed in
`/v2/files`, metadata fetchable via `GET /v2/workbooks/{id}`. Observed on
a workbook after UI edits added (a) conditional formatting on a
pivot-table and (b) a series breakout / color-by on a line chart. Both
v1 (pre-edit) and v2 (post-edit) of the same workbook returned 500,
while an unrelated workbook returned 200 on the same call.

**Confirmed trigger:** pivot-table cell-color conditional formatting
(heatmap visual). The toggle is reproducible:

| Workbook state | GET-spec |
|----------------|----------|
| Conditional formatting applied | 500 (`service_error`) |
| Conditional formatting removed via UI | 200 |
| Conditional formatting re-applied | 500 |
| Unrelated control workbook | 200 throughout |

Removing the formatting in the UI restores GET-spec to 200 instantly;
re-adding it 500s again. Affects **all** versions of the workbook, not
just the version containing the formatting — rollback-by-version-param
doesn't help.

The practical rule: configure cell-color conditional formatting **last**,
after any spec round-tripping for that workbook is done. Once it's
applied, GET-spec is dead for that workbook until it's removed again.

Other suspected triggers (untested) include other UI-only features
configurable but unrepresented in the code spec.

Hypothesis: when the UI saves a feature that isn't representable in the
code spec format, the serializer crashes instead of dropping the field
quietly. This affects ALL versions of that workbook, not just the
version containing the new feature — even rollback-by-version-param
doesn't help.

Diagnostic steps when GET-spec returns 500:

1. **Sanity check** another workbook's GET-spec (`/v2/workbooks/<other>/spec`)
   to rule out a global serializer outage. If the other workbook returns
   200, the problem is workbook-specific.
2. **Capture the `incident-id`** from the response body and file a Sigma
   support ticket — this is a server-side bug, not something the spec
   author can fix.
3. **Isolate the trigger via UI undo.** Undo one of the recent UI changes,
   save, retry GET-spec. If 200, that change is the culprit. Re-apply
   one at a time to confirm. Known-suspect features so far:
   - Pivot-table conditional formatting (heatmap cell coloring)
   - Line-chart series breakout / color-by dimension
4. **Don't try to repair via PUT** — overwriting with a known-good spec
   would destroy the new UI configuration. Read-only diagnosis until
   Sigma fixes the serializer or the user explicitly accepts that loss.

The wider implication: the workbooks-as-code feature is **not** a faithful
round-trip mirror of the UI. UI-only features sometimes silently drop
from GET responses; in this case they actively break GET. When promoting
patterns to this skill, prefer fields the docs example library
documents — and treat anything else as unstable until verified by a
clean round-trip.

### Misleading `Invalid kind` errors (POST validator quirk)

The POST validator's `Invalid kind: "<x>"` message sometimes masks a
**wrong field shape** rather than a genuinely unsupported kind. The
validator reports the kind it was trying to validate when it gave up,
not the field that confused it.

Verified case: a `line-chart` with a `color: {id: "ln-region"}`
series-breakout field returns `Invalid kind: "line-chart"`. The kind is
supported and the field is supported — the shape is wrong. The correct
shape is `color: {by: "category", column: "ln-region"}` (see "Series
breakout / color-by on charts" above). Round-tripping a UI-configured
chart via GET would have surfaced this immediately.

When you see `Invalid kind` on a kind you know is supported:

1. **Strip non-essential fields** back to the minimal docs example shape
   and confirm POST succeeds. This proves the kind isn't actually the
   issue.
2. **Add fields back one at a time.** The field whose addition flips
   POST from 200 to `Invalid kind` is the culprit.
3. **Check that field's shape against a GET-back of a real workbook**
   that uses the feature — UI-configured workbooks are the
   source of truth for non-obvious field shapes (column refs as bare
   strings vs `{id}` objects, etc.).

Don't chase kind-name variants until you've ruled out an extraneous or
misshapen field.


## KPI element shape

Minimal (number only):

```json
{
  "id": "kpi-revenue",
  "kind": "kpi-chart",
  "name": "Total Revenue",
  "source": { "kind": "table", "elementId": "<sibling-table-id>" },
  "columns": [
    { "id": "kpi-rev-value", "name": "Revenue", "formula": "[Metrics/Revenue]" }
  ],
  "value": { "id": "kpi-rev-value" }
}
```

With timeline comparison (preferred — gives readers period-over-period
context). Add a date-dimension column to the `columns` array. Sigma renders
the comparison/sparkline automatically when both a `value` column and a date
dimension are present:

```json
{
  "id": "kpi-revenue",
  "kind": "kpi-chart",
  "name": "Total Revenue",
  "source": { "kind": "table", "elementId": "<sibling-table-id>" },
  "columns": [
    { "id": "kpi-rev-month", "formula": "DateTrunc(\"month\", [Date])" },
    { "id": "kpi-rev-value", "name": "Revenue", "formula": "[Metrics/Revenue]" }
  ],
  "value": { "id": "kpi-rev-value" }
}
```

`value.id` points at the column whose value is rendered as the tile number.
The column's `formula` is typically `[Metrics/<Name>]` so currency/percent
formatting carries through from the data model. A KPI with a time-series
metric should always include the date-dimension column for the comparison.

The specific comparison **period** Sigma renders (vs prior month / quarter /
year) is UI-side state and isn't part of the code representation — see
"Scope of the code representation" at the top of this file. If a particular
period is required, configure it in the UI; the spec only carries the date
column that enables comparison-mode at all.

A bare KPI (just a number, no title, no comparison) is **not enough** for a
useful dashboard — see Visualization clarity below.

## Series breakout / color-by on charts

For chart kinds that support series breakout by a categorical dimension
(verified on `line-chart`; almost certainly applies to `bar-chart`,
`area-chart`, `combo-chart`, `scatter-chart`), the field is `color` —
but its shape is **not** `{id: ...}` like `xAxis` / `yAxis`. Sending the
`{id}` shape gets rejected with the masked error
`Invalid kind: "<chart-kind>"`.

Correct shape (verified via GET-back from a UI-configured line chart):

```json
"color": {
  "by": "category",
  "column": "ln-region"
}
```

- `by`: the breakout mode. `"category"` for discrete-dimension series
  (one line per region, one bar series per family, etc.). Other values
  likely exist for continuous gradients — discover via GET-back.
- `column`: the column **id** (string), NOT an object. This is one of
  the few places in the spec where a column reference is a bare id
  rather than `{id: "..."}`.

To match an exact `kind`-error symptom to this fix: if the validator
rejects `<chart-kind>` and your spec has a `color` field shaped like
`{id: "..."}`, that's the cause — change to `{by, column}`.

## Bar / line / area / combo chart shape

These four share the xAxis/yAxis pattern. Differences:

- `bar-chart`, `line-chart`, `area-chart` accept a single y-axis array
  of metric columns. Multi-series breakout uses `color: {by, column}`.
- `combo-chart` mixes bar + line in the same chart by giving each
  `yAxis` entry an optional `type` override (`"line"` for line-style,
  default is bar-style for `combo-chart` / what the `kind` implies).
- `area-chart` accepts an optional `stacking` field:
  - default (omitted) — stacked
  - `"none"` — unstacked overlay (each series drawn from the baseline)
  - `"normalized"` — 100%-stacked (each y value normalized to its
    column sum)

Minimal area-chart (stacked):

```json
{
  "id": "area-revenue-cogs",
  "kind": "area-chart",
  "name": "Revenue vs COGS — Monthly",
  "source": { "kind": "table", "elementId": "<sibling>" },
  "columns": [
    { "id": "ar-month",   "formula": "DateTrunc(\"month\", [Date])" },
    { "id": "ar-revenue", "formula": "[Metrics/Revenue]" },
    { "id": "ar-cogs",    "formula": "[Metrics/COGS]" }
  ],
  "xAxis": { "id": "ar-month" },
  "yAxis": [ { "id": "ar-revenue" }, { "id": "ar-cogs" } ]
}
```

Combo chart with one bar series + one line series:

```json
{
  "kind": "combo-chart",
  "xAxis": { "id": "month-col" },
  "yAxis": [
    { "id": "revenue-col" },
    { "id": "profit-margin-col", "type": "line" }
  ]
}
```

Add `color: {by: "category", column: "<col-id>"}` to break either of
these into multiple series (e.g. one line per region). The `column`
value is a bare id string, not an `{id}` object — see "Series breakout
/ color-by on charts."

Reference example with all variants:
`examples/additional-workbook-features-chart-and-control-catalog.json`.

## Bar chart `orientation` + categorical-axis sort rule

Bar charts accept `orientation: "horizontal" | "vertical"` (default vertical).
Discovered via UI-toggle + GET-back diff. **Bar charts only** — line/area/
combo/scatter use time-on-x or metric-on-x by design.

| X-axis type | Examples | `orientation` | `xAxis.sort` |
|---|---|---|---|
| Categorical | Segment, Tenure, Region | `"horizontal"` | `{by: "<y-col-id>", direction: "descending"}` |
| Time-series | Month, Week, Day | omit (vertical) | `{by: "<x-col-id>", direction: "ascending"}` |

Why categorical → horizontal + descending: dodges Sigma's auto-label-rotation
(labels read left-aligned on Y axis) AND ranks largest→smallest, the
conventional categorical read order. Horizontal on time-series compresses
the time scale.

## Pie / donut chart shape

Pie and donut charts use a different encoding from xAxis/yAxis charts.
They have two required fields:

- `color: {id: "<categorical-col-id>"}` — the dimension whose values
  become slice identities.
- `value: {id: "<metric-col-id>"}` — the metric whose values become
  slice sizes.

```json
{
  "id": "donut-revenue-by-family",
  "kind": "donut-chart",
  "name": "Revenue by Product Family",
  "source": { "kind": "table", "elementId": "<sibling>" },
  "columns": [
    { "id": "dn-family",  "formula": "[<table>/Product Family]" },
    { "id": "dn-revenue", "formula": "[Metrics/Revenue]" }
  ],
  "color": { "id": "dn-family" },
  "value": { "id": "dn-revenue" }
}
```

Switching `kind: "pie-chart"` ↔ `kind: "donut-chart"` is the only
spec-level difference between the two.

## Scatter / bubble chart shape

Both axes are metrics (not categorical). Each row of the underlying
data becomes one point. Optional encodings:

- `size: {id: "<metric-col-id>"}` — bubble-sizes the point. Without
  this, all points are the same size (pure scatter).
- `color: {by: "category", column: "<categorical-col-id>"}` — same
  shape as on line/area/bar; colors points by a categorical dimension.

```json
{
  "id": "scatter-revenue-vs-margin",
  "kind": "scatter-chart",
  "name": "Revenue vs Profit Margin — Stores",
  "source": { "kind": "table", "elementId": "<sibling>" },
  "columns": [
    { "id": "sc-store",    "formula": "[<table>/Store Name]" },
    { "id": "sc-revenue",  "formula": "[Metrics/Revenue]" },
    { "id": "sc-margin",   "formula": "[Metrics/Profit Margin]" },
    { "id": "sc-region",   "formula": "[<table>/Store Region]" }
  ],
  "xAxis": { "id": "sc-revenue" },
  "yAxis": [ { "id": "sc-margin" } ],
  "size":  { "id": "sc-revenue" },
  "color": { "by": "category", "column": "sc-region" }
}
```

If you need to plot each dot at the **same point's grain** as the
source rows, that's just one row → one point. If you need points
aggregated per dimension (e.g. one point per store, not per
transaction), the underlying source element must do that aggregation
first — either via `groupings` or by sourcing from a pre-aggregated
sibling.

## Pivot-table element shape

Pivot tables ARE supported at POST (despite being absent from the "supported
chart types" list in the docs page) — but the field shape is **not** the
same as the chart elements' `xAxis`/`yAxis` pattern. Field names that look
right but are wrong: `rows`, `cols`, `values: [{id: ...}]`.

The correct shape (matches
<https://help.sigmacomputing.com/docs/example-representation-workbook-with-a-pivot-table>):

```json
{
  "id": "chart-store-family-heatmap",
  "kind": "pivot-table",
  "name": "Units by Store × Product Family",
  "source": { "kind": "table", "elementId": "<sibling-table-id>" },
  "columns": [
    { "id": "pvt-store-name",       "name": "Store Name",       "formula": "[<table>/Store Name]" },
    { "id": "pvt-product-family",   "name": "Product Family",   "formula": "[<table>/Product Family]" },
    { "id": "pvt-units",            "name": "Units",            "formula": "Sum([<table>/Quantity])" }
  ],
  "rowsBy":    [ { "id": "pvt-store-name" } ],
  "columnsBy": [ { "id": "pvt-product-family" } ],
  "values":    [ "pvt-units" ]
}
```

Critical field-shape rules:

- `rowsBy` (NOT `rows`) — array of `{id}` objects pointing at row-grouping columns.
- `columnsBy` (NOT `cols`) — same shape, for column-grouping columns.
- `values` — array of **id strings** (e.g. `["pvt-units"]`), NOT objects like
  `[{"id": "pvt-units"}]`. The objects-form is rejected.
- Cell-color conditional formatting (the "heatmap" visual) is UI-side; the
  spec sets up the pivot structure but cell coloring is not in the code
  representation.

## Container element shape

Containers group other elements into a logical visual block (header bar,
KPI row, etc.) and let layout coordinates be expressed relative to the
container's own grid. The element body is intentionally minimal:

```json
{ "id": "container-header", "kind": "container" }
```

All child placement is in the layout XML using `<GridContainer>` — see
Layout below.

## Text element shape (titles, headings, narrative)

```json
{
  "id": "text-page-title",
  "kind": "text",
  "body": "## **Sales Overview Dashboard**",
  "verticalAlign": "middle"
}
```

`body` accepts markdown (headings, bold, links, lists). `verticalAlign` is
`top`, `middle`, or `bottom`. Use a text element at the top of every page for
the page title — the workbook's `name` field is metadata only and isn't
rendered as a visible heading.

## Visualization clarity (REQUIRED for any chart/KPI)

Every visualization must give the reader enough context to interpret it
without asking. A naked number or a chart without a title is a defect, not a
minimal-viable element.

For every chart, KPI, or pivot in a workbook, configure at minimum:

1. **A page-level title text element** at the top of every page. Use a `text`
   element with markdown body (`## **Page Name**`) inside the header
   container. The workbook `name` field is metadata only and isn't rendered
   as a visible heading.
2. **A descriptive title (the element's `name` field)** on every chart/KPI/
   table that names the metric and the slice (e.g. `Total Revenue` not
   `Revenue`; `Revenue by Month` not `Revenue`).
3. **A comparison or context** that lets the reader judge whether the value
   is good/bad/normal:
   - **KPIs**: include a date-dimension column in the KPI's `columns` array
     (e.g. `DateTrunc("month", [Date])`) so Sigma renders a period-over-period
     comparison and sparkline alongside the headline number. KPIs without
     this lose the most analytical value.
   - **Bar/line/area charts**: clear axis labels with units, sort order that
     reflects narrative (descending by value, or chronological for time), and
     a meaningful default time window.
4. **Format units explicitly** — currency symbols, % suffix, K/M/B
   abbreviation. Inheriting `[Metrics/X]` from the data model usually carries
   the format, but verify after CREATE — if the tile shows `12345.67` instead
   of `$12,345.67`, the format didn't propagate.
5. **Size for legibility.** A KPI with a sparkline needs ~8–10 grid rows of
   vertical space, not 3. A 3-row KPI with timeline comparison renders the
   sparkline too small to read.

The CREATE endpoint accepts a KPI with no title or comparison — it just
won't be useful. The skill's job is to refuse to ship one.

**Field-name TODO** — the exact JSON spec fields for KPI title visibility,
comparison period, and sparkline are not documented in Sigma's public help
docs (UI-level docs only). Discover them by configuring a KPI in the UI,
then `GET /v2/workbooks/{id}/spec` and diff against the previous spec.
Update this section with the field names once known.


## Control catalog (`controlType` values)

Every control has `kind: "control"`, a workbook-unique `controlId`,
and a type-specific shape. Verified types:

### `date-range`

Filters a date column to a between-bounded range.

```json
{
  "kind": "control",
  "id": "ctrl-date-range",
  "controlId": "DateRange",
  "controlType": "date-range",
  "mode": "between",
  "includeNulls": "when-no-value-is-selected",
  "filters": [{
    "source": { "kind": "table", "elementId": "<target>" },
    "columnId": "<target-element-column-id>"
  }]
}
```

### `list` (categorical-pick filter)

A dropdown filter populated from a column's distinct values.

```json
{
  "kind": "control",
  "id": "ctrl-region",
  "controlId": "StoreRegion",
  "controlType": "list",
  "mode": "include",
  "selectionMode": "multiple",
  "values": [],
  "source": {
    "kind": "source",
    "source": { "kind": "table", "elementId": "<target>" },
    "columnId": "<target-element-column-id>"
  },
  "filters": [{
    "source": { "kind": "table", "elementId": "<target>" },
    "columnId": "<target-element-column-id>"
  }]
}
```

`selectionMode: "single"` for single-select; default is `"multiple"`.

### `text` (string filter)

Free-text filter on a string column.

```json
{
  "kind": "control",
  "id": "ctrl-product-name",
  "controlId": "Product-Name",
  "controlType": "text",
  "case": "insensitive",
  "mode": "contains",
  "value": "",
  "includeNulls": "when-no-value-is-selected",
  "showOperators": true,
  "filters": [{
    "source": { "kind": "table", "elementId": "<target>" },
    "columnId": "<target-element-column-id>"
  }]
}
```

- `case: "insensitive" | "sensitive"`.
- `mode: "contains" | "starts-with" | "equals" | ...` — operator-style
  match. `showOperators: true` exposes a dropdown to the end user so
  they can change the operator at view time.

### `number-range` (numeric range filter)

Filters a numeric column to a min/max range. Defaults are derived from
the column's data range at view time.

```json
{
  "kind": "control",
  "id": "ctrl-price",
  "controlId": "Price",
  "controlType": "number-range",
  "includeNulls": "when-no-value-is-selected",
  "filters": [{
    "source": { "kind": "table", "elementId": "<target>" },
    "columnId": "<target-element-column-id>"
  }]
}
```

### `segmented` (value-provider toggle, NOT a column filter)

A button-row selector that produces a single value referenceable from
formulas anywhere in the workbook. **Does NOT have a `filters` field**
— it doesn't filter a column. Instead, other elements consume the
control's value via formula references.

```json
{
  "kind": "control",
  "id": "ctrl-date-segment",
  "controlId": "Date-Segment",
  "controlType": "segmented",
  "value": "month",
  "source": {
    "kind": "manual",
    "valueType": "text",
    "values": ["year", "quarter", "month", "week", "day"],
    "labels": ["Year", "Quarter", "Month", "Week", "Day"]
  }
}
```

- `value` is the default selection (one of `source.values`).
- `source.values` are the raw values stored on selection; `source.labels`
  are the UI display labels (same index → same option).
- `valueType` is the type of the values (`"text"`, `"number"`, etc.).

How to consume the value in a formula — see the next section.

## Controls as formula values (the segmented-control pattern)

A control's `controlId` is referenceable inside a formula by name in
square brackets — the same syntax as a column reference. This lets a
control's selected value drive calculations and chart axes, not just
filter rows.

Canonical example: a `segmented` control with `controlId: "Date-Segment"`
and values `year | quarter | month | week | day` lets the user toggle
the time grain of a chart. The chart's xAxis column references the
control inside `DateTrunc`:

```json
{
  "id": "chart-revenue-trend",
  "kind": "combo-chart",
  "source": { "kind": "table", "elementId": "<sibling>" },
  "columns": [
    {
      "id": "col-trend-period",
      "formula": "DateTrunc([Date-Segment], [Date])"
    },
    { "id": "col-revenue", "formula": "[Metrics/Revenue]" }
  ],
  "xAxis": { "id": "col-trend-period" },
  "yAxis": [ { "id": "col-revenue" } ]
}
```

When the user clicks "Quarter," the chart re-truncates the date column
to quarter boundaries without re-specifying any other element.

Where this pattern shines:

- Time-grain togglers (year/quarter/month/week/day).
- Currency / unit selectors that swap between metric formulas.
- Per-element threshold inputs (e.g. anomaly z-score cutoff) that
  drive `If()` cell colorings.
- Top-N selectors that drive `Rank() <= [TopN]` filters.

Naming convention: give segmented controls a hyphenated or PascalCase
`controlId` so the bracket reference reads naturally in formulas
(`[Date-Segment]`, `[TopN]`, `[CurrencyMode]`).

Other control types can also be referenced this way (a `text` control's
value, a `number-range` control's bounds, a `list` control's selected
values). The segmented pattern is the cleanest because it provides a
small enumerated set of options that maps directly to formula
parameters.

## Control wiring

```json
{
  "kind": "control",
  "controlId": "Date",
  "controlType": "date-range",
  "id": "ctrl-date-range",
  "filters": [
    {
      "source": { "kind": "table", "elementId": "<target-element-id>" },
      "columnId": "<target-element-column-id>"
    }
  ],
  "mode": "between",
  "includeNulls": "when-no-value-is-selected"
}
```

`filters[].columnId` is the column `id` on the target element — NOT the column
name. When you author the target element, give the column a stable, readable id
(e.g. `col-date`) so the control binding is legible. Auto-generated IDs
(`zjXo8KcTRL`) work but make the spec harder to read and diff.

**`controlId` is workbook-wide unique, not page-scoped.** Reusing
`controlId: "Date"` on a control on a second page is rejected at POST:

```
pages[1].elements[N].controlId: Duplicate id: 'Date'
```

When the same logical filter (Date Range, Customer Region, etc.) appears on
multiple pages, give each page's control a distinct `controlId`
(`Date` / `DateP2`, or namespace by page: `p1-date` / `p2-date`). The
element `id` is already required to be unique; `controlId` adds a second
uniqueness axis on top. If you genuinely want both pages' controls to drive
the same filter state, that's a workbook-level shared control — not modeled
by giving them the same `controlId`, but by wiring one control's `filters[]`
to elements on multiple pages.

