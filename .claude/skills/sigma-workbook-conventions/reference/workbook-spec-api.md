# Workbook Spec API — Reference

Canonical patterns for `POST/GET/PUT /v2/workbooks/spec`. These rules are the
result of iteration loops where the create endpoint accepted broken specs that
failed at render time. Read this before authoring any workbook spec.

## Layout rules — read before authoring multi-page

Three rules that the POST validator does not enforce. Sigma silently rewrites
the layout when any of them is broken, producing a workbook that opens but
looks wrong:

1. **`layout` is a top-level workbook field.** A `layout` placed under
   `pages[i]` is **silently discarded** by the API (verified 2026-05-11).
   The agent's expected output is one top-level `layout` string for the whole
   workbook.
2. **Multi-page = one `<?xml>` declaration + multiple `<Page>` siblings.** No
   outer wrapper element. Sigma's XML parser tolerates the multi-root form;
   the GET-back preserves it.
3. **Container children must be nested inside `<GridContainer>` in the XML.**
   The order of entries in `pages[].elements` does NOT define visual
   structure. A `<GridContainer>` with no nested `<LayoutElement>` /
   `<GridContainer>` children renders as an empty box, and all the elements
   you *thought* were inside it stack flat at the bottom of the page in a
   1/13-wide single column.

Run `scripts/validate-spec.py <spec.json>` before every POST/PUT — it checks
all three.

Example of the correct shape:

```xml
<?xml version="1.0" encoding="utf-8"?>
<Page type="grid" gridTemplateColumns="repeat(24, 1fr)" gridTemplateRows="auto" id="page-overview">
  <GridContainer elementId="container-hdr" type="grid"
                 gridColumn="1 / 25" gridRow="1 / 4"
                 gridTemplateColumns="repeat(24, 1fr)" gridTemplateRows="auto">
    <LayoutElement elementId="text-title" gridColumn="1 / 9" gridRow="1 / 4"/>
    <LayoutElement elementId="ctrl-date"  gridColumn="9 / 25" gridRow="1 / 4"/>
  </GridContainer>
  <LayoutElement elementId="chart-bar" gridColumn="1 / 25" gridRow="4 / 18"/>
</Page>
<Page type="grid" gridTemplateColumns="repeat(24, 1fr)" gridTemplateRows="auto" id="page-detail">
  ...
</Page>
```

Note: the layout XML at the bottom of this file (under "Layout") shows the
single-page case. Promote what's above when authoring multi-page workbooks.

## Scope of the code representation

The workbooks-as-code feature is **not a fully scoped definition of a Sigma
workbook**. Some element properties that are configurable in the UI are not
addressable in the spec, and a GET-back of a UI-configured workbook will not
necessarily round-trip every visual setting. Known examples (treat as
limitations, not bugs to fix):

- **KPI period-comparison configuration** (e.g. "vs prior month" vs "vs prior
  quarter"): the spec only carries the date-dimension column on the KPI's
  `columns` array. The actual comparison period Sigma renders from that
  column is UI-side state and isn't surfaced in the GET response. If a user
  needs a specific comparison period, configure it in the UI; don't try to
  set it in the spec.
- **Pivot-table cell-color conditional formatting (heatmap visual)**: the
  pivot structure (`rowsBy`, `columnsBy`, `values`) goes through the
  spec, but cell-color conditional formatting that produces the "heatmap"
  look is UI-only AND **also breaks the GET-spec endpoint** on any
  workbook where it's present — see "GET-spec can 500 when UI features
  aren't representable" below. Configure cell-color formatting last,
  after you've finished any spec round-tripping.
- (Add new findings here when you discover other UI-only properties.)

The practical implication for the iteration loop: when a user UI-fix changes
something visible but the diff against the prior spec is empty, that property
lives outside the code representation. Note it here and move on — don't burn
iterations searching for a field that doesn't exist.

## Endpoints

| Method | Path | Notes |
|--------|------|-------|
| `POST` | `/v2/workbooks/spec` | Create. Body is JSON or YAML. Required: `name`, `schemaVersion: 1`, `folderId`, `pages`. Optional: `layout`. POST defaults to YAML response — pass `Accept: application/json` for JSON. |
| `GET`  | `/v2/workbooks/{workbookId}/spec` | **Defaults to YAML.** Pass `Accept: application/json` for JSON. |
| `PUT`  | `/v2/workbooks/{workbookId}/spec` | Full-spec update; no partials. |
| `DELETE` | _unknown_ | **Open issue:** both `DELETE /v2/workbooks/{id}` and `DELETE /v2/files/{id}` return 404 against staging for workbooks the same token just CREATEd. Until the right endpoint is found, test workbooks accumulate and need manual UI cleanup. Discover via Sigma docs / network tab on a UI delete. |

`folderId` is the **internal UUID** (e.g. `eb548e3b-...`), NOT the urlId
(`7a3Q0z79Bx1H42pxjd0qWn`). Look up via `GET /v2/files/{urlId}` — both are returned.

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

## The column-declaration rule (MOST IMPORTANT)

**There is no implicit column inheritance into a workbook element from its source.**
You MUST declare every column you intend to use, with a stable `id`. The CREATE
endpoint will accept specs whose downstream references can't be resolved — the
broken element fails silently at render time.

Concretely:
- A bar chart sourced from a sibling table can only reference columns it has
  redeclared on its own `columns` array. Inheriting "via source" without
  redeclaration produces a chart that won't render.
- A control's `filters[].columnId` must match a column `id` declared on the
  target element. Referencing the column NAME (`"Date"`) instead of its `id`
  silently breaks the filter wiring.

Practical pattern when authoring from scratch: declare ALL columns of the
data-model element on the table (passthrough), even if the table will display
them. Then chart/control references downstream resolve correctly.

### Drill-down corollary: passthrough on visualizations, not just tables

The rule above keeps the formula resolver happy. There's a second reason
to declare every source column on every visualization: **right-click
drill-down in Sigma only exposes columns that element declares**. A bar
chart of `Revenue by Region` that only declares `region`, `revenue`,
and the metric's material columns gives the reader no path from
region → state → city → store, even though those columns exist on the
source table.

Default rule when generating a chart, KPI, or pivot: copy the parent
table's full passthrough column set onto the viz element (each as a
sibling-namespaced formula like `[Transactions/Store State]`), then
add the chart-specific derived columns (axis-derived dates, buckets,
etc.) on top. Only the encoding-bound columns appear in `xAxis`/`yAxis`/
`color`/`size`, but the others are present and drillable.

