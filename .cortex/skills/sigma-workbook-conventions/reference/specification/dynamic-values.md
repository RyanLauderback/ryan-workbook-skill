# Dynamic value binding

New 2026-08-03 (Wave 2 / C4). The author's error here is never "I
didn't know values could be dynamic" — it's "I used the wrong form in
this slot," and no field name tells you which. This file is a **slot →
accepted-form matrix**, not a tutorial on any one form. Consumed by
`actions.md` (effect fields), `pages.md` (modal header title), `agents.md`
(agent instructions + tool `agent-input`), and any dynamic-text build
(`text.md`).

Two independent mechanisms exist. Don't conflate them:

1. **Structured dynamic-value objects** — `{type: ..., ...}`, used in
   effect fields (`set-control-value.value`, `insert-rows.values[col]`,
   `delete-rows.whichRows`).
2. **`{{formula}}` string interpolation** — embedded inside a plain
   string field (modal header `title`, `text` element `body`, image
   `source.url`, agent `instructions`).

They are not interchangeable: an effect field expecting a structured
object rejects a `{{...}}` string, and a string field doesn't parse a
structured object.

## Structured dynamic-value objects — the 5 forms

| `type` | Shape | Verification | Used in |
|---|---|---|---|
| `constant` | `{type:"constant", value:{type:"text"\|"number"\|..., value:<literal>}}` | **Live-POST verified** (Wave 2 / C3 probe, `189db290-7674-4032-9ff7-7fad59dc14fa`) | `insert-rows.values[col]` |
| `formula` | `{type:"formula", formula:"<expr>"}` | **Live-POST verified** (same probe) | `delete-rows.whichRows`; plausible anywhere else a computed value is needed (unconfirmed beyond `whichRows`) |
| `column` | `{type:"column", column:"<columnId>"}` | **Live-POST verified**, via a real build (`fe0140e9-...`) — reads a column's value from the element that triggered the action (e.g. the clicked map region) | `set-control-value.value` |
| `control` | `{type:"control", control:"<controlId>"}` | **Live-POST verified** (Wave 2 / C3 probe, second round) — reads a control's current value | `insert-rows.values[col]`; also documented (harvest evidence only) as usable in `set-control-value.value` |
| `agent-input` | `{type:"agent-input", inputName:"<name>"}` | **Live-POST verified** (Wave 3 / C5+C6 probe, `b7fead6d-504e-48e7-b623-e41576ce8eb5`) — used in an agent tool's `insert-rows.values`, round-tripped byte-for-byte. The model supplies the value at call time, based on `inputName` and the tool's `description`. |

All five forms share the outer `{type: ...}` discriminator. Effect
fields document *which* forms they accept in `actions.md`; when in
doubt, `constant`/`formula`/`column`/`control` are all safe to assume
available in `insert-rows.values` and `set-control-value.value` — treat
`agent-input` as scoped to agent tool steps only until proven otherwise.

## `{{formula}}` string interpolation

Embeds a live Sigma formula result inside an otherwise-static string
field. **Live-POST verified** (Wave 2 / C3 probe): a modal page's
`modal.header.title` set to `"Filter is: {{[c-filter]}}"` — a bare
`[controlId]` reference inside the interpolation braces — round-tripped
byte-for-byte.

```json
{ "title": "Filter is: {{[c-filter]}}" }
```

Confirmed slots for `{{formula}}`, by evidence tier:

| Slot | Verification |
|---|---|
| `modal.header.title` | **Live-POST verified** (this skill's own C3 probe) |
| `image.source.url` | GET-spec/harvest evidence (a real production workbook selects between several image URLs via `{{If(...)}}`) — not yet independently POSTed by this skill |
| `text` element `body` | Documented elsewhere in this skill (`text.md`) as an established, pre-Wave-2 pattern with a d3-format-suffix convention |
| `agents[].instructions` | **Live-POST verified** (Wave 3 / C5+C6 probe) — a bare `{{[controlId]}}` reference round-tripped byte-for-byte, same mechanism as the modal-header-title probe |

**Bare `[controlId]` references work both inside `{{}}` interpolation
and directly in ordinary formulas** — see `controls.md` → "Numeric
parameter control referenced from formulas" for the already-established
(pre-Wave-2) pattern of referencing a `segmented`/manual-value control
directly as `[<controlId>]` in a column formula, no `{{}}` needed there
since it's already inside a formula context. The `{{}}` wrapper is
specifically for embedding a formula result inside a plain string field
that isn't itself a formula.

## `[<control>].start` / `.end` — date-range control accessors

A `date-range` control's bounds are accessible in formulas as
`[<controlId>].start` and `[<controlId>].end` (e.g.
`Between([Date], [cDate].start, [cDate].end)`). **GET-spec/harvest
evidence only** — observed in production workbooks, not yet
independently POST-verified by this skill. Probe before relying on this
in a build where it's load-bearing.

## What's still unverified

- `{{formula}}` in `image.source.url` — harvest evidence only, not this
  skill's own POST.
- `[<control>].start`/`.end` accessors — harvest evidence only.
- Whether `agent-input` is usable outside agent tool steps (e.g. in a
  button's `set-control-value.value`) — only probed inside
  `insert-rows.values` this wave.
