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

## Slider

A slider is a **`number-range` control**, not a distinct `slider` kind.
There is no separate `controlType: slider` shape — don't use
`value` / `min` / `max` at the top level (they get rejected with a
misleading `Invalid kind: pages[0].elements[N], got "control"` error).

```json
{
  "kind": "control",
  "controlType": "number-range",
  "mode": "between",
  "values": [1, 10]
}
```

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

## `dropdown` / `radio` — UI variants of `list`

```json
{
  "kind": "control",
  "controlType": "dropdown",
  "selectionMode": "single",
  "mode": "include"
}
```

- `dropdown` — typically paired with `selectionMode: single`.
- `radio` — always `selectionMode: single`.

Everything else — `mode`, `values`, `source`, `filters` — matches the
`list` shape.

## `segmented` — pill-button single-select

```json
{
  "kind": "control",
  "id": "ctrl-period",
  "controlId": "DatePart",
  "name": "Period",
  "controlType": "segmented",
  "showClearLabel": true,
  "value": null,
  "source": {
    "kind": "manual",
    "values": [
      { "label": "Day", "value": "day" },
      { "label": "Week", "value": "week" },
      { "label": "Month", "value": "month" }
    ]
  }
}
```

`source.kind: "manual"` is documented for segmented controls — you
specify the values inline rather than sourcing from a column.
`scripts/workbook-manifest.py` recognizes `"manual"` as a known
source kind for segmented controls.

`showClearLabel`: boolean. When true, adds a "Clear" pill to the
segmented widget.

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

Inspect a DM's controls via `mcp-describe.sh datamodel <dm-id>`
and look at the `controls` array on the response.