Exceptions are rare: skip passthrough only when the source table has
many columns (50+) and most are conceptually irrelevant to the page's
question. Almost everywhere else, default to passthrough-all.

## The explicit-`name` rule (also load-bearing at POST time)

**Set an explicit `name` on every column referenced by display name from a
sibling element.** A passthrough column without `name`:

```json
{ "id": "col-date", "formula": "[Plugs Transaction Details - Relationships/Date]" }
```

works in a GET-back exemplar (Sigma renders the inferred name "Date"), but
fails at POST with:

```
Cannot resolve column ... dependency not found:
formula reference 'plugs transaction details/date'
```

because the cross-element resolver looks up by display name and the column
doesn't have one yet at validation time. The fix is to declare it
explicitly:

```json
{ "id": "col-date", "name": "Date", "formula": "[Plugs Transaction Details - Relationships/Date]" }
```

Apply this to every column on a workbook table that downstream KPIs,
charts, or controls will reference via `[<TableDisplayName>/<ColumnName>]`.
For internal-only columns (e.g. an aggregation result that only the
element itself uses) `name` is still good practice but not load-bearing.

## Verify data-model columns resolve before relying on them

A column listed under `elements[].columns` in `GET /v2/dataModels/{id}/spec`
is **not guaranteed to be queryable** from a workbook spec. We've observed
columns that appear in the spec JSON (with a normal-looking
`formula: "[<warehouse-source>/<col>]"`) but fail formula resolution at
POST time:

```
dependency not found: formula reference
'plugs transaction details - relationships/cust key'
```

This happened with `Cust Key`, `Customer Name`, and `Cust Json` on the
`Plugs Transaction Details - Relationships` join element — other columns
on the same element (Date, Quantity, Store Region, etc.) resolved
normally. Hypothesis: the data-model element has stale or orphaned
column definitions whose underlying warehouse source doesn't actually
expose them, and the data-model spec serialization includes them anyway.

**Probe pattern.** When pulling unfamiliar or recently-added columns,
POST a one-table workbook with just those columns first as a smoke test:

```json
{
  "name": "PROBE",
  "schemaVersion": 1,
  "folderId": "<uuid>",
  "pages": [{
    "id": "p1", "name": "p1",
    "elements": [{
      "id": "tbl", "kind": "table", "name": "T",
      "source": { "kind": "data-model", "dataModelId": "...", "elementId": "..." },
      "columns": [
        { "id": "c1", "name": "Cust Key", "formula": "[<Element Name>/Cust Key]" }
      ]
    }]
  }]
}
```

400 → the column is unusable from this element. Pivot to warehouse-source
(see below) or pick a different join key. 200 → safe to build on.

## Falling back to `warehouse-table` source

When a data-model element has unusable columns you actually need, source
the workbook table directly from the underlying warehouse table. Pull
the connection ID and path from the data-model element's
`source.primarySource` (for join elements) or `source` (for
warehouse-table elements):

```json
{
  "id": "tbl-plugs-tx",
  "kind": "table",
  "name": "Plugs Transaction Details",
  "source": {
    "kind": "warehouse-table",
    "connectionId": "1653d1af-46f3-4bcf-a754-6fefc004332f",
    "path": ["RETAIL", "PLUGS_ELECTRONICS", "PLUGS_ELECTRONICS_HANDS_ON_LAB_DATA"]
  },
  "columns": [
    { "id": "col-cust-key", "name": "Cust Key",
      "formula": "[PLUGS_ELECTRONICS_HANDS_ON_LAB_DATA/Cust Key]" }
    /* ... */
  ]
}
```

