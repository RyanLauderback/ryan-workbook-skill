# Recon Workbook KPIs

All formulas use Sigma function syntax. Display labels follow
`sigma-workbook-conventions/reference/naming.md` (verb prefix in the ID, plain
human label for display).

| ID | Formula (Sigma) | Format | Depends on |
|----|-----------------|--------|------------|
| `total_book` | `Sum([book/amount])` | currency | `book.amount` |
| `total_compare` | `Sum([compare/amount])` | currency | `compare.amount` |
| `total_variance` | `[total_book] - [total_compare]` | currency, signed | both totals |
| `abs_variance` | `Abs([total_variance])` | currency | `total_variance` |
| `count_total` | `Count([book/key])` | integer | `book.key` |
| `count_matched` | `CountIf([flag_matched])` | integer | `flag_matched` |
| `count_unmatched` | `[count_total] - [count_matched]` | integer | totals |
| `pct_matched` | `[count_matched] / [count_total]` | percent, 1 decimal | counts |
| `flag_matched` | `Abs([amount_book] - [amount_compare]) < [materiality_control]` | boolean | record-level join + control |
| `aging_bucket` | `If([age_days] <= 7, "0–7d", If([age_days] <= 30, "8–30d", If([age_days] <= 90, "31–90d", "90d+")))` | categorical | `age_days` |
| `age_days` | `DateDiff("day", [period_book], Today())` | integer | record-level join |

## Materiality

`materiality_control` is a numeric control with a sensible default ($0.01) and
governs `flag_matched` only. Make sure it exists at the model level (not a single
page) so it applies wherever `flag_matched` is referenced.

## Notes

- When the book and compare sides use different currencies, normalize to a single
  reporting currency BEFORE computing `delta` — leave that translation in the
  source layer or as an early derived column, not as part of the metric formulas.
- When join cardinality is one-to-many (one GL line, many sub-ledger entries),
  aggregate the compare side to one-per-key before joining; otherwise `total_compare`
  will double-count.
