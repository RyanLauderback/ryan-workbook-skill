# Conventions — ryan-workbook-skill cross-cutting rules

This file consolidates the **load-bearing cross-cutting rules** that anchor
this skill's prompt-to-workbook workflow. These rules are NOT in the
official Sigma OpenAPI or the upstream `sigma-workbooks` skill — they're
verified-from-incident learnings specific to how this skill plans, builds,
and round-trips workbooks.

**Required reading on every build.** Skipping this file is how the
2026-05-19 cold-start session shipped a broken workbook in 30 minutes.
The plan's `Chunks Read:` line must list this file.

## Table of contents

- [Inference anchor — every formula traces to recon](#inference-anchor)
- [Passthrough mandate + drill-down corollary](#passthrough-mandate)
- [Explicit-`name` rule + rename-cascade corollary](#explicit-name-rule)
- [`[Metrics/<Name>]` resolution + DM-switch hard rule](#metrics-resolution)
- [Control/column ID collision](#control-column-collision)
- [Channel exclusivity (one column per binding channel)](#channel-exclusivity)
- [Bar-chart orientation + categorical-axis sort rule](#bar-orientation)
- [Summary-bar pattern (aggregate-then-categorize)](#summary-bar)
- [Two-tier sourcing (warehouse → derived)](#two-tier-sourcing)
- [Notes-promotion guardrail](#notes-promotion)

---

## Inference anchor — every formula traces to recon

**Rule.** Every formula in a proposed plan must trace to one of:

- A `[Metrics/<X>]` confirmed in `mcp-describe.sh datamodel-element <dm> <el>`
  output for the source element, OR
- A column declared on the source table that recon confirmed exists.

**"Reasonable assumption" formulas are forbidden.** If recon doesn't
show the field the user's prompt implies, the plan surfaces it as an
**Open Decision** (item 6 in the plan structure — see
`reference/workflows/plan.md`); it does NOT silently assume the field
exists. The cost of one extra clarification turn is far lower than
the cost of a plan + spec that fails at render time.

This applies equally to vague prompts ("build me a cost analysis") and
specific ones ("show NIM by region"). For vague prompts, the agent's
job is to lean into the recon and propose what's actually computable
— not to imagine a dashboard and hope the data supports it.

---

## Passthrough mandate

**There is no implicit column inheritance into a workbook element from
its source.** You MUST declare every column you intend to use, with a
stable `id`. The CREATE endpoint accepts specs whose downstream
references can't be resolved — the broken element fails silently at
render time.

Concretely:

- A bar chart sourced from a sibling table can only reference columns
  it has re-declared on its own `columns` array. Inheriting "via
  source" without redeclaration produces a chart that won't render.
- A control's `filters[].columnId` must match a column `id` declared
  on the target element. Referencing the column NAME (`"Date"`)
  instead of its `id` silently breaks the filter wiring.

Practical pattern when authoring from scratch: declare ALL columns of
the data-model element on the table (passthrough), even if the table
will display them. Then chart/control references downstream resolve
correctly.

### Drill-down corollary — passthrough on visualizations, not just tables

The mandate above keeps the formula resolver happy. There's a second
reason to declare every source column on every visualization: **right-
click drill-down in Sigma only exposes columns that element declares**.
A bar chart of `Revenue by Region` that only declares `region`,
`revenue`, and the metric's material columns gives the reader no path
from region → state → city → store, even though those columns exist on
the source table.

**Default rule when generating a chart, KPI, or pivot:** copy the
parent table's full passthrough column set onto the viz element (each
as a sibling-namespaced formula like `[Transactions/Store State]`),
then add the chart-specific derived columns (axis-derived dates,
buckets, etc.) on top. Only the encoding-bound columns appear in
`xAxis`/`yAxis`/`color`/`size`, but the others are present and drillable.

**The one carve-out — `Lookup`-derived phantom series.** If the source
table contains a `Lookup(...)` column that produces a phantom series
in a specific viz (e.g. a chart plotting `Sum([Metric])` accidentally
splits by the Lookup column), strip **that specific Lookup column**
from **that specific viz** only.

This carve-out NEVER generalizes:

- It does NOT apply to base data-model columns.
- It does NOT apply to other vizs on the same page (the same Lookup
  col may be legitimate elsewhere).
- It does NOT justify "no chart passthroughs beyond x/y axes" — that
  phrasing is the 2026-05-19 regression mode and is wrong.

**Calibration** (verified against 7 canonical exemplars):

- Smallest legitimate chart: ~7 cols (scatter on
  `examples/data-model-sourced-multi-element-catalog.json`).
- Smallest legitimate pivot: 3 cols
  (`examples/data-model-sourced-cohort-pivot.json`).
- The collapse signature: chart with ≤2 cols sourced from a table
  with ≥5 cols.

`validate-spec.py`'s `passthrough-coverage` check catches the collapse
signature pre-POST. Calibrated to FAIL on chart-kind elements with ≤2
cols sourced from tables with ≥5 cols; WARN on thin-but-not-collapsed
cases; KPIs intentionally excluded (col count is too variable).

---

## Explicit-`name` rule

**Set an explicit `name` on every column referenced by display name
from a sibling element.** A passthrough column without `name`:

```json
{ "id": "col-date", "formula": "[Plugs Transaction Details - Relationships/Date]" }
```

works in a GET-back exemplar (Sigma renders the inferred name "Date"),
but fails at POST with:

```
Cannot resolve column ... dependency not found:
formula reference 'plugs transaction details/date'
```

because the cross-element resolver looks up by display name and the
column doesn't have one yet at validation time. The fix is to declare
it explicitly:

```json
{ "id": "col-date", "name": "Date", "formula": "[Plugs Transaction Details - Relationships/Date]" }
```

Apply this to every column on a workbook table that downstream KPIs,
charts, or controls will reference via
`[<TableDisplayName>/<ColumnName>]`. For internal-only columns (e.g.
an aggregation result that only the element itself uses) `name` is
still good practice but not load-bearing.

### Rename-cascade corollary

The flip side: **renaming a source-of-truth table's `name` field
breaks every sibling formula that references it as
`[<OldName>/Column]`.** The cross-element resolver looks up by display
name; once the display name changes, the old reference no longer
resolves. POST/PUT will fail with:

```
Cannot resolve columns on table '<chart-id>': dependency not found:
formula reference '<old-table-name>/<column-name>'
```

Verified 2026-05-19 during a styling pass: prefixing the parent
table's `name` from `"Transactions Detail"` → `"🔴 Transactions
Detail"` left 14 sibling chart/KPI formula references pointing at a
name that no longer existed. PUT rejected the spec. See
`reference/history.md` → "2026-05-19 — Styled-name + style.borderColor
discovered."

**The rule.** Either:

1. **Leave source-of-truth table names alone** — they're an internal
   API surface for every sibling on the page. Restyle the *element
   title* instead via the styled-name object form (see
   `reference/specification/text.md` and the per-element files), which
   is rendered as the visible header WITHOUT changing the table's
   display-name handle that formulas reference.
2. **OR cascade the rename** — when the table name MUST change, also
   update every sibling formula `[<OldName>/X]` → `[<NewName>/X]` in
   the same edit. Validation won't catch missed references; the
   resolver will at POST/PUT time.

The styled-name object form is almost always the right tool for "I
want the title to look different" — it changes what the user sees
without touching what formulas resolve against.

---

## `[Metrics/<Name>]` resolution + DM-switch hard rule

**Resolution.** `[Metrics/<Name>]` references resolve against the
data-model element a spec sources from. `mcp-describe.sh
datamodel-element <dm> <el>` returns the metric catalog FOR THAT
ELEMENT. Treat that catalog as the source of truth — if a metric
isn't listed there, do not reference it from a spec that sources off
that element.

**Slash-in-name caveat:** metric names containing `/` (e.g.
`Cost/Member/Month`) are not safely addressable as
`[Metrics/Cost/Member/Month]` — the `/` is the namespace delimiter and
parsing of multi-slash names is undefined. Options:

1. **Rename the metric in the data model** (preferred — fixes for all
   consumers).
2. **Fall back to a hand-derived formula** using the metric's actual
   formula visible in `mcp-describe` output (e.g.
   `Sum([CostMember]) / Count([Month])`).

**Round-trip is not validation.** A spec that POSTs and GETs back
successfully with `[Metrics/A/B]` is not evidence the reference
resolves at render. POST preserves the string; GET returns the
string. Render is where the resolution happens. Always visually
verify post-POST.

### DM-switch hard rule

**On any data-model switch mid-session, re-derive every
`[Metrics/...]` reference from the new recon. Never carry metric
names forward from a previous DM's plan.**

The 2026-05-19 regression was caused by carrying
`[Metrics/Cost per Unit] * [Metrics/Encounter Volume]` from the
original DM's plan into a spec sourced against a different DM that
did not contain those metrics. Treat the prior plan as discarded for
metric purposes; re-run `mcp-describe.sh datamodel-element <new-dm>
<new-el>` and regenerate.

### Distinct from official's `[Source/Col]` syntax

The official Sigma skill (`sigma-workbooks`) documents column
references as `[<SourceName>/<column_name>]` where `<SourceName>` is
the warehouse table, sibling element, or join leg. This skill's
`[Metrics/<X>]` is an **additional** namespace specific to data-model-
sourced elements — it addresses metrics defined on the DM element,
not on the workbook. The two syntaxes coexist:

- `[Transactions/Date]` — sibling-element column (official syntax).
- `[Metrics/Total Revenue]` — DM metric (this skill's addition).

`reference/specification/formulas.md` carries both.

---

## Control/column ID collision

**Rule.** A control's `controlId` must not match any column `name` or
`id` on the elements it filters.

**Failure mode.** Sigma's formula resolver, when it sees a bare
reference like `[Date]`, resolves to a workbook **control** of that
name before falling back to columns. So a control declared with
`controlId: "Date"` shadows the `Date` column on its filtered element.
Downstream formulas — `Month([Date])`, `Year([Date])`,
`DateTrunc("month", [Date])` — silently coerce to operate on the
control's current selection value (a date range scalar), not the
column. Render-time symptoms: wrong axis values, "expected DateTime,
got string" errors at chart load, or KPIs that show the filter
selection back as a value.

**Verified 2026-05-19** during the cold-start sales-performance test
session: `controlId: "Date"` shadowed the `Date` column in the PLUGS
data model; the v3 spec errored at render until the control was
renamed to `DateRange` and column references were fully-qualified
(`[Transactions Detail/Date]`).

**Prevention checklist:**

- Prefix every controlId distinctively: `DateRange`, `StoreFilter`,
  `PlanTypeCtrl`, `SegmentSelect`.
- Never name a control after the column it filters. The control is
  the *interaction*, not the *data*.
- When in doubt, fully qualify column references in formulas:
  `[<ElementName>/Date]` instead of bare `[Date]`. This bypasses
  control-shadowing entirely.
- `validate-spec.py`'s `controlid-collision` check catches this
  pre-POST. The check inspects each control's `filters[].source.elementId`
  and compares its `controlId` against every column `name`/`id` on
  the target element.

---

## Channel exclusivity

**Rule:** A single column id may appear on at most **one** binding
channel per element. Reusing the same columnId across two channels
(e.g., putting the same `col-revenue` on both `value` and `holeValue`
of a donut, or on both `xAxis` and `color` of a bar chart) is
**rejected at POST** with a message like `Column '<id>' is referenced
from both 'X' and 'Y'; a column can only be on one channel at a time`.

**Why:** Sigma binds each channel to at most one distinct column per
element. If you need two channels to share the same underlying value,
define **two column entries** (different `id`s, same `formula`) and
wire one column per channel.

**Per-element channel lists:**

| Element kind | Binding channels (exclusive) |
|---|---|
| `bar-chart`, `line-chart`, `area-chart`, `combo-chart` | `xAxis`, `yAxis` (columnIds), `color`, `size` |
| `scatter-chart` | `xAxis`, `yAxis`, `color`, `size` |
| `pie-chart`, `donut-chart` | `value`, `color`; donut also `holeValue` |
| `region-map` | `region`, `color`, `label[]`, `tooltip[]` |
| `point-map` | `latitude`, `longitude`, `size`, `color`, `label[]`, `tooltip[]` |
| `geography-map` | `geography`, `color`, `label[]`, `tooltip[]` |
| `kpi-chart` | `value` |
| `table`, `pivot-table` | none (channels don't apply — everything is in `columns[]`) |

`label` and `tooltip` on maps are arrays — they accept multiple
`{id}` entries, but a given column id still must appear on only ONE
channel per element.

**Fix pattern:** duplicate the column with a distinct id.

```json
"columns": [
  { "id": "col-rev-value",  "formula": "Sum([Sales])", "name": "Revenue" },
  { "id": "col-rev-region", "formula": "[Region]",     "name": "Region" },
  { "id": "col-orders",     "formula": "CountDistinct([Order Id])", "name": "Orders" }
],
"value":     { "id": "col-rev-value" },
"holeValue": { "id": "col-orders" },       // distinct — Orders, not Revenue
"color":     { "id": "col-rev-region", "sort": { "by": "col-rev-value", "direction": "descending" } }
```

Verified 2026-07-02 against `exec-scorecard-v2` (2 POST rejections
on region-map channel reuse before this rule was formalized).

`validate-spec.py`'s `channel-exclusivity` check catches this
pre-POST (planned; not yet implemented — see `reference/workflows/validate.md`).

---

## Bar-chart orientation + categorical-axis sort rule

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

**`orientation` accepts `"horizontal"` or omit-for-default.** Explicit
`orientation: "vertical"` is rejected at POST. When you want vertical,
omit the field; the default IS vertical. Verified 2026-07-02 against
`exec-scorecard-v2` (1 POST retry on explicit-vertical).

---

## Summary-bar pattern

When a visualization needs to color/threshold/bucket rows against a
scalar derived from the data itself (median, mean, percentile, target
delta, etc.), do NOT put the categorization formula directly on the
chart. A formula like

```
If([Margin] >= Median([Margin]), "Above median", "Below median")
```

placed on a chart where `[Margin]` is already an aggregated metric
(`[Metrics/Total Profit Margin]`) creates a recursive aggregate.
Sigma rejects it with "Column has a recursive formula."

The correct shape is a **three-piece composition on a single parent
table**:

1. **Aggregated parent table** with `groupings` at the relevant grain
   (per-store, per-customer, per-cohort).
2. **`summary: [<col-id>, ...]`** on that table — a top-level field
   on the table element (singular `summary`, NOT `summaries`). Each
   entry is a column id whose formula is evaluated at the summary-bar
   grain (across all rows of the table). The summary value is
   broadcast to every row.
3. **Categorization column inside the grouping's `calculations`** that
   references both the per-row metric and the summary value by their
   local display names.

Charts then source from this parent and reference the bucket via the
sibling namespace. Full example with code in
`reference/specification/tables.md` → "Summary bar pattern."

**Why parent-table, not inline-on-chart:**

- **No recursion.** The chart references already-aggregated columns,
  not aggregates-of-aggregates.
- **Inspectable.** The parent table renders on the page; readers see
  the per-row values and the summary scalar side by side.
- **Composable.** Adding percentile-rank, quartile bucket, or
  delta-vs-target follows the same shape — new summary entry plus new
  grouping calc, no chart changes.
- **Reusable.** Many charts can source from one parent table — the
  scalar is computed once.

**When the scalar isn't a summary:** `summary` works when the scalar
is one of Sigma's aggregate functions (`Median`, `Mean`, `Sum`,
`Min`, `Max`, `Percentile`, `Count`, etc.) applied across the parent
table's rows. When the scalar comes from somewhere else — a control
value, a cross-element Lookup, a fixed threshold — declare it as a
regular column (not in `summary`) and reference it the same way from
the grouping's bucket column.

---

## Two-tier sourcing (warehouse → derived)

For workbooks where the data needs derivation (cohort buckets,
weeks-since-first-action, comparative anchors) before visualization,
build TWO table elements on the same page:

1. **Raw table** sourced from the warehouse/data-model element.
   Carries the base columns + any first-order calculated columns
   (`Rollup(Min([Date]), [Cust Key], ...)` for first-purchase, etc.).
2. **Derived table** sourced from the raw table via `kind: table,
   elementId: <raw-id>`. Carries the cohort dimensions and the
   final-grain columns (`DateDiff("week", [First Purchase], [Date])`
   etc.).

Then KPIs, charts, and pivots source from the derived table. This
keeps the first-order math out of the viz elements (avoiding
recursive aggregation) and makes the derivation chain inspectable.

Canonical example: `examples/data-model-sourced-cohort-pivot.json`.

---

## Notes-promotion guardrail

The iteration-playbook's "promote on 2nd recurrence" rule moves
recurring fixes from `workbooks/<name>/notes.md` into skill chunks.

**Guardrail.** Before promoting any notes.md observation into a skill
chunk, audit the entire iteration log for that workbook (and the
current session transcript when available) for a refutation or
correction of the claim. If the claim was at any point reversed, do
NOT promote — instead, add a `~~strikethrough~~` of the original
claim with a one-line refutation note. The skill is built from
VERIFIED learnings; `notes.md` is a working scratchpad and can
contain in-flight wrong hypotheses.

---

## Cross-references

- `reference/workflows/plan.md` — the plan-first workflow that
  enforces these rules at the planning gate.
- `reference/scope-and-edge-cases.md` — what doesn't round-trip
  through GET-spec (ryan-specific edge cases observed on this org).
- `reference/history.md` — the dated incident log behind each rule.