**Tradeoffs of warehouse-source vs data-model-source:**

| Capability | `data-model` | `warehouse-table` |
|---|---|---|
| `[Metrics/<Name>]` formulas | ✅ | ❌ — replace with inline `Sum(...)` etc. |
| Carries data-model column-level security/formatting | ✅ | ❌ |
| Works around orphaned columns on a data-model element | ❌ | ✅ |
| Survives data-model schema renames upstream | ✅ (Sigma re-resolves) | ❌ (warehouse path is brittle) |

Prefer data-model source by default; reach for warehouse-source only when
you've confirmed a needed column doesn't resolve via the data-model
element. When you do, replace each `[Metrics/X]` reference with the
equivalent inline aggregation (e.g. `Sum([Quantity] * [Price])` for
Revenue, `Sum([Quantity] * [Cost])` for COGS).

## Verifying correctness via generated SQL

The spec's `POST` and `PUT` will succeed (HTTP 200) for specs whose
formulas have *semantic* bugs that the API can't catch. A common case:
referencing a non-aggregated sibling column that you intended to be
aggregated. The lookup compiles to a `LEFT JOIN` against per-row data
instead of a per-group aggregate, downstream calcs silently go NULL,
and the workbook renders empty cells.

To catch this without opening the UI, query the SQL Sigma generated
for each element:

```bash
curl -H "Authorization: Bearer $TOKEN" \
  "$SIGMA_BASE_URL/v2/workbooks/<id>/elements/<element-id>/query" \
  | jq -r '.sql'
```

What to look for, in order of importance:

1. **Expected `GROUP BY`** on aggregating elements. If you wrote
   `Rollup(Min(...), [key], [target/key])` and the SQL has no
   `group by` in the joined subquery, the Rollup didn't compile as an
   aggregation — likely the target reference is wrong or the local
   element is single-tier off `warehouse-table`.
2. **No `iff(equal_null(min, max), max, null)` patterns** unless you
   genuinely want Lookup semantics. That pattern is Sigma's defensive
   NULL-return for ambiguous Lookups (multiple matches with different
   values) — a sign your "aggregation" is silently returning NULL.
3. **Expected expressions in select clause** match what your formulas
   describe (`Q1.QUANTITY * Q1.PRICE`, `date_trunc(month, ...)`, etc.).
   If a calc is missing from select, the formula was likely dropped
   silently — happens when an aggregate function is used in a context
   Sigma doesn't recognize as aggregatable.

Run this check after any spec POST/PUT that involves windowed
aggregation, cross-element joins, or derived calculations. It's the
fastest way to validate the math without sampling cell values in the
UI.

## Cross-element joins via `Lookup()`

To join two workbook elements without modifying the underlying data
model, use `Lookup()` formulas on the target element. The target needs:

- The local key column (e.g. `Cust Key`) declared with an explicit
  `name`, so it can be referenced as `[Cust Key]` from formulas on the
  same element.
- A sibling element on the same page sourcing the lookup table (data-model
  or warehouse) — Lookup needs a workbook element to resolve against, not
  a raw data-model reference.

Then each looked-up column is one passthrough formula:

```
Lookup([<Target Element Display Name>/<Target Column>], [<Local Key>], [<Target Element Display Name>/<Target Key>])
```

Example — bringing customer demographics from a `Customer Details`
sibling table into `Plugs Transaction Details` joined on `Cust Key`:

```json
{ "id": "col-cust-region", "name": "Cust Region",
  "formula": "Lookup([Customer Details/Cust Region], [Cust Key], [Customer Details/Cust Key])" }
```

The lookup-source element doesn't have to be the visual focus of the
page — but it must exist on the page and be placed in the layout XML.
Place it at the bottom under the detail table; users can scroll to it
but it stays out of the headline view.

## Column `format` — undocumented, omit at POST

Setting `format: { type: "number", format: "currency", currency: "USD" }`
on a column is rejected:

```
pages[0].elements[N].columns[M].format: Missing "kind" field
```

The required `kind` value is not in the public docs. Until the shape is
discovered (configure currency in the UI → `GET /v2/workbooks/{id}/spec`
→ diff), **omit `format` from POST bodies entirely** and configure
currency/percent formatting in the UI after CREATE. Replace this section
with the discovered shape once known.

## Looking up Sigma functions

This skill documents **patterns** (Lookup, Rollup, multi-level
groupings, materialize-then-window) and verified spec shapes. It does
NOT enumerate every Sigma formula function — that lives in Sigma's
official docs.

Retrieve current function documentation via the native
`mcp__claude_ai_Sigma_Docs__*` MCP integration (no auth, no bash, no
`WebFetch`):

- `mcp__claude_ai_Sigma_Docs__search` — keyword search for a function
  by name or topic ("is there a function that does X"). Returns
  `{id, title, url}` for top matches.
