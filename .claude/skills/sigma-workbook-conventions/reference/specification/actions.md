# Actions & effects (buttons, on-select, the interaction core)

New 2026-08-03 (Wave 2 / C3). Every shape below is **live-POST
verified** — 2 effects (`set-control-value`, `open-overlay`) confirmed
via a real build-mode session's published workbook (the map-click →
modal interaction in `fe0140e9-3798-4a9a-a30b-03af8ddbc8ef`); the
remaining 7 effects plus the `button` element itself confirmed via a
dedicated scratch probe (`189db290-7674-4032-9ff7-7fad59dc14fa`)
authored specifically to exercise each one in isolation. All 9 effects
round-tripped **byte-for-byte** through POST → GET with zero
normalization. (A 10th effect, `update-rows`, was confirmed later via
a real production workbook's agent tool step — not part of this
probe; see the `insert-rows`/`delete-rows`/`update-rows` entry below.)

`others.md` previously declared buttons and action sequences "not
supported" — retracted; see `reference/capability-ledger.md`.

```bash
jq '.components.schemas.Button, .components.schemas.Action, .components.schemas.Effect' /tmp/sigma-api.json
```

## `button` element

```json
{
  "id": "btn-clear",
  "kind": "button",
  "text": "Clear filter",
  "appearance": "outline",
  "actions": [
    {
      "id": "act-clear",
      "trigger": "on-click",
      "effects": [
        { "effect": "clear-control", "scope": { "type": "control", "control": "c-filter" } }
      ]
    }
  ]
}
```

| Field | Required | Notes |
|---|---|---|
| `id` | yes | Unique on the page |
| `kind` | yes | Always `"button"` |
| `text` | yes | Button label |
| `appearance` | no | `"outline"` and `"filled"` both observed round-tripping cleanly |
| `actions` | yes (for the button to do anything) | Array — see below |

Style fields (`fillColor`, `fontColor`, `borderRadius`, `fontWeight`,
`size`, `align`) are observed in harvested production workbooks but not
yet independently re-verified by this skill's own probe — treat as
probably-fine, not confirmed, until spot-checked.

## The `actions` / `effects` shape

Any element can carry `actions: [{id, trigger, effects: [...]}]`. Two
triggers observed: **`on-click`** (buttons) and **`on-select`**
(charts, KPIs, tables, pivots, maps — click a data point/row to fire the
action). Each action has one `trigger` and a list of `effects`, run in
array order.

```json
{
  "id": "<action-id>",
  "trigger": "on-click",
  "effects": [ { "effect": "<effect-name>", ...effect-specific fields } ]
}
```

## The 10 effects

### `set-control-value`

Sets a control's value programmatically. **Live-POST verified** via a
real build's map → modal interaction.

```json
{
  "effect": "set-control-value",
  "control": "c-selected-state",
  "value": { "type": "column", "column": "col-map-state" }
}
```

