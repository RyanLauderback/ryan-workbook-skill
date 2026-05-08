# Plugs Overview Dashboard — Notes

## Goal

Greenfield Overview workbook over the `Plugs Example Data Model`: 3 KPI tiles
(Revenue / COGS / Profit Margin) sourced from the data model's existing
metrics, a monthly Revenue bar chart, the full data-model node table, and a
filter trio (Date / Store Region / Product Family). Audience: internal Sigma
testing — second end-to-end build, applying the iteration-3 lessons from
`plugs-revenue-monthly`.

## Data sources

- Data model: `Plugs Example Data Model` (id `47d94152-6448-4cd2-9266-f3076d53cc59`)
- Element: node `aFkvPq8xkX` (`Plugs Transaction Details - Relationships`)
- Metrics referenced via `[Metrics/X]`: Revenue, COGS, Profit Margin
- Per-row Revenue calc on the table: `[Price] * [Quantity]`

## Live workbook

- URL: <https://staging.sigmacomputing.io/papercranestaging/workbook/34HTASYvMtpOaWYwo6qAN1>
- workbookId: `6510c976-e8f1-4fcb-9fb5-80fbf394c2ff`
- Folder: `My Documents/Claude Testing`

## Iteration log

| Date | Iteration file | What worked | What broke | Promoted? |
|------|----------------|-------------|------------|-----------|
| 2026-05-07 12:58 | `iterations/20260507-1258.json` | structure, control bindings by stable column id, `[Metrics/X]` everywhere, full passthrough table | KPI element rejected with `Invalid kind: "kpi"` — Sigma's example-library YAML uses `kind: kpi` but the API requires `kpi-chart` | n/a |
| 2026-05-07 12:59 | `iterations/20260507-1259.json` | sed-replaced `kpi` → `kpi-chart`, HTTP 200, all 8 elements created | first visual review: KPIs lacked titles + period comparison | **YES** — docs/API kind mismatch + `kpi-chart` shape added to skill |
| 2026-05-07 14:12 | `iterations/20260507-1412-from-sigma.json` (user UI fix, pulled back) | user added a page title text element, wrapped header bar + KPI/chart body into two containers, added `DateTrunc("month", [Date])` column on each KPI for timeline comparison, resized KPIs from 3 rows tall to 9 rows tall | nothing — `documentVersion: 2` is the new known-good baseline | **YES** — see "Promoted patterns" below; new exemplar saved |

## Open questions / decisions

- Bar chart angle = monthly Revenue. Could swap to Revenue by Product Family
  or Store Region in a follow-up if more useful.
- KPI comparison-period (vs prior month / quarter / year) is **not** part
  of the code representation — confirmed with user 2026-05-07. The spec only
  carries the date-dimension column that enables comparison mode; the
  selected period is UI-side state. Documented as a code-rep scope gap in
  `.claude/skills/sigma-workbook-conventions/reference/workbook-spec-api.md`
  §"Scope of the code representation". Closing this open question.

## Promoted patterns (in skills + exemplars)

Promoted from this workbook into the skill:

- **`kpi-chart` vs `kpi` kind mismatch** — `reference/workbook-spec-api.md`
  §"Element kinds" table.
- **KPI shape with timeline comparison** — `reference/workbook-spec-api.md`
  §"KPI element shape" now shows the date-dimension column pattern.
- **Container element kind + `<GridContainer>` layout XML** —
  `reference/workbook-spec-api.md` §"Container element shape" + expanded
  §"Layout" with the parent/child grid model.
- **Text element kind for page titles** — `reference/workbook-spec-api.md`
  §"Text element shape" + §"Visualization clarity" rule #1 (page-level
  title text element required).
- **Page-structure pattern** (header container with title+controls; body
  container with KPI row + chart; bare table at bottom) —
  `reference/workbook-spec-api.md` §"Page-structure pattern".
- **KPI sizing rule** (8–10 grid rows for sparkline legibility) —
  Visualization clarity rule #5.

Exemplars added:

- `workbooks/_exemplars/data-model-sourced-kpi-overview-with-containers.json`
- `.claude/skills/sigma-workbook-conventions/examples/data-model-sourced-kpi-overview-with-containers.json`
