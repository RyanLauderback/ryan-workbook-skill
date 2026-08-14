# Scope and edge cases

What the workbooks-as-code feature does NOT represent, the misleading
errors and 500s observed on this org, and the fallback rituals. Load when
something fails unexpectedly or before relying on a feature you haven't
round-tripped before.

This file is the **ryan-specific edge-case log**. For canonical per-element
shapes see `reference/specification/`; for the validation flow see
`reference/workflows/validate.md`. The schema-drift and persist-spec
rituals previously here have moved to `reference/workflows/crud.md`.

## Table of contents

- [Scope of the code representation](#scope-of-the-code-representation)
- [GET-spec can 500 when UI features aren't representable](#get-spec-500)
- [Map element status](#map-element-status)
- [Falling back to `warehouse-table` source](#falling-back-to-warehouse-table-source)

---

## Scope of the code representation

The workbooks-as-code feature is **not a fully scoped definition of a Sigma
workbook**. Some element properties configurable in the UI are not
addressable in the spec, and a GET-back of a UI-configured workbook will
not necessarily round-trip every visual setting. Known examples (treat as
limitations, not bugs to fix):

- **Retracted 2026-08-07:** this bullet previously claimed KPI
  period-comparison configuration ("vs prior month" vs "vs prior
  quarter") was UI-only state, not representable in the spec. That's
  wrong — `timeline` (a date-dimension column reference) +
  `periodComparison` (e.g. `"month"`) together set the comparison
  period explicitly in the spec, verified ~67 times in a real
  production dashboard. See `reference/specification/kpis.md` →
  "Period-over-period comparison." **Narrowed 2026-05-19:** KPI title
  color, font size, weight, and the element frame (border) are also
  spec-able via the styled-name object and the `style` field — see
  `reference/specification/kpis.md` → "Title styling."

- **Chart series colors** beyond the `color.scheme` palette:
  per-chart-spec `color: {by, column, scheme}` lets you set positional
  palettes (`category` mode) and continuous gradients (`scale` mode) —
  see `reference/specification/charts.md`. But the **fallback / theme
  palette** when `color` is unset comes from Administration → Branding
  Settings → Workbook Themes, applied via Workbook Settings → Theme.
  To rebrand the default chart colors org-wide, edit the workbook theme.

- **Chart axis label rotation:** Sigma auto-rotates labels that would
  overlap; no spec override. For bar charts with categorical x-axis, use
  `orientation: "horizontal"` (see
  `reference/conventions.md` → "Bar-chart orientation"). For time-series,
  widen the chart.

- **Padding / spacing / gap on containers and layouts** — verified
  2026-05-21 against the retail-sales harvest. Design specs mention
  `padding`, `ContainerSpacing`, `gap` but none survive into the JSON or
  layout XML on GET-back. UI-only.

- ~~Modal / popover pages, tabbed containers, buttons, action sequences —
  per Sigma's official workbooks-as-code limitations, these are NOT
  supported in the spec.~~ **Retracted 2026-08-03.** All five are fully
  spec-able — verified via clean GET-spec (HTTP 200) against 5 real
  production workbooks. See `reference/capability-ledger.md` for dated
  evidence and `reference/specification/others.md` → "What about buttons
  and modals?" for the full retraction and the retest protocol that should
  have been applied before this claim was written.

(Add new findings here when you discover other UI-only properties.)

The practical implication for the iteration loop: when a user UI-fix
changes something visible but the diff against the prior spec is empty,
that property lives outside the code representation. Note it here and
move on — don't burn iterations searching for a field that doesn't exist.

## GET-spec 500

The GET-spec endpoint can return HTTP 500 (`code: service_error`) on a
workbook that's otherwise healthy — open-able in the UI, listed in
`/v2/files`, metadata fetchable via `GET /v2/workbooks/{id}`.

**Confirmed trigger:** pivot-table cell-color conditional formatting
(heatmap visual). Reproducible via UI toggle:

| Workbook state | GET-spec |
|---|---|
| Conditional formatting applied | 500 (`service_error`) |
| Conditional formatting removed via UI | 200 |
| Conditional formatting re-applied | 500 |
| Unrelated control workbook | 200 throughout |

> **2026-05-21 update.** The upstream `sigma-workbooks` skill claims
> `conditionalFormats` round-trips cleanly. If true on the current
> platform, the trigger above may be **stale**. The four workbooks the
> user supplied during the 2026-05-21 training session that returned
> `service_error` (Claims Command Center, Sales MBR original + stripped
> twice, Healthcare Aesthetic) likely tripped on different features —
> the Healthcare summary explicitly mentions maps, buttons, modals.
> Retest required before relying on either claim. Stage 7 of the
> migration will probe these workbooks again.

> **Retested 2026-08-13 — confirmed stale for `backgroundScale`.** A
> from-scratch POST of a pivot-table with `backgroundScale` conditional
> formatting, followed immediately by `GET /v2/workbooks/{id}/spec`,
> returned 200 with the format present — no `service_error`. See
> `reference/capability-ledger.md`'s `pivot-table` row for the full
> evidence. The "Confirmed trigger" table above no longer reflects
> current behavior for `backgroundScale` on `pivot-table` on this org —
> treat it as historical, not current guidance, for that specific
> combination. Other conditional-format variants (`single`, `fontScale`,
> `dataBars`) and other element kinds (plain `table`) were not part of
> this retest and remain unconfirmed.

Suspected triggers (untested):

- Buttons / modal pages / tabbed containers (per Sigma's documented
  unsupported list)
- Possibly chart series breakout / color-by combined with conditional
  formatting

Maps used to be on this list but were verified round-trippable
2026-07-02 — see "Map element status" below.

**Cross-workbook scope:** rollback-by-version-param doesn't help.
Verified 2026-05-21 against Sales MBR stripped — all 4 versions
returned `service_error`. Once a workbook trips this failure mode, it
appears to stay tripped across versions.

Diagnostic steps when GET-spec returns 500:

1. **Sanity check** another workbook's GET-spec to rule out a global
   serializer outage. `${CLAUDE_PLUGIN_ROOT}/skills/sigma-workbook-conventions/scripts/api/whoami.sh` exercises this on the
   `/v2/files` listing.
2. **Capture the `incident-id`** from the response body and file a
   Sigma support ticket — this is a server-side bug.
3. **Isolate the trigger via UI undo.** Undo one UI change at a time,
   save, retry GET-spec. If 200, that change is the culprit.
4. **Don't try to repair via PUT** — overwriting with a known-good
   spec would destroy the new UI configuration.

Practical rule: configure suspected-trigger features (pivot cell
heatmaps, maps, buttons) **last**, after any spec round-tripping for
that workbook is done. Once they're applied, GET-spec may be dead for
that workbook until they're removed.

`${CLAUDE_PLUGIN_ROOT}/skills/sigma-workbook-conventions/scripts/api/harvest-workbook.sh` fails fast on `service_error`
responses with a diagnostic message — added 2026-05-21 after four
workbook harvests all tripped this.

## Map element status

**Supported.** Verified 2026-07-02: three map element kinds
(`geography-map`, `point-map`, `region-map`) round-trip cleanly through
POST/GET on this org. Harvest of `Element-Showcase-Dashboard`
(`6DGOTggv4x90Cls7Sq0y0j`) included both a `region-map` (us-state) and
a `point-map` (bubble by margin), both readable back cleanly.

See `reference/specification/maps.md` for the full shape guide,
including the `regionType` enum for `region-map` and the single-vs-
array shape gotcha on binding fields.

Historical note: prior to the 2026-07-02 validation, every
map-bearing workbook observed on this org returned `service_error` on
GET-spec. That's no longer the case — the earlier failures were
against workbooks that combined maps with a different unsupported
feature (likely pivot cell heatmaps or an unsupported control kind).
Author maps freely; only surface a scope caveat if the user's other
requested features overlap the known-failing feature list above.

## Falling back to `warehouse-table` source

When a `data-model`-sourced spec fails at POST and the data-model
element isn't load-bearing for the workbook's analytical question,
fall back to sourcing directly from the underlying warehouse table.

The data model's value is its joins + metrics + column-level security.
If your workbook needs none of those (a single-table dashboard with
hand-derived calcs), `warehouse-table` source is simpler and
sometimes unblocks builds when the DM has issues.

Discovery flow: `${CLAUDE_PLUGIN_ROOT}/skills/sigma-workbook-conventions/scripts/api/lookup-path.sh <conn-id>
"<DB>.<SCHEMA>.<TABLE>"` resolves the inodeId; then
`${CLAUDE_PLUGIN_ROOT}/skills/sigma-workbook-conventions/scripts/api/list-table-columns.sh <inode-id>` lists columns. Switch
the spec's source from `kind: "data-model"` to `kind: "warehouse-
table"` and update all column formulas from `[<DM-element-name>/Col]`
to `[<TABLE>/Col]`.

`${CLAUDE_PLUGIN_ROOT}/skills/sigma-workbook-conventions/scripts/sigma-resolve.py` handles the resolution when the prompt
mixes warehouse paths and folder names. See
`reference/workflows/discover.md`.

## History reference

Dated incident notes (per-page layout discarded, cohort groupings
shape, DivideSafe hallucination, format-field discovery, styled-name
discovery, the 2026-05-21 migration, etc.) live in
`reference/history.md`. Inline rules in this and other chunks are
evergreen; the history file carries **when** each rule was verified
and the incident that surfaced it.
