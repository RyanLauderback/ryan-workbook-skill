# `data-model-sourced-exec-kpi-scorecard.json` — design intent

Canonical **executive scorecard + geographic viz + anomaly detection**
exemplar. Source: fresh isolated sub-agent build (2026-07-02) against
`PLUGS Data Model vREL`, with post-build fix applied to the anomaly
page's derived table. Verified end-to-end after PUT: all 35 elements
compile clean.

## When to clone this exemplar

Executive / ops-review builds with:
- Period-over-period + prior-year KPI comparison (via small-multiples pattern)
- Pivot with **calculated PoP % delta column** (not two side-by-side raw numbers)
- Geographic viz (US-state `region-map` sourced from an aggregated
  region-level derived table)
- Scatter plot for outlier visualization (volume vs deviation)
- Anomaly-detection table ranked by absolute deviation, top-N filter

**Do NOT clone this** if the ask is a single-page tactical dashboard
(too complex) or if the data model has no store/region dimensions
(map won't work).

## Templated placeholders

Replace before POST:
- `folderId`
- Data-model UUID on `.pages[].elements[] | select(.kind == "data-model")`
- Formula prefixes matching your data model's element names

## What patterns this exemplar demonstrates

**Pivot with calculated PoP % delta** (Page 1 — canonical pattern):
- Pivot columns include both raw current/prior aggregation columns
  AND a computed `(Current - Prior) / Prior` column
- Conditional formatting on the % column
- `groupings` used to aggregate by store or region dimension

**Region map** (Page 2 — see `reference/specification/maps.md`):
- `kind: "region-map"` with `regionType: "us-state"`
- `region: {id: <state-col>, regionType: "us-state"}` — single object
- `color: {by: "scale", column: <metric-col>}` — sourced from a
  workbook table that uses `Lookup()` to pull the metric into
  the D_STORE-based aggregation
- `label: [{id: ...}]` — array (not single object; shape gotcha)

**Scatter outlier detection** (Page 3):
- `kind: "scatter-chart"`
- `xAxis` = volume metric, `yAxis` = deviation %
- `color.by: "category"` on a computed `Direction` column (`Up`/`Down`)
- `size` channel for a third metric

**Anomaly detection derived table** (Page 3 — after 2026-07-02 fix):
- Two-tier source: raw transactions → per-store derived table
- **`groupings` + conditional-Sum aggregations** — NOT `Rollup()`.
  Rollup misuse (literal `1` third arg, or Rollup combined with
  `groupings`) returns null; the fixed pattern uses plain
  `Sum(If(DateTrunc("month", [Date]) = DateTrunc("month", Today()), ...))`
  under `groupings.calculations`.
- Post-aggregation formulas reference sibling aggregated columns:
  `Historical Avg = If([Historical Months] > 0, [Historical Total] /
  [Historical Months], Null)` — works on `groupings` tables (unlike
  KPI value columns, see `reference/specification/kpis.md` →
  "Value formula pitfall")
- `IsNull(<col>)` function usage — NOT `[<col>] Is Null` operator
  (which the API rejects)

## Load-bearing rules this exemplar respects

- ✅ Passthrough mandate on every viz
- ✅ `controlId`s namespaced per-page (`OvDateRange`, `TrDateRange`,
  `OuDateRange`) to avoid collisions
- ✅ Channel exclusivity — each column appears on at most one binding
  channel per element (region-map channels don't overlap)
- ✅ KPI value formulas are self-contained (`[Metrics/...]` scalars),
  not sibling aggregation references
- ✅ `orientation` field only ever `"horizontal"` or omitted (explicit
  `"vertical"` is rejected)
