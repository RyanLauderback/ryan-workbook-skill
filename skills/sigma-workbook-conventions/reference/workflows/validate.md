# Validation

Validation runs in three phases:

1. **Pre-submit** — `${CLAUDE_PLUGIN_ROOT}/skills/sigma-workbook-conventions/scripts/validate-spec.py` catches what's visible
   in the spec text (17 checks; see the note on JSON/YAML input below).
2. **Post-create** — `${CLAUDE_PLUGIN_ROOT}/skills/sigma-workbook-conventions/scripts/api/verify-workbook.sh` catches
   unresolved / circular refs in the compiled SQL;
   `${CLAUDE_PLUGIN_ROOT}/skills/sigma-workbook-conventions/scripts/api/audit-workbook-schema.sh` catches `error`-typed
   columns in the schema. Both run automatically via
   `publish-workbook.sh`.
3. **Visual** — open the workbook URL and confirm it renders.

Both API phases matter. Silent compilation failures are the largest
hidden failure mode.

Load this before any POST or PUT.

## 1. Pre-submit — `${CLAUDE_PLUGIN_ROOT}/skills/sigma-workbook-conventions/scripts/validate-spec.py`

```bash
${CLAUDE_PLUGIN_ROOT}/skills/sigma-workbook-conventions/scripts/validate-spec.py workbooks/<name>/spec.json
```

