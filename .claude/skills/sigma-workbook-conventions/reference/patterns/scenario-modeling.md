# Scenario modeling & forecasting (composition, not a spec surface)

New 2026-08-04 (Wave 4 / C8). **This file is not a `specification/`
chunk on purpose.** Forecasting and what-if scenario modeling are not
a dedicated Sigma element kind or spec field — they're a *composition*
of primitives this skill already documents elsewhere:
`CallVariant`/formula functions (`formulas.md`), parameter controls
(`controls.md`), input tables and writeback (`input-tables.md`,
`actions.md`), and confidence-band line charts (`charts.md`). Filing
this under `specification/` would read as "there is a scenario
feature" — the same hallucination shape as the `DivideSafe` incident.
Every step below cites the primitive chunk that already covers its
underlying mechanism.

## Forecasting — a warehouse UDF call, not a Sigma feature

Sigma has no built-in forecasting function. The pattern is: call a
warehouse machine-learning UDF via `CallVariant` (confirmed 2026-08-04
via Sigma's own function docs to be a real formula function — `CallVariant(functionName,
arg1, arg2, ...)`, "calls a warehouse function that returns a Variant
datatype"; check Sigma's data-platform compatibility matrix before
relying on it), then unpack the result with accessor formulas:

```
CallVariant("SE_DEMO_DB.SNOWPARK_UDF.AUTO_TIMESERIES_MODEL", [Order Count], [Order Date], 12)
```

then, on the resulting `Variant` column (harvest-only naming —
`[Order Prediction]` in the source workbook):

```
Number([Order Prediction].Prediction)
Number([Order Prediction].Lower_CI)
Number([Order Prediction].Upper_CI)
```

**Status: harvest-only (millersigma), not independently probed by this
skill.** `CallVariant` itself is confirmed real; the specific UDF name,
its argument order, and the `.Prediction`/`.Lower_CI`/`.Upper_CI`
accessor field names are not — they depend on a warehouse UDF this
session had no access to test against. Before relying on this pattern
in a real build: confirm a forecasting UDF actually exists on the
target connection (ask the user or check with the data platform team),
and probe the accessor field names against its actual return shape
before assuming `.Prediction`/`.Lower_CI`/`.Upper_CI` are universal —
they're almost certainly UDF-specific, not a Sigma convention.

Draw the result as a line chart with a confidence band: the point
estimate and the two CI bounds as three `yAxis.columnIds` series on
one chart, following the ordinary multi-series line-chart shape
already documented in `charts.md` (live-POST verified there) — nothing
forecast-specific about the chart itself.

## What-if — parameter controls, not input-table filters

A "what-if" control (adjust an assumption, see the dashboard react) is
an ordinary parameter control per `controls.md`'s already-verified
`source.kind: "manual"` pattern (`segmented` or `slider`, a fixed
`values` array, **no `filters[]`**) — read as a bare `[controlId]`
reference directly in a formula, same mechanism as any other control
value (`controls.md` → "Numeric parameter control referenced from
formulas"). Date-range what-if uses the already-documented
`[<controlId>].start`/`.end` accessors (`dynamic-values.md` — harvest-
evidence only, not yet independently POST-verified by this skill
either).

## Structural gotcha #1 — controls cannot usefully filter input tables or pivots

**Partially confirmed 2026-08-04.** Live-POSTed a control with
`filters: [{source: {kind:"table", elementId: "<input-table-id>"},
columnId: "..."}]` targeting a real input-table — **the spec accepts
it outright**: clean POST, byte-for-byte GET-back, no rejection or
server-side stripping at any point. This means the millersigma claim
is **not** a POST-time validation rule (nothing here will stop you
from authoring this), and this skill has **not** independently
confirmed the other half of the claim — that the filter is a silent
functional no-op in the rendered UI — since doing so requires visual
inspection this session has no tool for.

**Practical guidance until visually confirmed either way:** don't rely
on a control filtering an input-table or pivot-table directly. If
scenario rows need to be sliced by a control's value, bind the control
to a **derived normal table** sourced from the input-table instead
(an ordinary `table` element with `source: {kind:"table", elementId:
"<input-table-id>"}`, redeclaring the needed columns per the
passthrough mandate in `conventions.md`), and filter *that* — the
already-verified, unambiguous mechanism (`conventions.md` →
"Passthrough mandate"; `controls.md` → standard `filters[]` usage).

## Structural gotcha #2 — input-table rows cannot be seeded from code

**Confirmed 2026-08-04, at the schema level.** Inspected the live
OpenAPI's full field list for the `input-table` element kind: `id`,
`kind`, `source`, `inputMode`, `name`, `description`, `style`,
`noDataText`, `tableComponents`, `tableStyle`, `columns`,
`conditionalFormats`, `summary`, `sort`, `filters`. **There is no field
for initial/seed row data anywhere in the schema** — the only ways
rows enter an input table are (a) a user typing into it in the UI, or
(b) the `insert-rows` effect (`actions.md`, `input-tables.md`) fired by
a button or agent tool. This structurally confirms the harvest claim,
not just repeats it.

**Practical implication:** an input table that needs to start non-empty
(a default "Base Case" scenario row, for instance) cannot have that row
baked into the spec you POST. Options: (1) a hidden formula column on a
*different*, read-only table computing the default case, which the
scenario UI reads until the user's own row exists and takes over — the
harvest's documented workaround; or (2) fire an `insert-rows` action
once, immediately after the workbook is created (e.g. from a build
script, not the spec itself), to seed the starting row via the real
writeback mechanism rather than trying to author it as static data.

## Worked pipeline shape (harvest-only, millersigma)

A 6-element scenario-modeling pipeline, structure only — not
independently authored or POSTed by this skill:

1. Base table (real data, read-only).
2. Empty `input-table` (`source.kind: "empty"`) — the scenario driver
   grid a user edits.
3. A cross-join pivot joining #1 and #2 so every scenario row applies
   across every dimension value: `columns: [{left: "1", right: "1"}]`
   — a constant-on-both-sides join, i.e. a deliberate cartesian
   product, not a real key relationship. Not independently verified;
   if this shape is load-bearing in a real build, probe it first (see
   `sources.md` → `join` for the already-documented join shape this
   would extend).
4. A `linked` input-table (`input-tables.md` → "linked" — this variant
   IS live-POST verified) driver grid bound to #3.
5. A derived "normal" table recombining #1 and #4 into the shape
   downstream charts/tables actually consume.
6. An app layer — buttons wired to `insert-rows`/`delete-rows`
   (create/submit/approve), all using the already-verified effect
   vocabulary in `actions.md`.

## Cross-references

- `reference/specification/formulas.md` — `CallVariant` and general
  formula function reference.
- `reference/specification/controls.md` — parameter controls,
  `source.kind:"manual"`, bare `[controlId]` formula references.
- `reference/specification/input-tables.md` — `empty`/`linked` source,
  writeback via `insert-rows`/`delete-rows`.
- `reference/specification/charts.md` — multi-series line charts (the
  confidence-band shape is an ordinary 3-series chart).
- `reference/specification/dynamic-values.md` — `[<control>].start`/
  `.end` date-range accessors.
