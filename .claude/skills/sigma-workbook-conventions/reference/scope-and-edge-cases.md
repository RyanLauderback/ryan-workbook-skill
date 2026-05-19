# Scope and edge cases

What the workbooks-as-code feature does NOT represent, the misleading errors and 500s you may hit, the rules for verifying spec correctness, the `format` field shape, fallback rituals, and a pointer to the incident history. Load when something fails unexpectedly or before relying on a feature you have not round-tripped before.

## Table of contents

- [Scope of the code representation](#scope-of-the-code-representation)
- [Endpoints](#endpoints)
- [Verify data-model columns resolve before relying on them](#verify-data-model-columns-resolve-before-relying-on-them)
- [Falling back to `warehouse-table` source](#falling-back-to-warehouse-table-source)
- [Verifying correctness via generated SQL](#verifying-correctness-via-generated-sql)
- [Column `format` field](#column-format-field)
- [Schema-drift fallback ritual (adopted from twells89/sigma-skills)](#schema-drift-fallback-ritual-adopted-from-twells89sigma-skills)
- [Persist spec to `/tmp` after CREATE (adopted from twells89/sigma-skills)](#persist-spec-to-tmp-after-create-adopted-from-twells89sigma-skills)
- [History reference](#history-reference)

---

## Scope of the code representation

The workbooks-as-code feature is **not a fully scoped definition of a Sigma
workbook**. Some element properties that are configurable in the UI are not
addressable in the spec, and a GET-back of a UI-configured workbook will not
necessarily round-trip every visual setting. Known examples (treat as
limitations, not bugs to fix):

- **KPI period-comparison configuration** (e.g. "vs prior month" vs "vs prior
  quarter"): the spec only carries the date-dimension column on the KPI's
  `columns` array. The actual comparison period Sigma renders from that
  column is UI-side state and isn't surfaced in the GET response. If a user
  needs a specific comparison period, configure it in the UI; don't try to
  set it in the spec. **Narrowed 2026-05-19:** KPI title color, font size,
  weight, and the element frame (border) ARE spec-able via the styled-name
  object and the `style` field — see
  `reference/element-shapes.md` → "Element-level styling fields." Only the
  comparison-period and sparkline-toggle remain UI-only on KPIs.
- **Chart series colors** (bar fill, line stroke, donut slice palette,
  scatter point colors): not spec-able per-chart. Series colors come from
  the workbook theme's Categorical/Sequential/Diverging color palettes,
  configured in Administration → Branding Settings → Workbook Themes and
  applied via Workbook Settings → Theme. The chart's spec `color` field
  controls *which column drives the breakout* (categorical or scale), not
  the actual color values. To rebrand chart colors, edit the workbook
  theme; to change per-chart series colors, that's UI-only as well (Format
  panel on each chart).
- **Pivot-table cell-color conditional formatting (heatmap visual)**: the
  pivot structure (`rowsBy`, `columnsBy`, `values`) goes through the
  spec, but cell-color conditional formatting that produces the "heatmap"
  look is UI-only AND **also breaks the GET-spec endpoint** on any
  workbook where it's present — see "GET-spec can 500 when UI features
  aren't representable" below. Configure cell-color formatting last,
  after you've finished any spec round-tripping.
- **Chart axis label rotation**: Sigma auto-rotates labels that would overlap;
  no spec override. For bar charts with categorical x-axis, use
  `orientation: "horizontal"` (see below). For time-series, widen the chart.
- (Add new findings here when you discover other UI-only properties.)

The practical implication for the iteration loop: when a user UI-fix changes
something visible but the diff against the prior spec is empty, that property
lives outside the code representation. Note it here and move on — don't burn
iterations searching for a field that doesn't exist.

## Endpoints

| Method | Path | Notes |
|--------|------|-------|
| `POST` | `/v2/workbooks/spec` | Create. Body is JSON or YAML. Required: `name`, `schemaVersion: 1`, `folderId`, `pages`. Optional: `layout`. POST defaults to YAML response — pass `Accept: application/json` for JSON. |
| `GET`  | `/v2/workbooks/{workbookId}/spec` | **Defaults to YAML.** Pass `Accept: application/json` for JSON. |
| `PUT`  | `/v2/workbooks/{workbookId}/spec` | Full-spec update; no partials. |
| `DELETE` | _unknown_ | **Open issue:** both `DELETE /v2/workbooks/{id}` and `DELETE /v2/files/{id}` return 404 against staging for workbooks the same token just CREATEd. Until the right endpoint is found, test workbooks accumulate and need manual UI cleanup. Discover via Sigma docs / network tab on a UI delete. |

`folderId` is the **internal UUID** (e.g. `eb548e3b-...`), NOT the urlId
(`7a3Q0z79Bx1H42pxjd0qWn`). Look up via `GET /v2/files/{urlId}` — both are returned.


## Verify data-model columns resolve before relying on them

A column listed under `elements[].columns` in `GET /v2/dataModels/{id}/spec`
is **not guaranteed to be queryable** from a workbook spec. We've observed
columns that appear in the spec JSON (with a normal-looking
`formula: "[<warehouse-source>/<col>]"`) but fail formula resolution at
POST time:

```
dependency not found: formula reference
'plugs transaction details - relationships/cust key'
```

This happened with `Cust Key`, `Customer Name`, and `Cust Json` on the
`Plugs Transaction Details - Relationships` join element — other columns
on the same element (Date, Quantity, Store Region, etc.) resolved
normally. Hypothesis: the data-model element has stale or orphaned
column definitions whose underlying warehouse source doesn't actually
expose them, and the data-model spec serialization includes them anyway.

**Probe pattern.** When pulling unfamiliar or recently-added columns,
POST a one-table workbook with just those columns first as a smoke test:

```json
{
  "name": "PROBE",
  "schemaVersion": 1,
  "folderId": "<uuid>",
  "pages": [{
    "id": "p1", "name": "p1",
    "elements": [{
      "id": "tbl", "kind": "table", "name": "T",
      "source": { "kind": "data-model", "dataModelId": "...", "elementId": "..." },
      "columns": [
        { "id": "c1", "name": "Cust Key", "formula": "[<Element Name>/Cust Key]" }
      ]
    }]
  }]
}
```

400 → the column is unusable from this element. Pivot to warehouse-source
(see below) or pick a different join key. 200 → safe to build on.

## Falling back to `warehouse-table` source

When a data-model element has unusable columns you actually need, source
the workbook table directly from the underlying warehouse table. Pull
the connection ID and path from the data-model element's
`source.primarySource` (for join elements) or `source` (for
warehouse-table elements):

```json
{
  "id": "tbl-plugs-tx",
  "kind": "table",
  "name": "Plugs Transaction Details",
  "source": {
    "kind": "warehouse-table",
    "connectionId": "1653d1af-46f3-4bcf-a754-6fefc004332f",
    "path": ["RETAIL", "PLUGS_ELECTRONICS", "PLUGS_ELECTRONICS_HANDS_ON_LAB_DATA"]
  },
  "columns": [
    { "id": "col-cust-key", "name": "Cust Key",
      "formula": "[PLUGS_ELECTRONICS_HANDS_ON_LAB_DATA/Cust Key]" }
    /* ... */
  ]
}
```

**Tradeoffs of warehouse-source vs data-model-source:**

| Capability | `data-model` | `warehouse-table` |
|---|---|---|
| `[Metrics/<Name>]` formulas | ✅ | ❌ — replace with inline `Sum(...)` etc. |
| Carries data-model column-level security/formatting | ✅ | ❌ |
| Works around orphaned columns on a data-model element | ❌ | ✅ |
| Survives data-model schema renames upstream | ✅ (Sigma re-resolves) | ❌ (warehouse path is brittle) |

Prefer data-model source by default; reach for warehouse-source only when
you've confirmed a needed column doesn't resolve via the data-model
element. When you do, replace each `[Metrics/X]` reference with the
equivalent inline aggregation (e.g. `Sum([Quantity] * [Price])` for
Revenue, `Sum([Quantity] * [Cost])` for COGS).


## Verifying correctness via generated SQL

The spec's `POST` and `PUT` will succeed (HTTP 200) for specs whose
formulas have *semantic* bugs that the API can't catch. A common case:
referencing a non-aggregated sibling column that you intended to be
aggregated. The lookup compiles to a `LEFT JOIN` against per-row data
instead of a per-group aggregate, downstream calcs silently go NULL,
and the workbook renders empty cells.

To catch this without opening the UI, query the SQL Sigma generated
for each element:

```bash
curl -H "Authorization: Bearer $TOKEN" \
  "$SIGMA_BASE_URL/v2/workbooks/<id>/elements/<element-id>/query" \
  | jq -r '.sql'
```

What to look for, in order of importance:

1. **Expected `GROUP BY`** on aggregating elements. If you wrote
   `Rollup(Min(...), [key], [target/key])` and the SQL has no
   `group by` in the joined subquery, the Rollup didn't compile as an
   aggregation — likely the target reference is wrong or the local
   element is single-tier off `warehouse-table`.
2. **No `iff(equal_null(min, max), max, null)` patterns** unless you
   genuinely want Lookup semantics. That pattern is Sigma's defensive
   NULL-return for ambiguous Lookups (multiple matches with different
   values) — a sign your "aggregation" is silently returning NULL.
3. **Expected expressions in select clause** match what your formulas
   describe (`Q1.QUANTITY * Q1.PRICE`, `date_trunc(month, ...)`, etc.).
   If a calc is missing from select, the formula was likely dropped
   silently — happens when an aggregate function is used in a context
   Sigma doesn't recognize as aggregatable.

Run this check after any spec POST/PUT that involves windowed
aggregation, cross-element joins, or derived calculations. It's the
fastest way to validate the math without sampling cell values in the
UI.


## Column `format` field

Sigma columns accept a `format` object that controls display formatting in the rendered workbook. **Past versions of this skill warned to omit `format` entirely at POST**; that warning was based on observing a 400 error when the object was missing its `kind` field. Verified 2026-05-18: `format` IS spec-able when shaped correctly (`reference/history.md` → 2026-05-18 format-field discovery).

### Verified shape

```json
{
  "format": {
    "kind": "number",
    "formatString": "$,.2f"
  }
}
```

- `kind`: format category. **Verified values: `"number"`.** Other kinds (e.g., `"date"`, `"percent"`, `"text"`) almost certainly exist — discover via UI-toggle + GET-back diff.
- `formatString`: D3/Python-style format spec for `kind: "number"`. Verified shapes:
  - `"$,.2f"` — currency with thousands separator, 2 decimals → `$1,234.56`
  - `"$.2~S"` — currency with D3 SI prefix, 2 significant digits → `$1.2M`,
    `$8.4K`. Verified 2026-05-19 on the reference exemplar
    (`reference/history.md` → "2026-05-19 — Styled-name + style.borderColor
    discovered"). The `~S` suffix is D3's SI-prefix mode (engineering
    notation with K/M/G/T suffixes); the `~` strips trailing insignificant
    zeros.
  - `"0.0%"` — percent with 1 decimal (untested; verify via UI roundtrip)
  - `",d"` — integer with thousands separator (untested)

### Richer format-object fields

The reference exemplar carries additional sibling fields on currency
columns that aren't strictly required (Sigma falls back to locale defaults
without them) but DO round-trip cleanly when present:

```json
{
  "format": {
    "kind":                "number",
    "formatString":        "$.2~S",
    "decimalSymbol":       ".",
    "digitGroupingSymbol": ",",
    "digitGroupingSize":   [3],
    "currencySymbol":      "$"
  }
}
```

- `decimalSymbol` — character for the decimal point (`"."` for US/UK,
  `","` for many European locales).
- `digitGroupingSymbol` — character between digit groups (`","` for US/UK).
- `digitGroupingSize` — array; first entry is the size of digit groups
  (`[3]` for thousands). Multi-entry forms (e.g. `[3, 2]` for the
  Indian numbering system) are untested.
- `currencySymbol` — currency glyph prefix (`"$"`, `"€"`, `"£"`).

These fields are mostly redundant when the `formatString` already encodes
the locale conventions, but include them when you want explicit control or
when round-tripping a UI-configured format.

### Discovering new format shapes

1. Configure the desired format in the UI (column → properties → format).
2. `scripts/api/publish-workbook.sh get-spec <workbookId>` for the GET-back.
3. Diff the column's `format` field against the previous spec.
4. Document the verified shape here.

Note: `validate-spec.py`'s `column-format-shape` check flags `format` only when the required `kind` field is missing (updated 2026-05-19 per Phase 9).

## Control/column ID collision

**Rule summary** (full version in `SKILL.md` → "Load-bearing rules" → rule #4): a control's `controlId` must not match any column `name` or `id` on the elements it filters.

**The failure mode:** Sigma's formula resolver, when it sees a bare reference like `[Date]`, resolves to a workbook **control** of that name before falling back to columns. So a control declared with `controlId: "Date"` shadows the `Date` column on its filtered element. Downstream formulas — `Month([Date])`, `Year([Date])`, `DateTrunc("month", [Date])` — silently coerce to operate on the control's current selection value (a date range scalar), not the column. Render-time symptoms include: wrong axis values, "expected DateTime, got string" errors at chart load, or KPIs that show the filter selection back as a value.

**Verified 2026-05-19** during the cold-start sales-performance test session: `controlId: "Date"` shadowed the `Date` column in the PLUGS data model; the v3 spec's KPI calculations and time-series breakouts errored at render until the control was renamed to `DateRange` and column references were fully-qualified (`[Transactions Detail/Date]`).

**Prevention checklist:**

- Prefix every controlId distinctively: `DateRange`, `StoreFilter`, `PlanTypeCtrl`, `SegmentSelect`.
- Never name a control after the column it filters. The control is the *interaction*, not the *data*.
- When in doubt, fully qualify column references in formulas: `[<ElementName>/Date]` instead of bare `[Date]`. This bypasses control-shadowing entirely.
- `validate-spec.py`'s `controlid-collision` check catches this pre-POST (added 2026-05-19, Phase 9). The check inspects each control's `filters[].source.elementId` and compares its `controlId` against every column `name`/`id` on the target element.

## Drill-passthrough coverage on viz elements

**Rule summary** (full version in `SKILL.md` → "Load-bearing rules" → rule #1 and `reference/layout-and-cross-element.md` → "Drill-down corollary"): every chart/pivot sourced from a workbook table carries the source table's substantive passthrough column set.

**The failure mode** observed 2026-05-19: when an agent over-corrects from a phantom-series learning (where a `Lookup()`-derived column caused an unwanted chart series), it generalizes "strip the offending column from the chart" into a blanket "strip ALL passthroughs from ALL charts." Resulting specs have charts with only `xAxis` and `yAxis` columns (2 cols total). Sigma accepts the spec; the workbook renders; right-click drill-down has nothing to expose.

**Calibration** (verified against 7 canonical exemplars):

- Smallest legitimate chart: ~7 cols (scatter on `data-model-sourced-multi-element-catalog.json`).
- Smallest legitimate pivot: 3 cols (`data-model-sourced-cohort-pivot.json`).
- The collapse signature: chart with ≤2 cols sourced from a table with ≥5 cols.

**The Lookup-strip exception is narrowly scoped:** strip ONLY the specific Lookup column that produces the phantom series, ONLY from the specific viz where it does. The exception NEVER generalizes:

- It does NOT apply to base data-model columns.
- It does NOT apply to other vizs on the same page (the same Lookup col may be legitimate elsewhere).
- It does NOT justify removing all passthroughs.

`validate-spec.py`'s `passthrough-coverage` check (added 2026-05-19, Phase 9) catches the collapse signature pre-POST. Calibrated to FAIL on chart-kind elements with ≤2 cols sourced from tables with ≥5 cols; WARN on thin-but-not-collapsed cases; KPIs intentionally excluded (col count is too variable).

## Metric resolution semantics

**Rule summary** (full version in `SKILL.md` → "Load-bearing rules" → rule #2): `[Metrics/<Name>]` references are addressable from any element sourcing the data model that defines the metric.

**The DM-switch trap** observed 2026-05-19: when a user changes data models mid-session (e.g. "actually use this other data model instead"), the agent will sometimes carry metric references from the prior plan into the new spec. The prior DM's metrics catalog is irrelevant to the new spec. The hard rule:

> On any data-model switch, re-run `mcp-describe.sh datamodel-element <new-dm> <new-el>` and re-derive EVERY `[Metrics/<X>]` reference from the new recon. Treat the prior plan as discarded for metric purposes.

**Slash-in-name caveat:** metric names containing `/` (e.g. `Cost/Member/Month`) are not safely addressable as `[Metrics/Cost/Member/Month]` — the `/` is the namespace delimiter and parsing of multi-slash names is undefined. Options when you encounter such a metric:

1. Rename the metric in the data model (preferred — fixes for all consumers).
2. Fall back to a hand-derived formula (`Sum([CostMember]) / Count([Month])` or equivalent based on the metric's actual formula visible in `mcp-describe` output).

**Round-trip is not validation:** a spec that POSTs and GETs back successfully with `[Metrics/A/B]` is not evidence the reference resolves at render. POST preserves the string; GET returns the string. Render is where the resolution happens. Always visually verify post-POST.

## Notes-promotion guardrail

The iteration-playbook's "promote on 2nd recurrence" rule moves recurring fixes from `workbooks/<name>/notes.md` into skill chunks. The 2026-05-19 test session surfaced a failure mode where a refuted claim was nevertheless written to `notes.md` and could plausibly have been auto-promoted:

> *"`[Metrics/Cost/Member/Month]` accepted at PUT and round-tripped through GET — formula-namespace parser treats everything after the first `/` as the literal metric name."*

The claim was refuted in the same session minutes later when the agent observed that round-trip preserves strings without validating render. The note remained in `workbooks/claims-cost-analysis/notes.md`.

**Guardrail rule:** before promoting any notes.md observation into a skill chunk, audit the entire iteration log for that workbook (and the current session transcript when available) for a refutation or correction of the claim. If the claim was at any point reversed, do NOT promote — instead, add a `~~strikethrough~~` of the original claim with a one-line refutation note. The skill is built from VERIFIED learnings; notes.md is a working scratchpad and can contain in-flight wrong hypotheses.

## Schema-drift fallback ritual (adopted from twells89/sigma-skills)

When a POST/PUT fails with an error suggesting schema mismatch (e.g., "unknown field", "unexpected type", "field not in schema"), this skill's documented shapes may have drifted from the live Sigma API. Apply this bounded fallback exactly once per session:

1. Surface a templated user-facing warning: *"API returned a schema-mismatch error. The skill may be stale. Checking live API..."*
2. Fetch the live OpenAPI spec via `mcp__claude_ai_Sigma_Docs__get-endpoint` for the failing endpoint.
3. Diff the fields the skill documents vs. what the live API expects.
4. Retry the call ONCE with the corrected shape.
5. **Stop after one retry.** If it still fails, surface the diff to the user and let them resolve. Do not loop.

Why bounded: looping silently retries against an unknown failure surface; one retry+stop preserves the iteration-as-evidence audit trail.

## Persist spec to `/tmp` after CREATE (adopted from twells89/sigma-skills)

After a successful POST to `/v2/workbooks/spec`, also save the response body to `/tmp/workbook-spec-<workbookId>.json`. Provides cross-session continuity: the next session can diff or re-PUT this spec without re-running the build. The wrapper-script equivalent of this is already done via `workbooks/<name>/spec.json`; the `/tmp` path is useful as a session-wide cache when you may not yet have a workbook folder.

---

## History reference

Dated incident notes (per-page layout discarded, cohort groupings shape, DivideSafe hallucination, format-field discovery, etc.) live in `reference/history.md`. Inline rules in these chunks carry the rule as evergreen guidance; the history file carries the **when** and the incident that surfaced it.
