# `data-model-sourced-single-page-inventory-health.json` — design intent

Canonical **single-page dashboard with conditional formatting + shared
controls** exemplar. Source: fresh sub-agent build (2026-07-02) against
`PLUGS Data Model vREL`. 10 elements total; the smallest of the
2026-07-02 exemplar family — clone this before the multi-page ones for
tight single-page asks.

## When to clone this exemplar

Single-page ops / triage dashboards with:
- 3-4 KPI cards at the top
- One item-level detail table with **conditional formatting** for
  status flagging (stockouts red / overstocks green / etc.)
- **Two shared controls filtering the whole page** (e.g., Store + Category)
- Fast morning-review use case — not a multi-page exploration

**Do NOT clone this** if the ask is multi-page (see
`data-model-sourced-sales-command-center.json`) or needs charts +
maps (see `data-model-sourced-exec-kpi-scorecard.json`).

## Templated placeholders

Replace before POST:
- `folderId`
- Data-model UUID
- Formula prefixes matching your data model's element name

## What patterns this exemplar demonstrates

**Conditional formatting** (see `reference/specification/tables.md`):
- `conditionalFormats` with `single` variant (threshold-based)
- Multiple rules on the same table (one per status class)
- Applied to both a numeric column AND a text status column

**Shared filters — "one control, multiple elements"** (see
`reference/specification/controls.md`):
- Each control's `filters[]` array has multiple bindings — one per
  target element to filter
- Both controls narrow the same page's tables in parallel (compose
  with AND semantics)

**Derived status column** (see `reference/specification/formulas.md`):
- `If([Metric] < Threshold, "Stockout", If([Metric] > Upper, "Overstock", "Healthy"))`
- Nested `If` — Sigma's ternary chain pattern

**Data-derivation transparency**:
- PLUGS is sales-transactional (no native inventory columns), so
  "Inventory Value" / "Stockout" / "Overstock" are derived from sales
  velocity with documented thresholds
- Real inventory deployments should join an ERP inventory fact table

## Load-bearing rules this exemplar respects

- ✅ Passthrough mandate on the detail table
- ✅ Both `controlId`s (`StoreFilter`, `CategoryFilter`) distinct from
  any column name on filtered elements
- ✅ Table `description` (when set) uses object form
  `{visibility: "hidden"}` — NOT a plain string (which API rejects
  on tables/KPIs)
- ✅ Single-page scoping — no over-engineering
