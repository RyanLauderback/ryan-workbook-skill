# Dynamic value binding

New 2026-08-03 (Wave 2 / C4). The author's error here is never "I
didn't know values could be dynamic" — it's "I used the wrong form in
this slot," and no field name tells you which. This file is a **slot →
accepted-form matrix**, not a tutorial on any one form. Consumed by
`actions.md` (effect fields), `pages.md` (modal header title), `agents.md`
(once it exists), and any dynamic-text build (`text.md`).

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
| `agent-input` | `{type:"agent-input", inputName:"<name>"}` | **GET-spec / harvest evidence only** — observed in production workbooks' `agents[].tools[].steps[]`, not yet independently authored-and-POSTed by this skill. The model supplies the value at call time. Confirm once the agent-surface chunk lands. |

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
| `agents[].instructions` | GET-spec/harvest evidence only — e.g. `{{[pProductName]}}` interpolated into an agent's system prompt |

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

- `agent-input` as a value-binding form — needs the agent surface (C6)
  to exist before it can be probed meaningfully.
- `{{formula}}` in `image.source.url` and `agents[].instructions` —
  harvest evidence only, not this skill's own POST.
- `[<control>].start`/`.end` accessors — harvest evidence only.