Accepts `.json` or `.yaml`/`.yml` (YAML needs PyYAML or `yq` on PATH —
added 2026-08-03, ported from upstream's `validate-spec.sh` fallback chain).

**This table was reconciled against the actual `CHECKS` array on 2026-08-03.**
It had drifted badly: 5 rows below described checks that did not exist in
code (`id-uniqueness`, `schema-keys`, `layout-element-ids`,
`metrics-existence`, and `name-required-on-passthrough` — the last one was
implemented, calibrated against 12 canonical examples + 5 live production
workbooks, found to false-positive at massive scale (587 hits on one working
dashboard), and retracted rather than shipped — see the function's docstring
in `validate-spec.py` and `reference/history.md`). 4 implemented checks had
no row at all. The table below is the 14 entries in `CHECKS` from that
reconciliation, plus a 15th (`schema-version`) added the same day after
a live Wave 1 POST probe caught an invalid `schemaVersion` value that
local validation alone couldn't have flagged without this check. A 16th
(`action-refs-resolve`) was added the same wave (Wave 2 / C3) alongside
the action/effect vocabulary itself. A 17th (`channel-exclusivity`) was
added 2026-08-04 after a Wave 3 test session hit the exact channel-reuse
rejection `reference/conventions.md` had documented since 2026-07-02 but
flagged as "planned; not yet implemented" — the second real-session
recurrence of the same failure mode.

| # | Check | What it catches |
|---|---|---|
| 0 | `schema-version` | Top-level `schemaVersion` isn't `1` — the only value every canonical exemplar and every successful POST has used. **WARN**, not fail, since `conventions.md`/`crud.md` already flag this as potentially unstable long-term. Added 2026-08-03 after a live probe POST was rejected with `schemaVersion: Invalid 1: number` on a spec that used `2`. |
| 1 | `no-per-page-layout` | A per-page `pages[i].layout` field — Sigma silently discards it; layout must be the single top-level `layout` string with every `<Page>` as a sibling. |
| 2 | `elements-placed-in-layout` | Every element `id` must appear as an `elementId` on a `<Element>`, `<Container>`, or `<TabbedContainer>` tag. Fails outright if there's no top-level `layout` at all. (`TabbedContainer` added 2026-08-03 — its absence produced a false FAIL on every tabbed-container element; verified against 2 independent production workbooks.) |
| 3 | `containers-have-children` | Every `kind:"container"` element has a matching `<Container>` in the layout XML, **and** that `<Container>` has nested children (not flat siblings). |
| 4 | `layoutelement-has-children` | The forward case of #3: a `<Element>` (a leaf tag) with nested child tags — they parse without error but are silently dropped and never render. Added 2026-08-03, ported from upstream's manual checklist. |
| 5 | `column-format-shape` | `column.format` must be an object carrying `kind` (verified shape: `{kind, formatString}`). The UI-export shape (`{type, format}`) is rejected with a misleading "Missing 'kind' field." |
| 6 | `control-id-unique` | `controlId` must be workbook-wide unique — **except** when one side is `controlType:"synced"`, Sigma's first-class cross-page control-sync stub (a primary control on one page + thin `synced` placeholders on others, deliberately sharing a `controlId`). Only fails when a duplicate exists where *neither* side is `synced`. (Exemption added 2026-08-03 after Bergey's Unified Insights showed the exact mechanism — a `segmented` primary + 4 `synced` stubs sharing one `controlId`.) |
| 7 | `passthrough-coverage` | Chart elements with ≤2 cols sourced from tables with ≥5 cols (the passthrough-collapse signature). FAIL on charts; WARN on thin-but-not-collapsed. KPIs excluded. See `reference/conventions.md` → "Passthrough mandate." |
| 8 | `controlid-collision` | Controls whose `controlId` matches a column `name` or `id` on the filtered element. See `reference/conventions.md` → "Control/column ID collision." |
| 9 | `bare-ref-resolution` | Bare `[column_name]` references (no `/`) that don't match any sibling column or controlId. **WARN-level** — Sigma auto-infers some column names (e.g. `DateTrunc("week", [Date])` → "Week of Date") that this regex-based check can't predict, so flags require inspection. Added 2026-05-21 — ported from upstream `validate-spec.sh`. See `reference/specification/formulas.md` → "The #1 formula mistake." |
| 10 | `control-filter-column-exists` | Control `filters[].columnId` values that don't exist on the target element, and `filters[].source.elementId` values that don't exist on the workbook. Catches typos that pass POST but silently break every downstream query on the page. Added 2026-07-02 after a fresh-agent build test surfaced this class of bug. Includes "did you mean" suggestions for near-match column IDs. |
| 11 | `action-refs-resolve` | Every action/effect reference resolves to something real: `set-control-value`/`clear-control` target/source controls exist; `open-overlay.overlayId` matches a `document.overlays[].id` (modals moved out of `pages[]` 2026-08-10, see `reference/specification/pages.md`); `navigate.target.page` matches a page; `select-tab.tabbedContainer` matches a tabbed-container element and `selectedTab.index` is in range; `insert-rows`/`delete-rows.table` matches an input-table element, and `insert-rows.values` keys match its columns. Added 2026-08-03 (Wave 2 / C3) alongside the action/effect vocabulary itself — positive-control tested against 5 deliberately-corrupted references (all caught) and 5 real production workbooks with actions (0 false positives). See `reference/specification/actions.md`. |
| 12 | `kpi-value-references-aggregation` | KPI value formulas that bare-ref sibling columns whose formulas contain aggregation functions (`Sum`, `Avg`, `Count*`, etc.). The bare ref evaluates per-row, an aggregation has no per-row value, and the KPI renders `null`. WARN-level — regex-based, so occasional false positives are possible. Fix: inline the aggregation into the value formula, or promote to a data-model metric. Added 2026-07-02 after `Marketing-and-Promotions-Performance`'s Promo Lift KPI rendered null. See `reference/specification/kpis.md` → "Value formula pitfall." |
| 13 | `summary-calc-collision` | Column IDs that appear in both `summary[]` and a `groupings[].calculations[]` list on the same table. POST rejects with `Duplicate column or folder reference`. Fix: split into two column definitions with distinct IDs. Added 2026-07-02 after `exec-scorecard` v1 hit this mid-build. See `reference/specification/tables.md` → "summary — summary-bar pattern." |
| 14 | `description-object-on-kpi-and-table` | Plain-string `description` on `kpi-chart`, `table`, `pivot-table`, or `input-table` elements. POST rejects with `Invalid object: string`. Fix: wrap as `{"text": "..."}` or `{"visibility": "hidden"}`. Chart elements accept the string form. Note: a GET-spec readback of any of these 4 kinds emits `description` as a plain string — a harvested spec must be normalized before it can be re-POSTed. Added 2026-07-02 after `inventory-health` build hit this. See `reference/specification/kpis.md` → "Description must be an object." |
| 15 | `pivot-missing-rows-and-columns` | Pivot-tables that have `values` but neither `rowsBy` nor `columnsBy` — the pivot compiles cleanly (passes POST + verify) but renders as a single grand-total row. Fix: add at least one `rowsBy` or `columnsBy` entry (`[{"id": "<dim-col-id>"}]`). Added 2026-07-02 after `Product-and-Basket-Performance` shipped two pivots that rendered as grand-total-only in the UI. See `reference/specification/tables.md` → "Shape" (pivot section). |
| 16 | `channel-exclusivity` | A column id bound to 2+ distinct binding channels on the same chart/map/KPI element (e.g. a region-map's `color.column` and `label[].id` both pointing at the same column). Sigma **rejects at POST** with `Column '<id>' is referenced from both 'X' and 'Y'; a column can only be on one channel at a time` — a hard failure, not a rendering quirk. FAIL-level. Covers `bar-chart`/`line-chart`/`area-chart`/`combo-chart`/`scatter-chart` (`xAxis`, `yAxis`, `color`, `size`), `pie-chart`/`donut-chart` (`value`, `color`, `holeValue`), `region-map`/`point-map`/`geography-map` (region/lat-lon/geography, `color`, `size`, `label`, `tooltip`), and `kpi-chart` (`value`). Fix: duplicate the column (same formula, a distinct id) and bind one id per channel. Added 2026-08-04 after a Wave 3 test session hit this live at POST — the second real-session recurrence since the rule was first documented (`exec-scorecard-v2`, 2026-07-02) without a validator check. See `reference/conventions.md` → "Channel exclusivity." |

**What this validator does not cover, even when it exits 0** (printed as a
footer on every run): qualified `[Source/Column]` refs are not verified —
the server checks those on publish; and `action-refs-resolve` (#11) does
not yet cover `agentId` references in `agents[].tools[].steps[]` effects,
since the agent surface has no chunk yet — that check extends once
`agents.md` lands.

Fix everything reported before continuing. If exit 0, proceed to the
manual pass.

The validator is part of `publish-workbook.sh post` — POSTing via the
wrapper runs validation first.

## 2. Manual formula pass (do not skip)

For each column's `formula`:

1. **List every bracketed reference** in the formula. E.g.,
   `Sum([Master/Sales]) - [Cost]` → refs are `Master/Sales` and `Cost`.
2. **For each reference, it must resolve to exactly one of:**
   - A **sibling** — the portion inside the brackets (no `/`) exactly
     matches a `name` in THIS element's `columns[]` array.
   - A **data-model metric** — `[Metrics/<X>]` where `<X>` is in the
     source element's metric catalog (from `GET /v2/dataModels/{id}/spec`,
     or `mcp-describe.sh datamodel-element <dm> <el>` — see
     `reference/workflows/discover.md` → "MCP status").
   - A **qualified ref** — contains `/`, and the prefix matches one of:
     - The last segment of the `path` array (if source is
       `warehouse-table`)
     - Another element's `name` (if source is `table` referencing
       that element)
     - A join leg's `name`, or the join's top-level `name` for
       `primarySource` columns
