# Workbook Spec API — Reference

Canonical patterns for `POST/GET/PUT /v2/workbooks/spec`. These rules are the
result of iteration loops where the create endpoint accepted broken specs that
failed at render time. Read this before authoring any workbook spec.

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

## Element kinds — verified vs. docs mismatches

The Sigma help-doc example library and the actual API don't always agree on
element `kind` values. Verified-against-API values (use these):

| What you want | Spec `kind` | Notes |
|---------------|-------------|-------|
| Bar chart | `bar-chart` | matches docs |
| KPI / single-value tile | `kpi-chart` | **docs example says `kpi` — API rejects with `Invalid kind: "kpi"`. Use `kpi-chart`.** |
| Table | `table` | matches docs |
| Control | `control` (with `controlType: date-range \| list \| ...`) | matches docs |
| Layout container | `container` | element body has only `id` + `kind`; child placement happens in the layout XML via `<GridContainer>`. |
| Markdown text / heading | `text` | fields: `body` (markdown), `verticalAlign` (`top \| middle \| bottom`). Used for page titles, section headers, narrative blocks. |

When the docs and the API disagree, trust the API error and update this table.

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
