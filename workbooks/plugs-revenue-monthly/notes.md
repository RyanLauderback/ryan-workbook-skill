# Plugs Revenue — Monthly — Notes

## Goal

Simple starter workbook over the `Plugs Example Data Model`: one page with a
date-range filter, a monthly revenue bar chart, and a flat table from the
`Plugs Transaction Details - Relationships` (node `aFkvPq8xkX`) data-model
element. Audience: internal Sigma testing. First end-to-end test of the
workbooks-as-code API.

## Data sources

- Data model: `Plugs Example Data Model` (urlId `2bzJWNEAYknlm565o2lCcx`,
  internal id `47d94152-6448-4cd2-9266-f3076d53cc59`)
- Element: `aFkvPq8xkX` (`Plugs Transaction Details - Relationships`,
  join of `PLUGS_ELECTRONICS_HANDS_ON_LAB_DATA` ⟕ `D_PRODUCT`)
- **Metrics on the data-model node** (use these — don't re-derive):
  - `Revenue` = `Sum([Quantity] * [Price])`, currency-formatted
  - `COGS` = `Sum([Quantity] * [Cost])`, currency-formatted
  - `Profit Margin` = `(Sum(Q*P) - Sum(Q*C)) / Sum(Q*P)`, percent-formatted

## Live workbook

- URL: <https://staging.sigmacomputing.io/papercranestaging/workbook/Plugs-Revenue-Monthly-6BrLA2Gu9lBt40HTSZV66z>
- workbookId: `d8fc91eb-6b79-4d6b-9b5c-a4b1d1adde37`
- Folder: `My Documents/Claude Testing` (id `eb548e3b-81e4-46d9-adfd-488ae1dfb0bb`)
- documentVersion: 2 (after user's manual UI fix)

## Iteration log

| Date | Iteration file | Prompt file | What worked | What broke | Promoted? |
|------|----------------|-------------|-------------|------------|-----------|
| 2026-05-07 12:31 | `iterations/20260507-1231.json` | `prompts/20260507-1231.md` | top-level structure (pages/elements/layout) | column formulas referenced warehouse-table namespace (`[PLUGS_ELECTRONICS_HANDS_ON_LAB_DATA/Date]`) — server rejected with `dependency not found` (HTTP 400) | n/a |
| 2026-05-07 12:33 | `iterations/20260507-1233.json` | `prompts/20260507-1231.md` | HTTP 200 — workbook created | **rendered broken**: declared only `col-revenue` on the table, assumed the rest "inherited" from the data-model source — false. Bar chart's `[Date]` and control's `columnId: "Date"` had nothing to bind to. Used `[Price] * [Quantity]` instead of the data model's `[Metrics/Revenue]`. | n/a (corrected next iter) |
| 2026-05-07 12:48 | `iterations/20260507-1248-from-sigma.json` (user's UI fix, pulled back) | n/a | known-good baseline: every column declared explicitly on table AND chart with stable ids; control binds via column id (`zjXo8KcTRL`); bar chart Y-axis uses `[Metrics/Revenue]`. | nothing — currently rendering. | **YES** — promoted to `.claude/skills/sigma-workbook-conventions/reference/workbook-spec-api.md` and `workbooks/_exemplars/data-model-sourced-simple-overview.json` |

## Open questions / decisions

- **Spec format** — server accepts JSON on POST and returns JSON when `Accept: application/json` is set; otherwise YAML. We're storing JSON.
- **Column ids** — Sigma auto-generates short alphanumeric ids (`zjXo8KcTRL`, `-843A_GZb1`) when the user adds columns via the UI. When we author a spec, prefer human-readable ids (`col-date`, `col-quantity`) so diffs are legible. Sigma preserves whatever ids we POST.
- **Layout normalization** — Sigma adds `<?xml version="1.0" encoding="utf-8"?>` prolog and a trailing newline to the layout XML on save.

## Promoted patterns (now in skills/exemplars)

- **`.claude/skills/sigma-workbook-conventions/reference/workbook-spec-api.md`** — endpoints, source kinds, the column-declaration rule, formula namespaces, control wiring, layout, and a minimal data-model-fed recipe.
- **`workbooks/_exemplars/data-model-sourced-simple-overview.json`** — the `documentVersion: 2` spec, frozen as the canonical reference for "data-model-fed table + chart with `[Metrics/X]` + date-range control".
- **`SKILL.md`** updated with three-rule summary at the top of the gotchas section.