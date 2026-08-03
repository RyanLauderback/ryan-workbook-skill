# `data-model-sourced-sales-command-center.json` — design intent

Canonical **modern 3-page multi-page workbook** exemplar. Source: fresh
sub-agent build (2026-07-02) against `PLUGS Data Model vREL` producing
Costco-branded Sales Command Center. Verified against every 2026-06 /
2026-07 skill fix (segmented control shapes, `gap.betweenSets`
precondition, donut `holeValue` distinct-column, KPI `value.columnId`,
element `layout.anchor`, `themeOverrides`, styled `name`, card `style`).

Supersedes `data-model-sourced-kpi-overview-with-containers.json` as the
"canonical KPI workbook" reference. Older file predates the KPI
`value.columnId` and `controlId` collision fixes.

## When to clone this exemplar

Any multi-page dashboard build with:
- 3+ pages, per-page source table (Lookup demographic passthrough)
- Mix of KPI row + line/bar/donut charts + detail table per page
- Store or customer or product picker on a detail page (uses `list` +
  `selectionMode: "single"` — not the rejected `dropdown` controlType)
- Costco-style card framing (`#FFFFFF` bg, thin border, subtle
  container accents)

**Do NOT clone this** for single-page dashboards (see
`data-model-sourced-single-page-inventory-health.json`), or for a
plain read-only exec dashboard where the base table should be hidden
rather than exposed (see `dashboard-department-scorecard.json` instead —
this exemplar predates that pattern and puts `tbl-tx` visibly on the
dashboard page). **Correction (2026-08-03):** this line previously also
said "or when the build needs UI-only features Sigma doesn't spec
(buttons, modals)" — that claim was retracted skill-wide; see
`reference/capability-ledger.md`.

## Templated placeholders

Replace before POST:
- `folderId` — destination Sigma folder UUID.
- `pages[].elements[] | select(.kind == "data-model") | .source.dataModelId` — data model UUID.
- `[Transactions/*]`, `[Customer Details/*]` etc. — swap for your data model's element display name.

## What patterns this exemplar demonstrates

**KPI patterns** (see `reference/specification/kpis.md`):
- `value.columnId` (not `value.id` — the older exemplar is wrong)
- Styled `name` object with brand color
- Element-level `layout.anchor: "middle"`
- Card-frame `style` block
- Passthrough column set for drill-through

**Chart patterns** (see `reference/specification/charts.md`):
- `bar-chart` with `orientation: "horizontal"` + categorical-descending sort
- `donut-chart` with distinct `value` and `holeValue` columns
- `line-chart` for time-series trend
- Card `style` on every viz
- `gap: {width: "medium"}` (safe default, no `betweenSets`)
- Legend positioning

**Control patterns** (see `reference/specification/controls.md`):
- `segmented` Variant A (manual `{valueType, values, labels}`)
- `segmented` Variant B (sourced from column)
- `list` with `selectionMode: "single"` (as the "dropdown" — NOT
  `controlType: "dropdown"` which POST-rejects)
- `hierarchy` control for drill-through dimensions
- Multi-binding filters (one control filters multiple elements)

**Formula patterns** (see `reference/specification/formulas.md`):
- `Lookup()` for cross-element demographic passthrough
- Same-page source-table architecture

**Layout / styling** (see `reference/specification/layout.md`,
`reference/specification/containers.md`):
- Multi-page layout XML (one `<Page>` per page, concatenated at top-level `layout`)
- Container hierarchy: header → filter bar → KPI row → chart sections
- `themeOverrides` at top-level

## Load-bearing rules this exemplar respects

- ✅ Passthrough mandate — every viz declares source-table's full column set
- ✅ Explicit `name` on every cross-referenced column
- ✅ `controlId` never collides with a column name on filtered elements
- ✅ `[Metrics/<Name>]` used for data-model metric references
- ✅ IDs are stable kebab-case (preserved through POST/PUT round-trip)