- `mcp__claude_ai_Sigma_Docs__fetch` — pull the full docs page for a
  specific function by id (returned by `search`).

Schemas load via `ToolSearch` on first use
(`select:mcp__claude_ai_Sigma_Docs__search,mcp__claude_ai_Sigma_Docs__fetch`).
Allowlisted in `.claude/settings.json` so calls run silent.

For Sigma's REST API endpoint reference (request/response shapes,
parameters, paths), the same MCP server exposes:

- `mcp__claude_ai_Sigma_Docs__list-endpoints` — full path/method index
- `mcp__claude_ai_Sigma_Docs__search-endpoints` — keyword search
- `mcp__claude_ai_Sigma_Docs__get-endpoint` — fetch a specific endpoint

Practical convention: when authoring a spec and you need a function
beyond the ones already documented in this skill, do a `search` →
`fetch` round-trip rather than guessing the signature from training
data. Sigma's function semantics (e.g. argument order on `Rollup`,
`DateLookback`, `DateAdd`) are too easy to misremember, and the cost
of a malformed formula is a silent NULL or an `iff(equal_null, …)`
defensive wrap in the SQL, not a POST error.

What this skill does cover natively (no need to look up):

- `Lookup`, `Rollup`, `DateLookback` — full sections with shape + when
  to use which.
- `[Metrics/<Name>]` reference syntax for data-model metrics.
- `[<sibling-element-display-name>/<column-name>]` cross-element refs.
- The materialize-then-window rule (you can't put `Min`, `Max`, `Sum`,
  `Rank` etc. directly on top of an unmaterialized expression).

Everything else — date math, string ops, conditional, statistical,
trig, type conversion — defer to `Sigma_Docs` MCP lookups.

## Formula namespaces

Formulas inside an element resolve column references against:

1. The element's **own** `columns` (bare names like `[Price]`, `[Revenue]`).
2. The **source element's** namespace, addressed as
   `[<Source Element Display Name>/<Column Name>]`.
3. The **data-model metric** namespace: `[Metrics/<Metric Name>]`.

| Element | Source kind | Formula style for upstream columns |
|---------|-------------|-------------------------------------|
| Table fed by data-model element `Plugs Transaction Details - Relationships` | `data-model` | `[Plugs Transaction Details - Relationships/Date]` |
| Bar chart fed by sibling table named `Plugs Transaction Details` | `table` | `[Plugs Transaction Details/Date]` |
| Calc on the table itself | (own namespace) | `[Price] * [Quantity]` |

Note that when the table's `name` differs from the data-model element's name,
the chart's reference uses the **table's display name**, not the upstream
data-model element's name.

## Use data-model metrics before hand-deriving

If the data model defines a metric that matches what you want to compute,
reference it via `[Metrics/<Metric Name>]`. Do not redo the math in the
workbook. Reasons:

- The metric carries formatting (currency, percent, decimals).
- Single source of truth — if the metric formula changes, the workbook tracks
  automatically.
- Less spec churn when the warehouse columns rename or restructure.

Discover available metrics with `jq '.. | objects | select(.metrics) | .metrics'`
on `GET /v2/dataModels/{id}/spec`. They live on the node element's `metrics`
array. Always check this BEFORE writing a custom calc.

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

## Table groupings — multi-level aggregation in tables

`groupings[]` on a table element creates a multi-level
hierarchically-aggregated table. Each entry is one **level** in the
hierarchy and binds a grouping dimension column to a set of
aggregation columns that are computed at that level's grain. The
generated SQL has real `GROUP BY` clauses — multiple, one per level,
joined together so each detail row carries the aggregates from its
ancestor levels.

The canonical example (saved to
`examples/data-model-sourced-multi-level-aggregated-table.json`)
defines three levels: Product Type → Product Line → Week of Date.
Each level owns its own aggregation columns.

### Shape (USE THIS — supersedes earlier `{id, columnId}` and `{id}`-only forms)

```json
"groupings": [
  {
    "id": "xnekFIqVJZ",
    "groupBy":     ["col-id-product-type"],
    "calculations": ["col-id-revenue", "col-id-profit-margin"]
  },
  {
    "id": "nYYmPerfs_",
    "groupBy":     ["col-id-product-line"],
    "calculations": ["col-id-line-rev", "col-id-pct-of-total"]
  },
  {
    "id": "HW-oenXx5P",
    "groupBy":     ["col-id-week-of-date"],
    "calculations": ["col-id-weekly-rev", "col-id-rev-4w-ago", "col-id-4w-delta-pct"],
    "sort": [{
      "columnId":  "col-id-week-of-date",
      "direction": "descending",
      "nulls":     "connection-default"
    }]
  }
]
```

Per-grouping fields:

- **`id`** — unique grouping id within the element. Convention:
  alphanumeric (Sigma-style), or human-readable like `grp-customer`.
  Must NOT collide with any column `id` on the same element.
