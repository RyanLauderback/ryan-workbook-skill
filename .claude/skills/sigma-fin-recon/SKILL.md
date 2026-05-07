---
name: sigma-fin-recon
description: >-
  Use when the user wants to build, edit, or audit a financial reconciliation
  workbook in Sigma — GL tie-out, sub-ledger to GL recon, bank recon, intercompany
  recon, or any "compare two ledgers and surface variances" dashboard. Provides
  the canonical page structure (Overview, Variance Trend, Detail, Exceptions),
  standard KPIs (total variance, % matched, aging buckets), and an exemplar
  spec to anchor generation. Requires sigma-api and sigma-data-models;
  pair with sigma-workbook-conventions for naming/layout rules.
---

# Sigma Financial Reconciliation Workbook Skill

Generate / edit / audit Sigma reconciliation workbooks. This is a
**workbook-pattern skill** — it prescribes what a recon workbook should look
like, leaving field-level mechanics to `sigma-data-models`.

## When this skill is the right one

- User says "reconciliation," "tie-out," "GL recon," "variance dashboard," or
  describes comparing two source ledgers and surfacing differences.
- User has, or can produce, two sources: a "book" (e.g. GL) and a "compare"
  (e.g. sub-ledger, bank statement, ERP feed).

If the request is a generic financial dashboard (P&L, cash flow, AR aging) with
no compare-and-variance pattern, this is NOT the right skill — fall back to
`sigma-data-models` + `sigma-workbook-conventions`.

## Prerequisites

1. `sigma-api` skill has produced `$SIGMA_API_TOKEN`.
2. The two source tables (book + compare) exist as Sigma sources or warehouse
   tables the credentialed account can read.
3. A join key exists between book and compare (transaction ID, account+date+amount, etc.).

## Canonical structure

Every recon workbook produced by this skill should have these pages, in order:

1. **Overview** — KPI tiles: `total_book`, `total_compare`, `total_variance`,
   `pct_matched`. One headline visualization (variance over time).
2. **Variance Trend** — time series of `abs(book - compare)` by period. Include
   a period control and a category drill (account, entity, etc.).
3. **Variance Detail** — record-level join of book vs compare with delta column,
   match flag, and aging bucket. This is the workbench for analysts.
4. **Exceptions** — filtered Detail showing only `flag_matched = false`, sorted
   by `abs(delta)` desc. Add an action column (notes / status) for follow-up.
5. **Reference: Mapping** (optional) — account/code mapping table if the recon
   requires translating between book and compare taxonomies.

## Canonical KPIs

Names follow `sigma-workbook-conventions`. Define every recon workbook with
at least these:

| Metric ID | Definition | Format |
|-----------|------------|--------|
| `total_book` | sum of book-side amount | currency |
| `total_compare` | sum of compare-side amount | currency |
| `total_variance` | `total_book - total_compare` | currency, signed |
| `abs_variance` | `abs(total_variance)` | currency |
| `count_unmatched` | rows where `flag_matched = false` | integer |
| `pct_matched` | `1 - count_unmatched / count_total` | percent, 1 decimal |
| `aging_bucket` | bucketing of unmatched age (0–7d, 8–30d, 31–90d, 90d+) | categorical |

## Standard controls

- `period_control` — date range bound to the book-side date column.
- `entity_control` — multi-select on entity/legal-entity dimension.
- `account_control` — multi-select on account dimension.
- `materiality_control` — numeric threshold; rows with `abs(delta) < threshold`
  are excluded from the Exceptions page only.

## Exemplar

`examples/exemplar-spec.json` is the anchor. **It is currently a stub** — replace
it with a real exported recon workbook from the user's Sigma org via
`scripts/export-workbook.sh`, then refresh `reference/structure.md` and
`reference/kpis.md` to match the real exemplar. Skill stays valuable even
without the exemplar but is much sharper with it.

## Reference

- `reference/structure.md` — page-by-page breakdown with element lists.
- `reference/kpis.md` — full metric definitions (formula, format, dependencies).

For field-level questions (how to express a metric, how relationships work,
how column-level security applies) defer to `sigma-data-models/reference/`
in the upstream skill (mirrored at `vendor/sigma-agent-skills/`).
