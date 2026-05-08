# Plugs Customer Performance — notes

**Workbook:** https://staging.sigmacomputing.io/papercranestaging/workbook/Plugs-Customer-Performance-56h0yALVIXys5BAMrdR0UB
**Workbook ID:** `a79bfefc-e643-45da-9753-72c76272617d`

## What got built

Single-page Customer Performance Analysis dashboard. 18 elements: 3 containers,
1 title, 5 controls, 3 KPIs, 4 bar charts, 2 source tables.

Filters: Date range, Cust Region, Loyalty Program, Store Region, Product
Family. KPIs: Total Customers (CountDistinct Cust Key), Total Revenue
(Sum Quantity × Price), Total Items Sold (Sum Quantity). Charts: Revenue by
Customer Region, Revenue by Store, Customers by Revenue (desc), Products by
Quantity (desc).

## Iterations

| Timestamp (UTC) | Result | Why |
|---|---|---|
| 2026-05-08T02:52:17Z | HTTP 400 | Column inference: KPI references `[Plugs Transaction Details/Date]` failed because passthrough columns on `tbl-plugs-tx` had no explicit `name`. |
| 2026-05-08T03:22:22Z | HTTP 400 | Added explicit names + reordered tables-first; new error: `[Plugs Transaction Details - Relationships/Cust Key]` not resolvable on the data-model element. |
| 2026-05-08T03:29:50Z | HTTP 200 | Pivoted `tbl-plugs-tx` to `warehouse-table` source. All transaction columns including Cust Key resolve. Lookup() against data-model-sourced `tbl-customer-details` brings in 14 customer demographic fields. Replaced `[Metrics/Revenue]` with inline `Sum([Quantity] * [Price])` because metrics live on the data-model element only. Format objects rejected (`Missing "kind" field`) and stripped — currency formatting can be set in UI. |

## Findings to promote into the skill

1. **The data model element `Plugs Transaction Details - Relationships`
   exposes `Cust Key`, `Customer Name`, and `Cust Json` columns in its
   `GET /v2/dataModels/{id}/spec` JSON, but the workbook formula resolver
   cannot reference them via `[Plugs Transaction Details - Relationships/<Col>]`.**
   Other columns on the same element (Date, Quantity, Store Region, etc.)
   resolve fine. Hypothesis: the warehouse source table doesn't actually
   expose these columns and the data-model element has stale/orphaned column
   definitions. Workaround: source the workbook table from the warehouse
   table directly.
2. **Workbook columns must have an explicit `name` field if they will be
   referenced by display name from sibling elements.** Inferred names from
   passthrough formulas (e.g. `formula: "[Source/Date]"` without `name`)
   work in the GET-back exemplar but fail at POST time. Always set
   `name: "Date"` etc. on referenced columns.
3. **Column `format` requires a `kind` field.** `{ "type": "number",
   "format": "currency", "currency": "USD" }` is rejected. Exact shape
   undocumented in the existing reference; configure in UI and GET-back to
   discover the right shape. Until then, omit `format` from POST bodies.
4. **Warehouse-sourced tables can't reference `[Metrics/<Name>]`.** Metrics
   live on data-model elements only. When a workbook table sources from a
   warehouse table, replace metric formulas with inline aggregations
   (`Sum([Quantity] * [Price])`).
5. **Workbook DELETE endpoint needs investigation.** Both
   `DELETE /v2/workbooks/{id}` and `DELETE /v2/files/{id}` returned 404
   against staging for newly-created workbooks. Two test workbooks remain
   in the staging folder and need manual UI cleanup: `8bcf86f2-...` and
   `9c2870ea-...`.

## Open questions for the user

- **Visually verify in the UI**: do the Lookup() customer columns populate
  with non-null values, or are they all NULL because the warehouse
  CUST_KEY/D_CUSTOMER.CUST_KEY don't actually overlap? If they're empty,
  the join key mismatch on D_CUSTOMER side needs checking.
- **Currency formatting** on Revenue KPIs/charts is currently default
  number — would you like me to discover the correct `format` shape via
  UI configure → GET-back diff?