- **`groupBy`** — array of column ids to group by at this level
  (almost always one entry — multi-column groupBy at a single level is
  rare).
- **`calculations`** — array of column ids whose formulas are evaluated
  at this grouping level's grain. A column id appears in exactly one
  `calculations` array; whichever level claims it determines the
  formula's grain.
- **`sort`** — optional per-level sort. Same shape as the chart
  `sort` field; `nulls: "connection-default"` defers null-placement
  to the warehouse default.

### How the same formula resolves at different grains

Notice the example workbook has **five** columns with formula
`[Metrics/Revenue]` (Revenue at Product Type level, Line Rev at Product
Line level, Weekly Rev at Week level, Ind. Rev at the leaf/detail
level, and the implicit grand-total view). Each is its own column id;
which `calculations` array it lives in determines the grain at which
Sigma applies the aggregation. The leaf row (un-grouped detail) gets
the formula at row level. That's why the same `[Metrics/Revenue]` can
appear multiple times in `columns[]` with different display names —
they're different aggregations of the same metric.

### Detail (leaf) columns

Columns that appear in `columns[]` but NOT in any grouping's `groupBy`
or `calculations` are **leaf detail columns** — they're shown only
when a user expands a grouping all the way to row level. The element's
`order` array (not the `columns` array's order) defines the left-to-right
display order of these leaf columns. Grouping-level columns appear in
the order their grouping appears in `groupings[]`.

### `visibleAsSource`

Aggregated tables often set `"visibleAsSource": false` to hide the
element from other elements' source-picker dropdowns in the UI. The
property doesn't affect spec functionality.

### Earlier `{id}`-only / `{id, columnId}` shapes — what they actually are

The earlier shape `groupings: [{id: "..."}]` (no `groupBy`,
`calculations`) is a **legacy/decorative form** Sigma's GET serializer
emits in some round-trips. It does NOT trigger real SQL aggregation —
just a UI render hint that the element has groupings (without telling
Sigma which columns at which grain). If you author a spec with this
form, your aggregation columns silently won't aggregate; downstream
`Lookup` against the element will see per-row data and likely return
NULL via Sigma's `iff(equal_null(min, max), max, null)` defensive
pattern. (This is exactly the bug that consumed iteration 2 of the
cohort workbook.)

The `{id, columnId}` shape from older docs is also superseded — neither
field name (`columnId`) appears in current GET-backs. Use the
`{id, groupBy, calculations}` form documented above.

### When to use multi-level `groupings` vs. aggregated-sibling vs. `Rollup`

For "compute an aggregate per group, return it per row" needs, there
are two implementations: an **aggregated sibling table + Lookup**, or
the inline **Rollup** formula. Both produce equivalent SQL. Default to
the aggregated sibling — it almost always wins on legibility.

| You want | Use |
|---|---|
| One table that shows aggregates at multiple grains in a single hierarchical view | `groupings` |
| A per-row column that carries a per-group aggregate so other formulas can reference it (cohort attribution, lag calcs, share-of-parent) — **and the intermediate aggregation matters as its own analytical artifact** | **Aggregated sibling table + `Lookup`** (default) |
| Same need, but the intermediate is genuinely throw-away and you want to keep the page tight | `Rollup` (next section) |
| Hierarchical view AND a derived per-row column referencing those aggregates | Combine — `groupings` at the element level, Rollup/Lookup at the column level. |

**Why aggregated sibling is the default — legibility and modifiability:**

When a user opens the workbook to understand or extend it, an
intermediate table on the page makes the calculation chain visible:
"Customer Firsts has one row per Cust Key with their min(Date) — and
Plugs Transactions Lookup-joins against that." The reader sees the
shape, the values, and where to intervene to change the logic. Compare
to a `Rollup(Min([X/Date]), [Cust Key], [X/Cust Key])` formula buried
in a column on a 12-column table — same SQL, but the user has to
mentally execute the formula to know what's happening.

Practical consequences:

- **Code review.** A reviewer can scan the aggregated sibling in
  seconds; Rollup formulas require unpacking each one.
- **End-user modifications.** A non-author wanting to switch from "first
  purchase date" to "first purchase date in this calendar year" edits
  the sibling's `Min([Date])` formula in one obvious place. With Rollup,
  they're surgical-editing a buried formula inside a derived column.
- **Debugging.** When the cohort math is wrong, the aggregated sibling
  is the first thing to inspect — and it's already there on the page.
  With Rollup the only way to inspect the intermediate is to read the
  generated SQL or fan out a temporary table.

Reach for Rollup specifically when (a) you have many small windowed
aggregates that would clutter the page as separate tables, or (b) the
page is for downstream consumers who shouldn't see the scaffolding.
Default to aggregated sibling.

## Window functions require pre-materialized columns

Sigma's window-style functions (`Rollup`, `DateLookback`,
running-totals, ranks, `Sum(...) by [partition]`, etc.) operate on
**column values that already exist on the element**, not on inline
expressions. You cannot put a window function directly on top of a
multi-term expression like `[Quantity] * [Price]` and expect Sigma to
window over it — the engine needs the partitioned value to be a
materialized column first.

