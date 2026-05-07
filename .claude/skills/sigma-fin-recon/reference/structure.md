# Recon Workbook Structure (page-by-page)

Element lists per page. When generating a new recon workbook, include at minimum
the elements marked **(required)**.

## Page: Overview

- KPI tile: `total_book` **(required)**
- KPI tile: `total_compare` **(required)**
- KPI tile: `total_variance` **(required)**
- KPI tile: `pct_matched` **(required)**
- Visualization: line chart of `abs_variance` by period **(required)**
- Filter Bar: `period_control`, `entity_control`

## Page: Variance Trend

- Visualization: stacked bar of `abs_variance` by period split by `account` or `entity` **(required)**
- Visualization: small multiples per entity (optional, when entity count ≤ 12)
- Filter Bar: `period_control`, `entity_control`, `account_control`

## Page: Variance Detail

- Pivot/table: book × compare joined on key, with columns:
  `period`, `entity`, `account`, `amount_book`, `amount_compare`, `delta`,
  `flag_matched`, `aging_bucket` **(required)**
- Conditional formatting on `delta` (red/green by sign)
- Filter Bar: `period_control`, `entity_control`, `account_control`, `materiality_control`

## Page: Exceptions

- Filtered version of Detail where `flag_matched = false` **(required)**
- Sorted by `abs(delta)` desc
- Optional notes/status columns for analyst workflow
- KPI tile: `count_unmatched`, `abs_variance` filtered to unmatched
- Filter Bar: same as Detail, plus a status filter if notes/status columns exist

## Page: Reference: Mapping (optional)

- Lookup table linking book taxonomy to compare taxonomy.
- Used as a relationship source for Detail when the two ledgers don't share keys natively.

## Sources

- `book` source — typically GL.
- `compare` source — sub-ledger, bank, ERP feed, etc.
- `mapping` source (optional) — account/code crosswalk.

## Relationships

- `book__compare` — one-to-one or one-to-many on the join key. Cardinality must
  be set explicitly so Sigma's variance math is correct.
- `book__mapping` and `compare__mapping` when a mapping table is in play.

## Folder groupings

- `Overview Inputs` — KPI metrics + headline visualization
- `Detail Inputs` — joined record-level columns and flags
- `Shared Calculations` — `delta`, `flag_matched`, `aging_bucket`, `materiality_control`