`control` is a **`controlId`**, not the control element's own `id`.
`value` is a dynamic-value object — see `dynamic-values.md` for the
full set of forms (`column`, `control`, `formula`, `constant`,
`agent-input`). The `column` form above reads the value from a column
on the **same element** that triggered the action (e.g. the clicked
map region's state column).

### `clear-control`

Resets a control to its default/empty state.

```json
{ "effect": "clear-control", "scope": { "type": "control", "control": "c-filter" } }
```

`scope.control` is a `controlId`.

### `open-overlay` / `close-overlay`

Opens/closes a modal page.

```json
{ "effect": "open-overlay", "overlayId": "page-modal" }
```
```json
{ "effect": "close-overlay" }
```

`overlayId` matches a `document.overlays[].id` — **not** an element id,
and (as of 2026-08-10) not a `pages[].id` either. Modals moved out of
`pages[]` entirely into a top-level `overlays` array; see
`reference/specification/pages.md` → "Modal pages" for the current
shape. `close-overlay` takes no other fields; it closes whichever
overlay is currently open, so it's typically placed on a button living
inside the modal itself.

### `navigate`

Switches the active page.

```json
{ "effect": "navigate", "target": { "type": "page", "page": "page-second" } }
```

`target.page` is a page `id`.

### `select-tab`

Switches the active tab on a `tabbed-container`.

```json
{
  "effect": "select-tab",
  "tabbedContainer": "tabs-1",
  "selectedTab": { "type": "tab", "index": 1 }
}
```

`tabbedContainer` is the `kind:"tabbed-container"` element's own `id`.
`selectedTab.index` is **0-based**, matching position in that element's
`tabs[]` array (index `1` = the second tab).

### `open-url`

Opens an external URL.

```json
{ "effect": "open-url", "openTarget": "_blank", "url": "https://help.sigmacomputing.com/" }
```

`openTarget`: `"_blank"` observed (new tab); other standard target
values are plausible but unverified.

### `insert-rows` / `delete-rows` / `update-rows` — input-table writeback

The **only** writeback mechanisms for `input-table` elements (see
`tables.md` → "Input tables"): append-only inserts, explicit deletes,
or a targeted single-row update by primary key.

```json
{
  "effect": "insert-rows",
  "table": "tbl-rows",
  "values": {
    "col-note": { "type": "constant", "value": { "type": "text", "value": "probe row" } }
  }
}
```
```json
{
  "effect": "delete-rows",
  "table": "tbl-rows",
  "whichRows": { "type": "formula", "formula": "[Note] = \"probe row\"" }
}
```
```json
{
  "effect": "update-rows",
  "table": "tbl-rows",
  "whichRows": {
    "type": "single-row",
    "primaryKeys": { "col-id": { "type": "agent-input", "inputName": "rowId" } }
  },
  "values": {
    "col-status": { "type": "constant", "value": { "type": "boolean", "value": false } }
  }
}
```

`table` is the `input-table` element's own `id`. `insert-rows.values`
and `update-rows.values` are keyed by column `id`, each a dynamic-value
object (see `dynamic-values.md`) — do not pass values for system
columns (`ID`, `CREATED_AT`, `CREATED_BY`, `UPDATED_AT`, `UPDATED_BY`),
they're protocol-managed. `delete-rows.whichRows` is a formula
evaluated against each existing row; matching rows are removed.
**`delete-rows` is rejected outright on `linked`-source input tables**
(confirmed 2026-08-11, specific server error) — see `input-tables.md`
→ "Writeback restriction — `linked` sources reject `delete-rows`".
`update-rows.whichRows` uses a **different, non-formula shape**:
`{type:"single-row", primaryKeys:{<columnId>: <dynamic-value>}}` —
keyed by column `id` (not name), identifying the one row to mutate;
only the columns present in `values` are changed on that row. **Live-
confirmed** via a real, currently-live production workbook's agent
tool step (not this skill's own scratch probe) — observed value forms
were `{"type":"agent-input","inputName":"Status"}` and
`{"type":"constant","value":{"type":"boolean","value":false}}`. The
formula's bare `[Note]` in the `delete-rows` example above resolves
against the input-table's own column **names** (`"Note"`, the `name`
on `col-note`) — same bare-ref resolution rules as any other element.

Agent tools (`agents[].tools[].steps[]`) reuse this exact same effect
vocabulary, with one addition: `{type: "agent-input", inputName}` as a
dynamic-value form the model supplies at call time — see
`dynamic-values.md`. **Live-POST verified** (Wave 3 / C5+C6 probe):
each step is shaped exactly like a button's effect object, plus one
added sibling key, `kind:"effect"`. See `agents.md`.

## What's still unverified

- **Referential integrity is enforced by `validate-spec.py` for
  `actions[].effects[]`; also extended to `agents[].tools[].steps[]`
  and `chat.agentId` this wave.** A dangling `overlayId`, `control`,
  `table`, `tabbedContainer`, `navigate.target.page`, or `agentId`
  fails silently at runtime otherwise — POST succeeds, nothing renders
  or fires when clicked. See the `action-refs-resolve` check.
- Whether tool steps support the full 10-effect vocabulary or only the
  writeback trio — only `insert-rows` was independently probed as a
  tool step by this skill's own probe; `update-rows` has separate
  real-world confirmation as a tool step (see above) but `delete-rows`
  as a tool step remains unconfirmed. See `agents.md`.
- Effect `style` fields on buttons beyond `appearance` (see above).