The rule:

1. **Step 1.** Declare the row-level value as its own named column on
   the element. For revenue this is one column with formula
   `[Quantity] * [Price]` and `"name": "Revenue"`.
2. **Step 2.** Apply the window function in a second column that
   references the materialized column: `Rollup(Sum([Revenue]), …)`,
   `DateLookback([Revenue], [Week of Date], 4, "week")`, etc.

Concrete cohort-workbook example:

```json
{ "id": "col-revenue", "name": "Revenue",
  "formula": "[Quantity] * [Price]" },

{ "id": "col-weekly-rev-shifted", "name": "Rev (4 weeks ago)",
  "formula": "DateLookback([Revenue], [Week of Date], 4, \"week\")" }
```

Trying to fold both into one column —
`DateLookback([Quantity] * [Price], [Week of Date], 4, "week")` —
either fails to compile or silently returns wrong values, because the
window function needs to address a stable column, not an ad-hoc
expression.

Practical consequence for authoring: when designing the columns array
for an element that will hold window calcs, list the materialized
base columns FIRST (the building blocks), then the window-derived
columns that reference them. The order in `columns` doesn't matter for
SQL generation, but it does matter for readers tracing the calculation
chain.

This pattern shows up in the canonical `Aggregate Results` example
(`examples/data-model-sourced-multi-level-aggregated-table.json`):
`Weekly Rev` is a materialized column, and `Rev (4 weeks ago)` /
`4 week delta %` reference `[Weekly Rev]` (via `[Metrics/Revenue]` at
the Week-of-Date grain, plus `DateLookback`).

## Per-row windowed aggregations — `Rollup`

When a formula needs an aggregate value (per-group min/max/sum/avg/count)
returned **per row** so other columns can reference it (cohort
attribution, RFM scoring, first/last attribution, etc.), the function
is `Rollup`. This is Sigma's analogue of SQL's
`AGG(...) OVER (PARTITION BY ...)`.

```
Rollup(<agg over target/col>, <local key>, <target/key>)
```

Example — for every transaction, attach that customer's first
purchase date:

```
Rollup(Min([Plugs Transactions Raw/Date]), [Cust Key], [Plugs Transactions Raw/Cust Key])
```

The element holding this formula needs a sibling element (here
`Plugs Transactions Raw`) on the same page that contains both the
aggregated column (`Date`) and the join key (`Cust Key`). For
cohort/per-customer attribution work the sibling is usually the raw
transactions table; the local table sources from it and adds derived
columns via Rollup.

Generated SQL is exactly what you want:

```sql
left join (select min("DATE") MIN_27, CUST_KEY
           from <warehouse_table>
           group by CUST_KEY) Q3
       on equal_null(Q2.CUST_KEY, Q3.CUST_KEY_28)
```

Contrast with `Lookup` — `Lookup` does NOT aggregate; it picks a single
matching value. When the target has multiple matches for a given key
and they aren't all identical, Lookup returns `NULL`. Reach for `Rollup`
whenever the right answer requires aggregation across the matched rows.

## Summary bar and aggregate-then-categorize pattern

When a visualization needs to color/threshold/bucket rows against a
scalar derived from the data itself (median, mean, percentile, target
delta, etc.), do NOT put the categorization formula directly on the
chart. A formula like

```
If([Margin] >= Median([Margin]), "Above median", "Below median")
```

placed on a chart where `[Margin]` is already an aggregated metric
(`[Metrics/Total Profit Margin]`) creates a recursive aggregate. Sigma
rejects it with "Column has a recursive formula."

The correct shape is a **three-piece composition on a single parent
table**:

1. **Aggregated parent table** with `groupings` at the relevant grain
   (per-store, per-customer, per-cohort).
2. **`summary: [<col-id>, ...]`** on that table — a top-level field on
   the table element (singular `summary`, NOT `summaries`). Each entry
   is a column id whose formula is evaluated at the summary-bar grain
   (across all rows of the table). The summary value is broadcast to
   every row.
3. **Categorization column inside the grouping's `calculations`** that
   references both the per-row metric and the summary value by their
   local display names.

Example — per-store table with median-margin summary plus an
"above/below median" bucket column:

```json
{
  "id": "tbl-store-agg",
  "kind": "table",
  "name": "Store Aggregates",
  "source": { "kind": "table", "elementId": "tbl-tx" },
  "columns": [
    { "id": "col-sa-store",  "formula": "[Transactions/Store Name]" },
    { "id": "col-sa-margin", "formula": "[Metrics/Total Profit Margin]" },
    { "id": "col-sa-median-margin", "name": "median margin",
      "formula": "Median([Total Profit Margin])" },
    { "id": "col-sa-cat", "name": "cat margin",
      "formula": "If([Total Profit Margin] >= [median margin], \"above median\", \"below median\")" }
  ],
  "groupings": [
    {
      "id": "grp-store",
      "groupBy": ["col-sa-store"],
      "calculations": ["col-sa-margin", "col-sa-cat"]
    }
  ],
  "summary": ["col-sa-median-margin"]
}
```

