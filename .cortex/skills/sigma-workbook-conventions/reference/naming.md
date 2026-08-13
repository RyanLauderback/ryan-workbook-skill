# Naming Reference

Detailed naming rubric for Sigma workbook elements in this repo.

## Pages

| Type | Pattern | Example |
|------|---------|---------|
| Overview | "Overview" | `Overview` |
| Trend / time-series | `<Subject> Trend` | `Revenue Trend` |
| Detail / record-level | `<Subject> Detail` | `Variance Detail` |
| Exception list | `<Subject> Exceptions` | `GL Exceptions` |
| Glossary / reference | `Reference: <Topic>` | `Reference: Account Mapping` |

## Columns

- Internal ID: `snake_case`. Prefix raw source columns as the source delivers them; prefix derived columns with the calculation type (`calc_`, `bucket_`, `flag_`).
- Display label: `Title Case`, no abbreviations unless universally known.
- Date columns: suffix `_date`. Datetime columns: suffix `_at`.
- Boolean flags: prefix `flag_`, label as a question or condition ("Is Reconciled?").

## Metrics

- ID starts with an action verb: `total_`, `count_`, `avg_`, `min_`, `max_`, `pct_`, `ratio_`.
- Display label drops the verb prefix when it reads natural ("Total Revenue", not "Total Total Revenue").
- Always set an explicit format on currency, percent, and count metrics — don't rely on Sigma defaults.

## Filters and Controls

- Suffix `_filter` for filters, `_control` for parameter/segment/range controls.
- Bind controls to the dimension they govern; do not reuse one control across unrelated dimensions.
- Date range controls: `<dimension>_date_range_control`.

## Relationships

- Naming pattern: `<from_table>__<to_table>` with double underscore.
- Always specify cardinality (`one_to_many`, etc.) explicitly even when Sigma would infer it.

## Folder groupings

- Top-level folders match page sections (`Overview Inputs`, `Detail Inputs`, `Shared Calculations`).
- Inside a folder, order is: sources → keys → measures → derived → flags.