3. **If a reference doesn't match any of these, the formula is wrong.**
   Most common fix: add the source prefix — see
   `reference/specification/formulas.md` → "Column reference rules."

## 3. Final shape checks

- A column's `formula` references a name matching its own `name`
  field → circular reference (silent fail at render).
- A formula references a column name that doesn't exist on the source
  → re-confirm column names via `GET /v2/dataModels/{id}/spec`.
- Donut chart requires `value` + `color` (or `holeValue` if used).
- Layout XML: no `<Element type="grid">` with children — use
  `<Container>` for nesting (children are silently dropped
  otherwise).
- Controls bind via `filters[].columnId` matching a column `id` on
  the target element (NOT `name`).

## 4. Post-create — `${CLAUDE_PLUGIN_ROOT}/skills/sigma-workbook-conventions/scripts/api/verify-workbook.sh`

**Do not skip.** A successful POST is necessary but not sufficient.
Sigma accepts specs whose column formulas don't actually resolve,
then surfaces the failures *at query time* by embedding the error as
a string literal in the compiled SQL:

```sql
select V_44 "Total Revenue" from (select 'Unknown column "[ORDER_TOTAL]"' V_44) Q1
select V_11 "Quarter" from (select distinct 'Circular column reference to [Quarter]' V_11 ...) Q1
```