Grain by grain:

- `col-sa-margin` is in the grouping's `calculations` → per-store grain.
  Display name auto-derives from the formula path:
  `[Metrics/Total Profit Margin]` → `"Total Profit Margin"`.
- `col-sa-median-margin` is in `summary` → summary-bar grain. Sigma
  evaluates `Median([Total Profit Margin])` across all per-store rows,
  yielding one scalar that's broadcast to every row.
- `col-sa-cat` is in the grouping's `calculations` → per-store grain.
  `[Total Profit Margin]` is the per-store value at this grain;
  `[median margin]` is the summary scalar. For each store the `If`
  returns the bucket label.

Charts source from this parent and reference the bucket via the
sibling namespace:

```json
{
  "id": "chart-margin-by-store",
  "kind": "bar-chart",
  "source": { "kind": "table", "elementId": "tbl-store-agg" },
  "columns": [
    { "id": "cm-store",  "formula": "[Store Aggregates/Store Name]" },
    { "id": "cm-margin", "formula": "[Store Aggregates/Total Profit Margin]" },
    { "id": "cm-cat",    "formula": "[Store Aggregates/cat margin]" }
  ],
  "xAxis": { "id": "cm-store", "sort": { "by": "cm-margin", "direction": "descending" } },
  "yAxis": [ { "id": "cm-margin" } ],
  "color": { "by": "category", "column": "cm-cat" }
}
```

**Optional `source.groupingId`.** Charts can pin themselves to a
specific grouping level via `source: { ..., groupingId: "<grouping-id>" }`.
This makes the grouping's columns directly accessible as local
references (`[Total Profit Margin]` without the sibling prefix). Sigma's
GET round-trip sometimes strips `groupingId`; charts still render at the
grouping's grain when every referenced column is itself grain-anchored
(groupBy or grouping calc), so omitting the explicit `groupingId` is
not fatal — but include it when the chart needs local-name access to
the grouping's columns.

### Why parent-table, not inline-on-chart

- **No recursion.** The chart references already-aggregated columns,
  not aggregates-of-aggregates.
- **Inspectable.** The parent table renders on the page; readers see
  the per-row values and the summary scalar side by side.
- **Composable.** Adding percentile-rank, quartile bucket, or
  delta-vs-target follows the same shape — new summary entry plus new
  grouping calc, no chart changes.
- **Reusable.** Many charts can source from one parent table — the
  scalar is computed once.

### When the scalar isn't a summary

`summary` works when the scalar is one of Sigma's aggregate functions
(`Median`, `Mean`, `Sum`, `Min`, `Max`, `Percentile`, `Count`, etc.)
applied across the parent table's rows. When the scalar comes from
somewhere else — a control value, a cross-element Lookup, a fixed
threshold — declare it as a regular column (not in `summary`) and
reference it the same way from the grouping's bucket column.

## Two-tier sourcing pattern (warehouse → derived)

When you need windowed aggregations (`Rollup`), cross-element joins, or
any formula that references aggregated values from another element,
adopt this layered pattern:

1. **Raw element** — `kind: table`, `source.kind: "warehouse-table"`.
   Passthrough columns only, no aggregations, no Rollup. Acts as the
   shared root.
2. **Derived element(s)** — `kind: table`, `source.kind: "table"`
   pointing at the raw element. Holds passthrough columns plus all
   derived/aggregation columns (`Rollup`, `Lookup`, calc columns).
3. **Visualization element(s)** — `kind: bar-chart | line-chart |
   pivot-table | ...`, `source.kind: "table"` pointing at the derived
   element. The chart's columns reference the derived columns by
   sibling display-name syntax.

Why two-tier rather than one-tier:

- A single `warehouse-table`-sourced element can hold derived columns
  (calcs, Rollups), but those calcs reference the warehouse path
  (`[PLUGS_ELECTRONICS_HANDS_ON_LAB_DATA/...]`) for raw fields and the
  same element by display-name for derived fields. Mixing both
  reference styles in one element makes spec churn high when paths
  change.
- The derived sibling cleanly separates "what the warehouse returns"
  from "what we compute on top." A second derived element can branch
  off the same raw for a different analysis without re-declaring the
  warehouse path.
- Rollup needs a sibling target to reference; a one-tier model can't
  Rollup over itself (cycle).

For the cohort workbook the layering looks like:

```
tbl-plugs-tx-raw  (warehouse-table, passthrough)
  └─ tbl-plugs-tx (source: table → raw, +Rollup/cohort/weeks/revenue/profit)
       └─ chart-cohort-pivot (source: table → tbl-plugs-tx, +Sum on values)
```

## Layout

Layout is XML embedded as a string in the JSON `layout` field. 24-column grid.
Three node types:

