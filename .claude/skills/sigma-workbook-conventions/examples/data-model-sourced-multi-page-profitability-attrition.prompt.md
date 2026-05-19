# Exemplar: Multi-page profitability + attrition signals

## Source prompt (verbatim — original build, 2026-05-18)

> use the Customer-Financials-461QUZu2VPny8KxImgSmfF data model to build a
> customer profitability analysis. I also want to understand what customer
> behaviors potentially lead to leaving the bank. put the analysis in the
> Claude-Testing-3Kzaga67BMlB7vVJQksjlX folder

Live workbook: `Customer-Profitability-and-Attrition-Signals-3ZVbmdF04RhgUVdBwEtBvt`
in `My Documents/Claude Testing`. Round-tripped through POST + iterative PUTs
(see `workbooks/customer-profitability-attrition/notes.md` iteration log).
IDs in this file have been templated to placeholders.

## What this exemplar demonstrates

**Multi-page workbook** — 4 pages, one top-level `layout` field, multiple
`<Page>` siblings under a single `<?xml>` declaration. Pages:

1. **Profitability Overview** — KPI row (NII, Gross Income, NIM, Customers Served) + horizontal bar (NII by Segment) + donut (NII by Customer Type)
2. **Drivers** — 4 horizontal bar charts (NII by Tenure Bracket / Age Bracket / Credit Score Band / Branch Region) + detail table
3. **Attrition Signals** — 3 KPIs (% Closed, At-Risk Customers, NII at Risk) + line chart (closures by month) + 2 horizontal bars (closure rate by segment / by tenure) + at-risk-customer table
4. **Data Sources** — utility page with the per-page source tables grouped

**Patterns exercised:**
- **Per-page source-table architecture**: each page declares its own `<FACT_ELEMENT_NAME>`, `<CUST_DIM_ELEMENT_NAME>`, `<BRANCH_DIM_ELEMENT_NAME>` source tables (suffixed P1/P2/P3) — required because `Lookup()` resolves only against same-page siblings.
- **Cross-element `Lookup()` joins**: customer demographics (Customer Name, Segment, Risk Rating, Age, etc.) and branch dims (Branch Region, etc.) joined onto the central fact via `Lookup()` calls on a derived enriched table per page.
- **Computed bucket columns**: tenure bracket, age bracket, credit-score band, recently-closed flag — `If` chains on the enriched table.
- **Bar-chart orientation rule (Phase 3)**: every bar chart with a categorical x-axis uses `orientation: "horizontal"` + `xAxis.sort = {by: "<yAxis-col-id>", direction: "descending"}`. The line chart on Page 3 (`Account Closures by Month`) stays vertical because its x-axis is time-series.
- **Drill-down passthrough**: every chart declares the full passthrough column set from its source table (10–18 columns each), so right-click drill exposes the dimension hierarchy.
- **Data-model metrics**: `[Metrics/Net Interest Income]`, `[Metrics/Gross Income]`, `[Metrics/Net Interest Margin (NIM)]` — never hand-derived.
- **Safe-divide pattern (Phase 5)**: `Zn(N/D)` and `If([D]=0, Null, [N]/[D])` — no `DivideSafe` references.
- **Column `format` field (Phase 6b)**: `{kind: "number", formatString: "$,.2f"}` on the NII-at-Risk KPI value column — verified shape that survives round-trip.
- **Container-based layout**: header bar + KPI row + chart row + detail row containers wrap related elements on each page.
- **5 controls per page** with workbook-unique `controlId`s (suffixed `-P1`/`-P2`/`-P3`).

## Templated placeholders

When cloning this exemplar, substitute:
- `<DATA_MODEL_ID>` — UUID of the target data model (single — the original workbook used one data model with multiple elements)
- `<FACT_ELEMENT_ID>` — element ID of the central fact table
- `<CUST_DIM_ELEMENT_ID>` — element ID of the customer dimension
- `<BRANCH_DIM_ELEMENT_ID>` — element ID of the branch dimension
- `<FACT_ELEMENT_NAME>` — display name of the fact element (referenced in `[<FACT_ELEMENT_NAME>/Column Name]` formulas)
- `<CUST_DIM_ELEMENT_NAME>` — display name of the customer dim
- `<BRANCH_DIM_ELEMENT_NAME>` — display name of the branch dim
- `<DESTINATION_FOLDER_ID>` — folder UUID for the new workbook

To clone-and-modify against a different domain (e.g., retail customer LTV instead of banking profitability):
1. Substitute all placeholders above for your target data model + folder.
2. Workbook-internal table names (`Customer Financials P1`, `Customer Master P1`, etc.) are NOT templated — they're internal display names. Rename in-place if your domain differs (e.g., `Customer Master P1` → `Customer Profile P1` for retail).
3. Update bucket-column formulas (tenure, age, credit bands) for your domain's relevant dimensions.
4. Update KPI names + chart titles for your domain.

## Iteration history

See `workbooks/customer-profitability-attrition/notes.md` for the full audit trail —
4 iterations (initial POST, drill-passthrough + DivideSafe fix, orientation/sort
fix, format-field re-add). All iterations preserved with timestamps in
`workbooks/customer-profitability-attrition/iterations/`.