Affected elements render empty in the UI. Catching this from the
spec text alone is impossible — only Sigma's compiler knows.

After every CREATE and after every PUT that touches columns or
formulas, run:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/sigma-workbook-conventions/scripts/api/verify-workbook.sh <wb-id>
```

It hits `GET /v2/workbooks/<id>/elements/<eid>/query` for each
element and reports any whose SQL contains `Unknown column "..."`
or `Circular column reference to [...]` markers.

Non-zero exit means at least one element's formulas don't resolve.
Fix the spec, PUT, re-verify.

Most common causes of post-create failure:

- **Bare warehouse refs.** `Sum([ORDER_TOTAL])` instead of
  `Sum([ORDERS/ORDER_TOTAL])`. The single biggest trap. The
  `bare-ref-resolution` validator check catches most of these
  pre-POST, but not all.
- **Friendly-name mismatch.** The columns endpoint returns raw
  warehouse names (`V userId`, `UNIT PRICE`); formulas need Sigma's
  normalized friendly names (`V User Id`, `Unit Price`). Sigma is
  permissive at POST and normalizes casing for many simple cases,
  but won't rescue all of them. See `reference/workflows/discover.md`
  → "Column names — friendly vs raw warehouse."
- **Circular reference.** A column named `Quarter` with formula
  `[Quarter]` — easy when copying warehouse column names verbatim
  into a sibling-reference position. Rename one side.

### `audit-workbook-schema.sh` — the data-layer companion

`verify-workbook.sh` grep's the compiled SQL text. It misses the
class where SQL compiles but Sigma rejects the formula at query
time — the column shows `type: error` in the schema and downstream
renders as `Reference to errored column`. `audit-workbook-schema.sh`
inspects the schema via `mcp-describe workbook-element` and reports
`error`-typed columns with element + column + formula.

Runs automatically after every POST/PUT via `publish-workbook.sh`;
non-zero exit propagates so publish fails outright. Common causes:
unknown functions (e.g. `NTile`), aggregation-across-element-boundary
on grouped-source columns, `Rollup` arg3 mismatches. A cascade of
errors usually traces to one upstream errored column — fix the root,
downstream clears. Suppress with `SIGMA_SKIP_AUDIT=1`; standalone
re-audit via `${CLAUDE_PLUGIN_ROOT}/skills/sigma-workbook-conventions/scripts/api/audit-workbook-schema.sh <wb-id>`.

**Exit 3 means the gate didn't actually run — treat it as a hard
blocker, not a pass.** Originally found via a live build-mode test
2026-08-03, back when every `mcp-describe` call reliably 403'd under
this skill's then-only `client_credentials` auth model: the script
bucketed that the same way as a genuinely non-queryable element
(control/text/container) — reporting "0 queryable element(s) checked,
no error-typed columns" with exit 0, indistinguishable from a real
clean audit. Fixed so `mcp-describe.sh` exits 3 specifically for
transport-level failures (distinct from its exit 1 for "responded but
not describable"), and `audit-workbook-schema.sh` now exits 3 and
prints a loud `INCOMPLETE` warning instead of silently reporting
clean. **Under this skill's current `browser-login.sh` auth path,
`mcp-describe` is expected to succeed — an exit-3 audit now means
something's actually wrong (a stale/wrong-scope token, or a real MCP
outage), not a routine/permanent condition to route around.** Do not
report a workbook as built-and-verified on an exit-3 audit — fall
back to a manual UI check, or re-run `${CLAUDE_PLUGIN_ROOT}/skills/sigma-workbook-conventions/scripts/api/browser-login.sh` if
auth looks stale.

## 5. Visual verify in the UI

After verify-workbook returns clean, **open the workbook URL and
visually inspect.** The API doesn't validate:

- Cross-element column resolution at render (verify catches most,
  not all)
- Visualization quality / clarity
- Whether the layout looks right at typical viewport sizes
- Whether filter wiring produces the expected user experience
- Whether `[Metrics/<X>]` references resolve at render

If anything looks wrong in the UI, the issue is downstream of the
API contract. Iterate by editing the spec, PUT, re-verify, re-view.

## Decoding cryptic validation errors

Server-side validation errors point at a JSON path but don't say
what shape was expected. Use the path as the root-cause hint, then
check the spec reference file for that feature to compare shapes.

| Error pattern | Most likely cause | Where to look |
|---|---|---|
| `Invalid kind: pages[0].elements[N], got "..."` | Almost always the element's **inner shape** is wrong for the `controlType`/`kind` it claims, **not** that the kind is unsupported. Sigma's parser picks a schema by `kind` + `controlType` and reports the parent path when the inner match fails. | `reference/specification/controls.md` (slider is the most common trap), or the relevant per-element file (`charts.md`, `kpis.md`, `tables.md`). |
| `Invalid value: pages[0].elements[N].filters[M], got object` | The field is typed as an array of a specific shape and you sent something that doesn't match. | A working reference workbook (`GET` an existing workbook) for that exact field. |
| `Invalid kind: pages[0].elements[N].columns[M]` | Usually missing `id`, `name`, or `formula`, or `format.kind` mismatched. | `reference/specification/formatting.md`. |
| `Cannot resolve columns on table '<chart-id>': dependency not found: formula reference '<old-name>/<col>'` | Renamed source-of-truth table broke sibling formulas. | `reference/conventions.md` → "Rename-cascade corollary." |
| `Column has a recursive formula` | A column references itself via `name` collision, OR a chart formula re-aggregates an already-aggregated metric. | `reference/conventions.md` → "Summary-bar pattern" for the aggregate-then-categorize case. |
| **Silent bad data** — no error, but the value/element is missing or `null` on readback | (a) A boolean-operator formula written as a function call (`Not(...)` instead of `Not ...`) — parses successfully but evaluates `null` per row; (b) layout XML naming an `elementId` that doesn't exist on the page (typo, deleted element, case mismatch); (c) a control field that doesn't round-trip (e.g., `number-range` `values`). | `reference/specification/formulas.md` for (a), `reference/specification/layout.md` for (b), `reference/specification/controls.md` for (c). |
| `service_error` / 500 on GET-spec | Workbook contains a UI feature the serializer can't represent (confirmed: pivot cell heatmaps; suspected: maps, complex color-by). | `reference/scope-and-edge-cases.md` → "GET-spec can 500 when UI features aren't representable." |

**General strategy:** the error path names the offending field; the
spec reference file for that feature shows the shape. If after
checking both you still can't see the mismatch, fetch a known-good
reference workbook via `${CLAUDE_PLUGIN_ROOT}/skills/sigma-workbook-conventions/scripts/api/publish-workbook.sh get-spec
<wb-id>` and diff your shape against it.