- `<Page>` — the root. `type="grid"`, `gridTemplateColumns="repeat(24, 1fr)"`,
  `gridTemplateRows="auto"`, `id="<page-id>"` (must equal the page id in the
  `pages` array).
- `<GridContainer>` — wraps a container element's children. Has its OWN grid
  (24 cols by default), so child positions inside a container are relative
  to the container, not the page. Required attrs: `elementId` (the container
  element's id), `type="grid"`, `gridColumn`, `gridRow`,
  `gridTemplateColumns`, `gridTemplateRows`.
- `<LayoutElement>` — a leaf element placement. Required: `elementId`,
  `gridColumn`, `gridRow`.

```xml
<Page type="grid" gridTemplateColumns="repeat(24, 1fr)" gridTemplateRows="auto" id="page-overview">

  <!-- Header bar: title + filter controls in one row, wrapped in a container -->
  <GridContainer elementId="container-header" type="grid"
                 gridColumn="1 / 25" gridRow="1 / 4"
                 gridTemplateColumns="repeat(24, 1fr)" gridTemplateRows="auto">
    <LayoutElement elementId="text-page-title"  gridColumn="1 / 10"  gridRow="1 / 4"/>
    <LayoutElement elementId="ctrl-store-region" gridColumn="10 / 15" gridRow="1 / 4"/>
    <LayoutElement elementId="ctrl-date-range"   gridColumn="15 / 20" gridRow="1 / 4"/>
    <LayoutElement elementId="ctrl-product-family" gridColumn="20 / 25" gridRow="1 / 4"/>
  </GridContainer>

  <!-- Body: 3 KPIs across the top, full-width chart below -->
  <GridContainer elementId="container-body" type="grid"
                 gridColumn="1 / 25" gridRow="4 / 25"
                 gridTemplateColumns="repeat(24, 1fr)" gridTemplateRows="auto">
    <LayoutElement elementId="kpi-revenue"  gridColumn="1 / 9"   gridRow="1 / 10"/>
    <LayoutElement elementId="kpi-cogs"     gridColumn="9 / 17"  gridRow="1 / 10"/>
    <LayoutElement elementId="kpi-margin"   gridColumn="17 / 25" gridRow="1 / 10"/>
    <LayoutElement elementId="chart-revenue-monthly" gridColumn="1 / 25" gridRow="10 / 22"/>
  </GridContainer>

  <!-- Bare leaf, no container -->
  <LayoutElement elementId="tbl-plugs-tx" gridColumn="1 / 25" gridRow="25 / 45"/>
</Page>
```

Layout rules:

- `gridColumn="1 / 25"` = full width. Half-width = `1 / 13` and `13 / 25`.
- `gridRow="1 / 3"` = 2 rows tall. KPI tiles with timeline comparisons need
  more vertical space (8–10 rows tall, not 3) so the sparkline reads.
- Container children's coordinates are RELATIVE to the container's own grid,
  not the page. Inside the container you start a fresh `1 / 25` column space.
- A container's element body in the JSON `pages[].elements` is just
  `{id, kind: "container"}` — no children listed there. The XML is the
  source of truth for parent/child relationships.
- The `id` attribute on `<Page>` MUST equal the page id in the `pages` array.
- Sigma normalizes by prepending `<?xml version="1.0" encoding="utf-8"?>`
  and a trailing newline on save.

## Page-structure pattern (apply by default)

Every page starts with a header bar container holding the page title text
element + the filter controls. The body holds KPIs/charts (often in a
container so the layout reads as a logical block). Detail tables go bare at
the bottom (large enough that a container adds no value).

```
[ container-header: <title>  <ctrl1>  <ctrl2>  <ctrl3> ]
[ container-body:   <kpi1>   <kpi2>   <kpi3>           ]
[                   <bar-chart full width>             ]
[ <table full width, no container>                     ]
```

This is the shape used in
`workbooks/_exemplars/data-model-sourced-kpi-overview-with-containers.json`
and `examples/data-model-sourced-kpi-overview-with-containers.json`.

## Recipe — minimal data-model-fed dashboard

1. `GET /v2/files/{folder-urlId}` → grab the folder's internal UUID.
2. `GET /v2/dataModels/{id}/spec` → identify the target node's display name,
   its column display names, and its `metrics`.
3. Author the table element with `source.kind: "data-model"` and a `columns`
   array that declares every data-model column you'll need downstream
   (passthrough formulas: `[<NodeName>/<ColumnName>]`).
4. Author the chart with `source.kind: "table"`, its own `columns` array
   redeclaring whatever it needs, and `xAxis` / `yAxis` referencing those ids.
   Prefer `[Metrics/<Name>]` over hand-derived sums.
5. Author the control with `filters[].columnId` = the column id you declared
   on the table.
6. Layout XML wires elementIds to grid positions.
7. POST → if HTTP 200, GET it back as the new source of truth (Sigma normalizes
   IDs, layout XML, etc.) — overwrite `spec.json`.
8. **Open the workbook in the UI and visually verify** elements render — the
   API will not catch broken cross-element column references.
