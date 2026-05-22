# Exemplar: Multi-element catalog (single-page data-model-sourced)

## Source
Hand-built as a "kitchen sink" reference workbook by the skill author. Saved as
`Exemplar Workbook` (urlId `7pBsZqYPg2MpLAwfXI7Muy`) in the `My Documents/Claude Testing`
folder against the PLUGS data model. Round-tripped through POST + GET. IDs in
this file have been templated to placeholders.

## What this exemplar demonstrates

Single-page workbook with broad coverage of element kinds and control types,
organized as a visualization reference:

**Chart kinds present (6 of 7 supported non-table viz kinds):**
- `bar-chart` (Revenue by Store Region)
- `line-chart` (Revenue Trend by Product Type)
- `area-chart` (Revenue Over Time — stacked)
- `donut-chart` (Revenue Distribution by Product Type)
- `scatter-chart` (Profit vs Revenue by Store, top 50)
- `pivot-table` (Revenue & Profit by Region × Product Type)
- `kpi-chart` × 3 (Total Revenue, Total Profit, AOV)

**Table elements:**
- 1 plain table (passthrough columns from data-model source)
- 1 table with multi-level `groupings`:
  - `groupBy: [<region-col>, <product-type-col>]` (2-column groupBy at one level)
  - `calculations: [<3 metric cols>]`
  - `sort: [{columnId: ..., direction: "descending", nulls: "first"}]`

**Control types (4 of 5 supported):**
- `list` × 3 (Store-Name, Product-Type, Store-Region)
- `date-range` × 1 (Date)
- `text` × 1 (Cust-Name)
- `segmented` × 2 (Product-Type-1, date-part)

## Gaps — patterns NOT exemplified here
- `combo-chart` — see legacy exemplar `additional-workbook-features-chart-and-control-catalog.json` or `reference/specification/charts.md` → "Combo chart."
- `pie-chart` — see legacy exemplar `additional-workbook-features-chart-and-control-catalog.json` (donut and pie share a shape; pie example lives there).
- `control` of `controlType: "number-range"` — documented in `reference/specification/controls.md` → "number-range" only.
- `container` element — see existing `data-model-sourced-kpi-overview-with-containers.json` for the canonical container + GridContainer pattern.

## Templated placeholders

When cloning this exemplar, substitute:
- `<DATA_MODEL_ID>` — the UUID of your target data model
- `<DATA_MODEL_ELEMENT_ID>` — the data model element ID this workbook sources from
- `<DATA_MODEL_ELEMENT_NAME>` — the display name of that element (referenced in formula passthroughs like `[<DATA_MODEL_ELEMENT_NAME>/Column Name]`)
- `<DESTINATION_FOLDER_ID>` — the folder UUID where you want the new workbook to land

`scripts/api/find-file-by-urlid.sh <url-slug>` resolves Sigma URL slugs → UUIDs for the
data model and folder; `scripts/api/mcp-describe.sh datamodel <DATA_MODEL_ID>` lists the
element IDs and their display names.
