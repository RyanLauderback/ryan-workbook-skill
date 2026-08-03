# `dashboard-department-scorecard.json` — design intent

**Canonical "dashboard" tier exemplar**, per `reference/workflows/composition.md`'s
sizing ladder — a plain, read-only exec dashboard (no buttons, no actions,
no agents). Authored 2026-08-03 to close two gaps found during capability-
expansion planning:

1. No existing exemplar demonstrated `composition.md`'s "hidden base table"
   default — the flagship 3-page exemplar
   (`data-model-sourced-sales-command-center.json`) puts its base table
   (`tbl-tx`) visibly on the dashboard page.
2. No exemplar demonstrated the exec-KPI recipe found in a real, shipped
   production dashboard (Bergey's Unified Insights, harvested 2026-08-03):
   `style:{borderRadius:"round", borderColor, borderWidth:1}` +
   `periodComparison` + `timeline` + a styled `name` object, repeated
   consistently across every KPI tile.

## When to clone this exemplar

Any single-page (or single-dashboard-page-plus-hidden-source-page) build
where the request is "a dashboard" per `composition.md`'s sizing ladder —
KPI row, one or two charts, a supporting ranked table, a filter control,
explicit layout — and the base/source data doesn't need to be visible to
the end user.

**Do NOT clone this** for the "single thing" or "focused view" tiers
(skip the hidden-source-page ceremony entirely — see `composition.md`),
or for an interactive-app build that needs writeback/agents/buttons —
those capabilities are real and supported (see
`reference/capability-ledger.md`) but this exemplar deliberately doesn't
reach for them, since they hadn't yet been through the Wave 0 POST probe
at the time this was authored. Use a plain-dashboard exemplar as the base
only once that probe confirms authoring, not just GET-spec reading,
round-trips.

## Templated placeholders

Replace before POST:
- `folderId` — destination Sigma folder UUID.
- `<data-model-id>` / `<data-model-element-id>` — your data model + element UUIDs.
- `[<Data Model Element>/*]` — swap for your data model element's actual display name.

## What patterns this exemplar demonstrates

**Composition (see `reference/workflows/composition.md`):**
- The "dashboard" tier of the sizing ladder — KPI row, one chart, one
  ranked table, one filter control, explicit layout XML.
- **Hidden base table** — `page-data-source` carries `visibility:"hidden"`
  and holds only `tbl-base`; every dashboard element sources it via
  `elementId`, never re-declaring the raw data model connection.
- **Ranked chart and ranked table both sorted by the metric being
  ranked on** — `chart-rev-by-region`'s `xAxis.sort` is `{by:
  "rbr-revenue", direction: "descending"}`; `tbl-top-stores`'s `sort` is
  `[{columnId: "tts-revenue", direction: "descending"}]`. Neither is
  sorted alphabetically by name.
- No intermediate join is exposed — `tbl-base` sources directly from the
  data model; there's no join step to hide in the first place at this
  scale, which is itself the point (avoid introducing one just to look
  more "enterprise").

**KPI patterns (see `reference/specification/kpis.md`) — the exec-KPI recipe:**
- `style: {borderRadius: "round", borderColor: "#e8dfd3", borderWidth: 1}`
  on every KPI tile — a soft card frame, not the default flat tile.
- `timeline: {columnId}` + `periodComparison: "month"` — verified present
  in a real production dashboard (Bergey's Unified Insights) across ~67
  KPI instances, repeated with the same recipe every time.
- Styled `name` object (`{text, color, fontWeight, fontSize}`) rather
  than a plain string — matches every other KPI exemplar in this skill.

**Table patterns (see `reference/specification/tables.md`):**
- `groupings` + `summary` — the summary-bar (aggregate-then-categorize)
  pattern for the ranked-store table.
- Full passthrough columns (`tts-date`, `tts-cost`) present but not
  displayed in `order` — available for drill-through per the passthrough
  mandate, without cluttering the visible column set.

## Load-bearing rules this exemplar respects

- Passthrough mandate — every viz declares the base table's relevant
  columns with a stable `id`.
- Explicit `name` on every cross-referenced column.
- `controlId` (`OvDateRange`) doesn't collide with any column name.
- `[Metrics/<Name>]` used for data-model metric references
  (`Total Revenue`, `Distinct Orders`); non-metric passthrough uses
  `[<Data Model Element>/<Column>]`.
- Validated clean: `python3 scripts/validate-spec.py` — 0 fail, 0 warn.

## Known gap, not yet fixed

`scripts/workbook-manifest.py` doesn't yet recognize `periodComparison`/
`timeline` as known KPI keys (it will flag them as "unknown_keys" —
harmless, just a manifest-registry gap, not a spec defect). Follow-up,
not blocking.
