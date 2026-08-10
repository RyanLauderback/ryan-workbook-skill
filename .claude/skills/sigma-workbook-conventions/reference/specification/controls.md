# Controls

Interactive filter elements — dropdowns, date pickers, text inputs,
sliders, toggles, etc. They live in the page's `elements` array alongside
tables and charts, **not** nested inside them.

```bash
jq -r '.components.schemas | keys[] | select(test("Control"))' /tmp/sigma-api.json
jq '.components.schemas.ListControl, .components.schemas.DateRangeControl, .components.schemas.TextControl' /tmp/sigma-api.json
```

The wiring (which column a control filters, which downstream elements
respond) is the part of the design that the OpenAPI doesn't really
teach — that's what this file is for.

## Table of contents

- [Common fields](#common-fields)
- [`controlId` vs `id` — both required](#controlid-vs-id--both-required)
- [Element-level styling](#element-level-styling)
- Control types:
  - [`list` (dropdown / multi-select)](#list-dropdown--multi-select)
  - [`date-range`](#date-range) (with 8 modes)
  - [`text` — single-line text filter](#text--single-line-text-filter)
  - [`text-area` — multi-line text input](#text-area--multi-line-text-input)
  - [`number-range`](#number-range)
  - [`slider` / `range-slider`](#slider-variants--slider-and-range-slider)
  - [`toggle` / `checkbox`](#toggle--checkbox--boolean-switch)
  - [`dropdown` / `radio` — NOT accepted](#dropdown--radio--not-accepted-use-list--selectionmode-single)
  - [`segmented`](#segmented--pill-button-single-select) (with manual + column variants)
  - [`hierarchy`, `switch`, `date`, `number`](#additional-controltype-variants)
  - [Numeric parameter control referenced from formulas](#numeric-parameter-control-referenced-from-formulas)
- Patterns:
  - [One control, multiple elements](#one-control-multiple-elements)
  - [One element, multiple controls](#one-element-multiple-controls)
  - [Control/column ID collision (CRITICAL)](#controlcolumn-id-collision-critical)
  - [Where control bindings apply](#where-control-bindings-apply)
  - [Inherited-from-data-model controls](#inherited-from-data-model-controls)
- [Element-level filters — `top-n`](#element-level-filters--top-n)

---

## Common fields

| Field | Required | Notes |
|---|---|---|
| `kind` | yes | Always `"control"` |
| `id` | yes | Element ID — must be unique on the page |
| `controlId` | yes | Formula reference name (e.g., `RegionFilter`). **Must NOT match a column `name` or `id` on filtered elements** — see `reference/conventions.md` → "Control/column ID collision" |
| `controlType` | yes | Determines the widget + filter behavior (see variants below) |
| `name` | yes | Display label |
| `source` | usually | Points at the column whose values populate the control. Shape: `{kind: "source", source: {kind: "table", elementId: ...}, columnId: ...}` |
| `filters` | yes | Array of `{source: {kind: "table", elementId: ...}, columnId: ...}` — connects the control to the column(s) it filters |

## `controlId` vs `id` — both required

- `id` is the **element ID** used internally and in `layout.md`.
- `controlId` is a **human-facing handle** used when referring to this
  control's value from formulas or downstream logic. Pick it to be
  meaningful (e.g., `RegionFilter`, `DateRange`).

They are not the same; both are required.

## Element-level styling

Controls accept the same top-level `style` object as viz elements,
typically just `{backgroundColor, borderRadius}` (no border):

```json
"style": {
  "backgroundColor": "#FAF7F2",
  "borderRadius": "round"
}
```

See `containers.md` → "Common style recipes" → "Subtle control fill."

---

## `list` (dropdown / multi-select)

```json
{
  "kind": "control",
  "id": "ctrl-region",
  "controlId": "RegionFilter",
  "name": "Store region",
  "controlType": "list",
  "mode": "include",
  "selectionMode": "multiple",
  "values": [],
  "source": {
    "kind": "source",
    "source": { "kind": "table", "elementId": "sales-table" },
    "columnId": "col-region"
  },
  "filters": [
    {
      "source": { "kind": "table", "elementId": "sales-table" },
      "columnId": "col-region"
    }
  ]
}
```

- `mode`: `include` | `exclude`
- `selectionMode`: `single` | `multiple`
- `values`: initial selected values. `[]` = none pre-selected.

## `date-range`

A date-range control filters one or more date columns. The widget
shape is determined by `mode`, and each mode takes different additional
fields. **8 modes** are supported. No `source` is needed — the
column is defined by the `filters` binding.

Common shape:

```json
{
  "kind": "control",
  "id": "ctrl-date",
  "controlId": "DateFilter",
  "name": "Date range",
  "controlType": "date-range",
  "mode": "<see below>",
  "includeNulls": "when-no-value-is-selected",
  "filters": [
    {
      "source": { "kind": "table", "elementId": "sales-table" },
      "columnId": "col-date"
    }
  ]
}
```

`includeNulls`: `always` | `never` | `when-no-value-is-selected`.

### Modes

| Mode | Extra fields | Use for |
|---|---|---|
| `between` | `startDate?`, `endDate?` (ISO 8601) | Inclusive range. Both optional — omitting shows the picker with no preset. |
| `last` | `value` (number), `unit`, `includeToday` (bool) | "Last N days/weeks/months." |
| `next` | `value`, `unit`, `includeToday` | "Next N days/weeks/months." |
| `current` | `unit` | "This year/quarter/month/week/day." |
| `on` | `date` (ISO 8601) | Exact date match. |
| `before` | `date` | Strictly before a fixed date. |
| `after` | `date` | Strictly after a fixed date. |
| `custom` | `startDate`, `endDate` (each: ISO string OR `{op, unit, value}` for relative) | Mixed fixed/relative bounds. |

`unit` values: `year`, `quarter`, `month`, `week-starting-sunday`,
`week-starting-monday`, `day`, `hour`, `minute`.

For relative `startDate` / `endDate` shapes (used in `custom` mode):

```json
{ "op": "now-minus", "unit": "day", "value": 30 }
```

`op`: `now-minus` or `now-plus`.

### Examples

**Last 70 days:**

```json
{ "mode": "last", "value": 70, "unit": "day", "includeToday": true }
```

**This quarter:**

```json
{ "mode": "current", "unit": "quarter" }
```

**Fixed range:**

```json
{ "mode": "between", "startDate": "2026-01-01", "endDate": "2026-03-31" }
```

**Last 90 days through today (custom mode with relative bounds):**

```json
{
  "mode": "custom",
  "startDate": { "op": "now-minus", "unit": "day", "value": 90 },
  "endDate":   { "op": "now-minus", "unit": "day", "value": 0 }
}
```

**Caution — `last`/`next`/`current` modes anchor to the real calendar
date, not the data's date range.** `mode:"last"` (and `next`/`current`)
resolves relative to *today, at render time* — pushed down as a literal
`WHERE date BETWEEN <today-minus-N> AND <today>` clause into the compiled
SQL. Verified 2026-08-03: a dashboard built against a synthetic/seeded
dataset (a `PERFORMANCE_TESTING_DB` warehouse table with no relationship
to the real calendar) used `mode:"last", value:24, unit:"month",
includeToday:true` as the default filter and rendered **completely
blank** — every KPI, chart, and table empty — because the dataset's actual
dates didn't fall inside the resulting 24-months-before-today window. No
error anywhere: POST succeeded, `verify-workbook.sh` and
`audit-workbook-schema.sh` both reported clean (this is a *filtering*
problem, not a compile or schema error, so neither check catches it).
Diagnosed via `GET /v2/workbooks/{id}/elements/{eid}/query` (the same
compiled-SQL-preview endpoint `verify-workbook.sh` uses) — the pushed-down
date `WHERE` clause was directly visible in the SQL text. **Default a
date-range control to `mode:"between"` with no `startDate`/`endDate`**
(fully open, no restriction) unless the user's prompt specifically named
a relative window ("last 90 days") *and* you've confirmed via recon that
the data actually has recent rows — don't default to a "last N" window
just because it's a common dashboard convention.

## `text` — single-line text filter

```json
{
  "kind": "control",
  "id": "ctrl-search",
  "controlId": "SearchText",
  "name": "Search",
  "controlType": "text",
  "mode": "contains",
  "value": "",
  "case": "insensitive",
  "includeNulls": "when-no-value-is-selected",
  "filters": [
    {
      "source": { "kind": "table", "elementId": "sales-table" },
      "columnId": "col-product-name"
    }
  ]
}
```

`mode` values: `equals`, `does-not-equal`, `contains`,
`does-not-contain`, `starts-with`, `ends-with`, `like`,
`matches-regexp`, and their negations.

`case`: `sensitive` | `insensitive`.

## `text-area` — multi-line text input

Same shape as `text`, different widget:

```json
{
  "kind": "control",
  "controlType": "text-area",
  "mode": "contains",
  "value": "",
  "case": "insensitive"
}
```

## `number-range`

```json
{
  "kind": "control",
  "id": "ctrl-amount",
  "controlId": "AmountFilter",
  "name": "Amount",
  "controlType": "number-range",
  "mode": "between",
  "values": [0, 1000],
  "filters": [
    {
      "source": { "kind": "table", "elementId": "sales-table" },
      "columnId": "col-amount"
    }
  ]
}
```

> **Round-trip gap:** as of 2026-04, `values` on a `number-range`
> control does not reliably round-trip. A PUT with `values: [1, 10]`
> reads back as `values: null` on the next GET. The UI still respects
> the initial value when the workbook renders, but the source-of-truth
> view via the API shows `null`. Don't rely on a subsequent GET to
> confirm the value stuck — open the workbook or trust the last-known
> PUT.

## Slider variants — `slider` and `range-slider`

Verified 2026-07-02: `slider` and `range-slider` are both distinct
`controlType` values, separate from `number-range`. Inspect the
OpenAPI shape for each before authoring, as the field set differs:

```bash
jq -r '.components.schemas | keys[] | select(test("Slider|Range"))' /tmp/sigma-api.json
```

- **`slider`** — single-thumb numeric slider.
- **`range-slider`** — dual-thumb range slider (visually distinct from
  `number-range`, which is a number-input pair).
- **`number-range`** — see the section above; input-field based.

Historical note: an earlier version of this doc claimed slider was
just `number-range`. That was wrong — `element-showcase` uses `slider`
and `range-slider` as first-class control types.

## `toggle` / `checkbox` — boolean switch

Both share the shape; the type picks the widget:

```json
{
  "kind": "control",
  "id": "ctrl-active-only",
  "controlId": "ActiveOnly",
  "name": "Active only",
  "controlType": "toggle",
  "value": false,
  "filters": [
    {
      "source": { "kind": "table", "elementId": "users-table" },
      "columnId": "col-is-active"
    }
  ]
}
```

## `dropdown` / `radio` — NOT accepted; use `list + selectionMode: single`

**Verified 2026-07-02:** POSTing `controlType: "dropdown"` or
`controlType: "radio"` returns `Invalid kind: "control"`. No harvested
or exemplar workbook contains either — the API rejects them.

Use `list` with `selectionMode: "single"` instead — the widget will
render as a single-select dropdown by default:

```json
{
  "kind": "control",
  "id": "ctrl-region",
  "controlId": "RegionFilter",
  "name": "Store region",
  "controlType": "list",
  "mode": "include",
  "selectionMode": "single",
  "values": [],
  "source": {
    "kind": "source",
    "source": { "kind": "table", "elementId": "sales-table" },
    "columnId": "col-region"
  },
  "filters": [
    { "source": { "kind": "table", "elementId": "sales-table" },
      "columnId": "col-region" }
  ]
}
```

If a future API version restores `dropdown` / `radio` as first-class
controlTypes, this doc should be updated with a verified example.
Until then, don't ship them — the POST will fail with a generic error
that gives no hint about the controlType being the problem.

## `segmented` — pill-button single-select

Two `source` variants, both verified 2026-07-02 against harvested
workbooks. **Do not mix them** — the earlier docs' `[{label, value}]`
object-array form is not the accepted shape.

### Variant A — manual values (inline)

Use when the choices are a fixed enum with no backing column
(e.g., date grain: year/quarter/month/week/day).

```json
{
  "kind": "control",
  "id": "ctrl-date-part",
  "controlId": "date-part",
  "controlType": "segmented",
  "source": {
    "kind": "manual",
    "valueType": "text",
    "values": ["year", "quarter", "month", "week", "day"],
    "labels": ["Year", "Quarter", "Month", "Week", "Day"]
  },
  "value": "month"
}
```

- `source.kind`: **must be `"manual"`**.
- `source.valueType`: `"text"` (observed); other primitives likely
  accepted — check the OpenAPI.
- `source.values`: **array of primitive strings**, not `[{label, value}]`
  objects.
- `source.labels`: optional **parallel** array of display strings.
  When omitted, `values` are shown directly.
- `value`: initial selected value (or `null`).

### Variant B — sourced from a column

Use when the pills should reflect a column's distinct values.

```json
{
  "kind": "control",
  "id": "ctrl-product-segment",
  "controlId": "Product-Segment",
  "name": "Product Segment",
  "controlType": "segmented",
  "showClearLabel": true,
  "filters": [
    { "source": { "kind": "table", "elementId": "sales-table" },
      "columnId": "col-product-type" }
  ],
  "source": {
    "kind": "source",
    "source": { "kind": "table", "elementId": "sales-table" },
    "columnId": "col-product-type"
  },
  "value": null
}
```

- `source.kind`: `"source"`.
- Nested `source.source`: the source-table reference.
- `filters`: same shape as `list` — parallel to `source`.

### Common fields

- `showClearLabel`: boolean. When `true`, adds a "Clear" pill.
- `value`: initial selection (or `null`).
- Omit `name` if you don't want a visible label above the pills
  (both harvested variants do this).

`scripts/workbook-manifest.py` recognizes both `manual` and `source`
kinds on segmented.

---

## One control, multiple elements

A control's `filters` array can hold **multiple bindings** — one per
element/column the control should filter. This is the right tool for
a page-level filter that applies to several tables or charts at once.
Don't make a separate control per element.

```json
{
  "kind": "control",
  "id": "ctrl-region",
  "controlId": "RegionFilter",
  "name": "Store region",
  "controlType": "list",
  "mode": "include",
  "selectionMode": "multiple",
  "values": [],
  "source": {
    "kind": "source",
    "source": { "kind": "table", "elementId": "sales-table" },
    "columnId": "col-region"
  },
  "filters": [
    { "source": { "kind": "table", "elementId": "sales-table" }, "columnId": "col-region" },
    { "source": { "kind": "table", "elementId": "returns-table" }, "columnId": "col-region" },
    { "source": { "kind": "table", "elementId": "sales-by-region" }, "columnId": "col-region" }
  ]
}
```

Each binding names the target element by `elementId` and the column
on that element to filter by `columnId`. The column IDs do **not**
need to match across elements; they just need to exist on each target.

## One element, multiple controls

The dual pattern — a parent table that several controls filter, with
downstream elements (KPIs, charts, secondary tables) sourcing from
the parent. **Filter once at the parent — every element that sources
it inherits the filter automatically.**

Multiple controls on the same target compose with **AND** — selecting
region "West" + date "Q1" narrows to the intersection. Prefer this
over binding each control to every downstream element; it's less
repetitive and keeps the filter chain in one place.

## Control/column ID collision (CRITICAL)

A control's `controlId` MUST NOT match any column `name` or `id` on
the elements it filters. When names collide, Sigma's resolver
shadows the column with the control: `[Date]` resolves to the
control's selection (a scalar), not the column.

Full rule + worked example in `reference/conventions.md` →
"Control/column ID collision."

`scripts/validate-spec.py`'s `controlid-collision` check catches
this pre-POST.

## Where control bindings apply

Controls parametrize **filter values** on their target elements —
nothing else. They cannot bind to structural fields like `rowCount`,
`rankingFunction`, aggregation choice, or chart mappings. A spec
like `rowCount: "[TopN]"` will be rejected; the field takes a number
literal only. To vary a top-N cap interactively you currently need
to duplicate the element per cap.

## Inherited-from-data-model controls

When a `data-model` source defines controls (e.g., a parameter
control on the DM), those can appear on the workbook through the
DM-sourced element. The shape on the workbook side is the same as
any other control; the inheritance is in the DM, not in the
workbook spec.

Inspect a DM's controls via `GET /v2/dataModels/{dm-id}/spec` and look
at the `controls` array (opportunistically `mcp-describe.sh datamodel
<dm-id>`, expect exit 3).

---

## Additional controlType variants

The following `controlType` values are verified in production
workbooks (harvested 2026-07-02 from `element-showcase`) but need
their exact field sets pulled from the OpenAPI before authoring —
each has its own schema entry:

```bash
jq -r '.components.schemas | keys[] | select(test("Control$"))' /tmp/sigma-api.json
```

### `hierarchy`

Hierarchical single-select or drill-through filter over a nested
dimension (e.g., Region → State → City). Uses `filters[]` + `source`
like `list`; verify the extra fields (drill path, initial level) via
the OpenAPI. Observed shape:

```json
{
  "kind": "control",
  "id": "ctrl-hierarchy",
  "controlId": "StoreHierarchy",
  "name": "Store hierarchy",
  "controlType": "hierarchy",
  "mode": "include",
  "source": {
    "source": { "kind": "table", "elementId": "sales-table" },
    "columnId": "col-region"
  },
  "filters": [
    { "source": { "kind": "table", "elementId": "sales-table" }, "columnId": "col-region" }
  ],
  "values": []
}
```

Note: the `source` object here does NOT carry an outer `kind` field
(unlike `list`'s `kind: "source"`). Observed but unverified whether
that's a variant or an omission that round-trips.

### `switch`

Boolean switch — visually distinct from `toggle` / `checkbox` but
same semantics. Inspect the OpenAPI to see if it needs extra fields.

### `date`

Single-date picker (as opposed to `date-range`). Filters a date
column to a single day. Pulls the same `filters[]` binding as
`date-range`.

### `number`

Single-number **filter** — filters a numeric column on a target element
by a comparison operator. Not a general-purpose scalar parameter (for
that, see "Numeric parameter control referenced from formulas" below).

```json
{
  "kind": "control",
  "id": "ctrl-price",
  "controlId": "Price-Filter",
  "name": "Price Filter",
  "controlType": "number",
  "mode": "=",
  "includeNulls": "when-no-value-is-selected",
  "filters": [
    { "source": { "kind": "table", "elementId": "sales-table" },
      "columnId": "col-price" }
  ]
}
```

- `mode`: `"="` (observed). Likely also `">"`, `"<"`, `">="`, `"<="`, `"!="`.
- `filters` is **required** — this is a filter control, not a bare scalar.

Verified 2026-07-02 against `element-showcase` harvest.

**Do NOT** attempt to author `controlType: "number"` without a
`filters[]` binding — POST rejects with generic `Invalid kind: "control"`
that gives no hint about the missing field. If you need a scalar
parameter unbound from any specific column (for use in formulas), use
the pattern in the next section instead.

## Numeric parameter control referenced from formulas

**Use case:** a "target margin" or "threshold" or "top-N cap" that the
user sets via the UI and every formula reads via `[<controlId>]` bare-ref.

The right shape is `segmented` with a manual value list and
`valueType: "number"`. No `filters[]` binding — the control has no
target element; its value is instead pulled by formulas anywhere on the
page.

```json
{
  "kind": "control",
  "id": "ctrl-target",
  "controlId": "SalesPerUnitTarget",
  "name": "Target Sales per Unit ($)",
  "controlType": "segmented",
  "source": {
    "kind": "manual",
    "valueType": "number",
    "values": [10, 25, 50, 100],
    "labels": ["$10", "$25", "$50", "$100"]
  },
  "value": 25
}
```

Then reference from any formula via the `controlId` (bare, no prefix):

```json
{ "id": "col-target-band",
  "name": "Target Band",
  "formula": "If([Sales per Unit] >= [SalesPerUnitTarget], \"Over target\", \"Under target\")" }
```

Feed `[col-target-band]` into a chart's `color.by: "category"` channel
to get direct color-coding-by-threshold — the color updates live as the
user changes the segmented pill.

**Why segmented over `number-range` or `slider` for parameter use:**
- No `filters[]` binding needed — cleaner semantics for a parameter.
- Discrete values keep the UI unambiguous.
- Adding `labels` lets you format the pill text ($10) separately from
  the value the formula sees (10).

**controlId collision reminder** — `[SalesPerUnitTarget]` bare-ref only
resolves to the control if no column on the referencing element has
`name` or `id` equal to `"SalesPerUnitTarget"`. See "Control/column ID
collision" above.

Verified 2026-07-02 against `Product-and-Basket-Performance` build.

## Element-level filters — `top-n`

Not a `controlType`, but worth listing here because it's a filter
kind you may encounter or need to author. Lives **inside** an
element's `filters[]` array, not as its own control:

```json
"filters": [
  {
    "id": "top10-states",
    "columnId": "col-revenue",
    "kind": "top-n",
    "rankingFunction": "rank",
    "mode": "top-n",
    "rowCount": 10,
    "includeNulls": "when-no-value-is-selected"
  }
]
```

See [`charts.md`](charts.md) → "Element-level filters (top-N, etc.)"
for placement and interaction with a `columnId` field on the parent
element.
