# Layout and cross-element

How elements connect, reference each other, and lay out on the page. Covers layout XML, the column-declaration rule, cross-element joins (Lookup/Rollup), table groupings, summary-bar pattern, two-tier sourcing, and the canonical recipe. Load when stitching multiple elements together or laying out the page.

## Table of contents

- [Layout rules — read before authoring multi-page](#layout-rules-read-before-authoring-multi-page)
- [The column-declaration rule (MOST IMPORTANT)](#the-column-declaration-rule-most-important)
- [The explicit-`name` rule (also load-bearing at POST time)](#the-explicit-name-rule-also-load-bearing-at-post-time)
- [Cross-element joins via `Lookup()`](#cross-element-joins-via-lookup)
- [Window functions require pre-materialized columns](#window-functions-require-pre-materialized-columns)
- [Per-row windowed aggregations — `Rollup`](#per-row-windowed-aggregations-rollup)
- [Summary bar and aggregate-then-categorize pattern](#summary-bar-and-aggregate-then-categorize-pattern)
- [Two-tier sourcing pattern (warehouse → derived)](#two-tier-sourcing-pattern-warehouse-→-derived)
- [Layout](#layout)
- [Page-structure pattern (apply by default)](#page-structure-pattern-apply-by-default)
- [Recipe — minimal data-model-fed dashboard](#recipe-minimal-data-model-fed-dashboard)

---


## Layout rules — read before authoring multi-page

Three rules that the POST validator does not enforce. Sigma silently rewrites
the layout when any of them is broken, producing a workbook that opens but
looks wrong:

1. **`layout` is a top-level workbook field.** A `layout` placed under
   `pages[i]` is **silently discarded** by the API.
   The agent's expected output is one top-level `layout` string for the whole
   workbook. (Incident log: `reference/history.md` → 2026-05-11.)
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

### Rename-cascade corollary

The flip side of the explicit-`name` rule: **renaming a source-of-truth
table's `name` field breaks every sibling formula that references it as
`[<OldName>/Column]`.** The cross-element resolver looks up by display
name; once the display name changes, the old reference no longer
resolves. POST/PUT will fail with:

```
Cannot resolve columns on table '<chart-id>': dependency not found:
formula reference '<old-table-name>/<column-name>'
```

Verified 2026-05-19 during a styling pass: prefixing the parent table's
`name` from `"Transactions Detail"` → `"🔴 Transactions Detail"` left 14
sibling chart/KPI formula references (`[Transactions Detail/Date]`,
`[Transactions Detail/Store Name]`, …) pointing at a name that no longer
existed. PUT rejected the spec.
See `reference/history.md` → "2026-05-19 — Styled-name + style.borderColor
discovered" for the full incident.

**The rule.** Either:

1. **Leave source-of-truth table names alone** — they're an internal API
   surface for every sibling on the page. Restyle the *element title*
   instead (via the styled-name object — see
   `reference/element-shapes.md` → "Element-level styling fields"), which
   is rendered as the visible header WITHOUT changing the table's
   display-name handle that formulas reference.
2. **OR cascade the rename** — when the table name MUST change, also
   update every sibling formula `[<OldName>/X]` → `[<NewName>/X]` in the
   same edit. Validation won't catch missed references; the resolver
   will at POST/PUT time.

The styled-name object form is almost always the right tool for "I want
the title to look different" — it changes what the user sees without
touching what formulas resolve against.


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
pattern. (Incident log: `reference/history.md` → 2026-05-13.)

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
