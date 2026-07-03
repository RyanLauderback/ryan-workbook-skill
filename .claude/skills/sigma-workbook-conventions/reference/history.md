# Workbook-spec API — Verified Incident Log

Dated incident notes from past iterations. The inline rules in the
`reference/*.md` chunks carry the rule as evergreen guidance; this file carries
the **when** and the incident that surfaced it. Useful for git-archaeology and
to flag "this rule was once unverified and bit us — treat it as load-bearing."

> **2026-05-21 reorganization note.** Pre-2026-05-21 entries reference
> chunk files that have since been split: `element-shapes.md` →
> `reference/specification/{tables,charts,kpis,controls,containers,text,others}.md`
> (per-element shapes) and `reference/conventions.md` (cross-cutting
> rules); `function-reference.md` → `reference/specification/formulas.md`
> + `reference/conventions.md`; `layout-and-cross-element.md` →
> `reference/specification/layout.md` + `reference/conventions.md`. The
> old file names in older entries below are historical — read the
> incident narrative and find the equivalent section in the new files
> if you need the current rule wording. See the migration commits
> (`e0eec01`–`c765c1d`) for the full mapping.

## 2026-05-11 — Per-page `layout` field silently discarded

POSTing a workbook spec with `layout` placed under `pages[i]` (rather than at
the workbook top level) caused Sigma to silently discard the per-page layout.
The workbook opened in the UI with all charts stacked in a 1/13-wide single
column — POST returned 200 with no warning. Verified by POST → GET-back diff.
Rule: `layout` is a top-level workbook field; multi-page = one `<?xml>` +
multiple `<Page>` siblings. See `reference/layout-and-cross-element.md` → "Layout rules."

## 2026-05-13 — Cohort iteration: legacy `groupings: [{id}]` shape

Spec authored with `groupings: [{id: "..."}]` (no `groupBy` / `calculations`)
silently failed to aggregate; downstream `Lookup` against the element returned
NULL via Sigma's defensive `iff(equal_null(min, max), max, null)` pattern. The
legacy `{id}`-only form is a render-hint serialization sometimes emitted by
older GET-backs, NOT a functional aggregation spec. Rule: use the
`{id, groupBy: ["<col-id>"], calculations: ["<col-id>"]}` form. See
`reference/layout-and-cross-element.md` → "Table groupings" → "Earlier `{id}`-only shapes."

## 2026-05-15 — `DivideSafe` hallucination committed to skill (commit 58f376a)

Commit `58f376a` added a `DivideSafe(<num>, <denom>)` row to the function
quick-reference table under the heading "Verified signatures." The function
**does not exist** in Sigma's formula library. Verified via `mcp__claude_ai_Sigma_Docs__search`
(returned only `Div` and `Zn` for safe-division queries) and via the official
Math functions page enumeration (no `DivideSafe` between `DistancePlane` and
`Exp`). Caught during the 2026-05-18 build of the customer-profitability
workbook. POST returned 200 — the formula `DivideSafe(N, D)` was accepted by
the validator but would have failed silently at render time.

Rule going forward: use `If([denom] = 0, Null, [num] / [denom])` or
`Zn([num] / [denom])` for safe division. The function quick-reference table
header has been demoted from "Verified signatures" to "Common patterns —
verify unfamiliar entries before relying on them."

## 2026-05-18 — Column `format` shape discovered (Phase 6b)

Prior skill text claimed: *"omit `format` from POST bodies entirely … the required `kind` value is not in the public docs."* That was overly conservative.

Verified shape via PUT to the Customer Profitability workbook's `p3-kpi-nr-val` column:

```json
"format": { "kind": "number", "formatString": "$,.2f" }
```

POST returned 200 and the format field round-tripped via GET-spec intact, with the currency formatting visibly applied in the Sigma UI. The earlier 400 ("Missing 'kind' field") was Sigma rejecting a format object that *lacked* `kind`, not rejecting the field categorically. With `kind` present, `format` is spec-able.

Rule going forward: `format: {kind: "number", formatString: "<python-format-spec>"}` is verified. Other kinds (`date`, `percent`, `text`) likely exist — discover via UI-toggle + GET-back diff. Skill section: `reference/scope-and-edge-cases.md` → "Column `format` field."

`scripts/validate-spec.py` still flags any `format` field present — that rule is overly conservative and should be updated to only flag `format` objects *missing* the `kind` field (follow-up).

## 2026-05-19 — Cold-start test session: chunk files not consumed (Phase 9 trigger)

Cold-start session re-ran Eval 1 (Healthcare-Claims) and a sales-performance build against PLUGS. Surface symptoms: plans were reasonable, but formulas failed; charts collapsed to 2 columns (xAxis + yAxis only); a controlId/column collision broke time-based formulas.

Forensic finding from the transcript (lines 1–5957 of `test_run_two_workbook_attempts.md`): **the 4 chunk files split out in Phase 6 (`function-reference.md`, `element-shapes.md`, `layout-and-cross-element.md`, `scope-and-edge-cases.md`) were never `Read` during authoring.** The agent loaded SKILL.md, scanned its index + 10-bullet checklist, and worked from memory of prior sessions. Chunk filenames appeared only as citations copied into `notes.md` without ever being opened.

Rule going forward: SKILL.md gained a hard-gate "Required reading before authoring" subsection mandating Reads of chunk files mapped to task type; agent must cite `Chunks Read` in the plan. Without that line, the plan is incomplete and not approvable. See `SKILL.md` → "Required reading before authoring (HARD GATE)."

## 2026-05-19 — DM-switch metric carryover (claims attempt 1)

During the claims-cost-analysis build, the user switched data models mid-session (from one Healthcare-Claims element to another with a different metrics catalog). The agent ran `mcp-describe.sh` on the new element, noted the new metric set in `notes.md` (*"Paid Claims Amt $, Cost/Member/Month, Coverage Rate, Avg Claim Paid, Member Month"*), then authored the next spec using `[Metrics/Cost per Unit] * [Metrics/Encounter Volume]` — metrics from the **original** DM. The carryover happened because the agent treated the plan as the source of truth post-recon, not the recon itself.

Rule going forward: on any data-model switch, every `[Metrics/<X>]` reference must be re-derived from the new recon. The prior plan is discarded for metric purposes. See `SKILL.md` → "Load-bearing rules" → rule #2 and `reference/scope-and-edge-cases.md` → "Metric resolution semantics."

## 2026-05-19 — Passthrough collapse from phantom-series over-correction

In the claims-cost-analysis v2 iteration, a `Lookup()`-derived column caused a phantom series on a chart. The fix — strip the Lookup column from that specific chart — was generalized incorrectly into "no chart passthroughs beyond x/y axes" (verbatim from agent's own session note, line 3506 of the transcript). Applied to the next workbook (sales-performance), which had no Lookup columns at all, the result was every chart collapsing to 2 columns. Right-click drill-down had nothing to expose.

Agent's own retrospective (line 4239): *"I overcorrected from the earlier 'phantom series' issue … rule #1 of the conventions, which I knowingly violated."*

Rule going forward: the Lookup-strip exception is narrowly scoped — only the specific Lookup col, only on the specific viz, never to base columns, never as a general "thin passthrough is fine" stance. `validate-spec.py`'s new `passthrough-coverage` check (Phase 9) catches the collapse signature pre-POST: charts with ≤2 cols sourced from tables with ≥5 cols FAIL validation. Calibrated against all 7 canonical exemplars — no false positives. See `SKILL.md` → "Load-bearing rules" → rule #1.

## 2026-05-19 — Falsely-claimed `[Metrics/Cost/Member/Month]` round-trip (cautionary tale)

During the same session, the agent wrote into `workbooks/claims-cost-analysis/notes.md`:

> *"`[Metrics/Cost/Member/Month]` accepted at PUT and round-tripped through GET — formula-namespace parser treats everything after the first `/` as the literal metric name."*

The claim was refuted in the same session minutes later when the agent observed that round-trip preserves strings without validating render — and the slash-in-name reference doesn't actually resolve. The original note remained unedited in `notes.md` and could plausibly have been auto-promoted into the skill on next recurrence per the iteration-playbook 2nd-recurrence rule.

Rule going forward: before promoting any notes.md observation, audit the iteration log for refutation. `reference/scope-and-edge-cases.md` → "Notes-promotion guardrail." Slash-in-metric-name caveat now documented in `SKILL.md` → "Load-bearing rules" → rule #2 and `reference/scope-and-edge-cases.md` → "Metric resolution semantics" → "Slash-in-name caveat."

## 2026-05-19 — Styled-name + `style.borderColor` discovered

User asked for a "red themed" workbook on the plugs-store-state-performance
build. Initial attempt mapped to what the skill said was possible —
markdown body changes + emoji prefixes — because `element-shapes.md`
carried a "Field-name TODO" comment claiming KPI title styling fields were
"not documented in Sigma's public help docs (UI-level docs only)."

User pushed back with a concrete probe: *"pull down the code representation
of [Sales-Performance-Eval-1] to compare formatting"*. GET-spec on that
workbook (a UI-themed reference exemplar in the same folder) surfaced
four spec features the skill didn't document:

1. **`name` polymorphism.** Every viz element's `name` field accepts
   either a plain string OR a styled object:
   `{text, color, fontWeight, fontSize}` — and `{visibility: "hidden"}`
   to suppress the title bar entirely. Resolves the long-standing
   `Field-name TODO` in `element-shapes.md`.
2. **Top-level `style` field.** Viz elements take
   `style: {borderRadius, borderColor, borderWidth}` for the element
   frame. Per-element override of the workbook theme's data-element
   defaults.
3. **`legend` object.** `legend: {visibility: "hidden"}` or
   `legend: {position: "bottom"}` on charts.
4. **Inline HTML in text element `body`.** Sigma's text renderer honors
   `<span style="color:#RRGGBB">…</span>` — verified round-trip.

Additionally, the reference exemplar uses `color: {by: "scale", column:
"<numeric-id>"}` on a bar chart — a second verified mode alongside the
documented `{by: "category"}` shape. And currency `format` carries
`"$.2~S"` (D3 SI prefix → `$1.2M`) with sibling fields `decimalSymbol`,
`digitGroupingSymbol`, `digitGroupingSize`, `currencySymbol`.

**Rename-cascade failure mode (same session).** Before the diff, the
agent attempted to red-theme element titles by prefixing every element's
`name` string with a red emoji. Two of those names were source-of-truth
table names (`"Transactions Detail"` → `"🔴 Transactions Detail"`,
`"D Store Lookup"` → `"🔴 D Store Lookup"`). PUT rejected with
`Cannot resolve columns ... dependency not found: formula reference
'transactions detail/date'` — 14 sibling chart/KPI formulas referenced
the old table name. The styled-name object form makes this a non-issue:
restyle the visible header without touching the display-name handle that
formulas resolve against.

Rules going forward:

- `reference/element-shapes.md` → new "Element-level styling fields"
  section documenting the verified shapes. KPI Field-name TODO marked
  RESOLVED.
- `reference/scope-and-edge-cases.md` → "Scope of the code representation"
  narrowed: KPI period-comparison stays UI-only; title styling and
  borders are now spec-able. New bullet for chart series colors (theme
  palette, still UI-only).
- `reference/scope-and-edge-cases.md` → "Column `format` field"
  augmented with the D3 SI prefix verified shape and sibling fields.
- `reference/layout-and-cross-element.md` → "Rename-cascade corollary"
  added to the explicit-`name` rule.

**Discovery technique worth keeping.** When the skill claims a property
is UI-only and the user wants it spec-able, ask whether there's a
reference workbook in the same workspace that has the property
configured. `scripts/api/find-file-by-urlid.sh <url-slug>` →
`publish-workbook.sh get-spec <id>` → diff against the current spec.
That's how this round of fields was found, and it's reusable for the
remaining UI-only properties (axis label styling, comparison-period,
table cell formatting).

## 2026-05-19 — Control/column ID collision (sales-performance attempt 2)

Sales-performance v3 spec declared `controlId: "Date"` for a date-range filter on the PLUGS Transactions Detail element, which has a `Date` column. Sigma's formula resolver shadowed the column with the control: `Month([Date])` and `Year([Date])` errored at render because the resolver returned the control's selection (a date-range scalar), not the column.

Fixed in v4 by renaming `controlId` to `DateRange` and fully-qualifying downstream column references as `[Transactions Detail/Date]`. This was the second observed instance of the pattern (cf. similar collision on a less-prominent control in a prior unrecorded session), warranting a dedicated rule.

Rule going forward: `controlId` must not match a column `name` or `id` on the filtered element. `validate-spec.py`'s new `controlid-collision` check (Phase 9) catches this pre-POST. See `SKILL.md` → "Load-bearing rules" → rule #4 and `reference/scope-and-edge-cases.md` → "Control/column ID collision."

## 2026-05-21 — `style.backgroundColor` + container/control styling discovered

Capability-1 harvest of `Sales-Performance-Eval-1`
(saved at `workbooks/harvest/retail-sales-performance/` — gitignored)
surfaced three spec fields the skill didn't yet document:

1. **`style.backgroundColor`** — fourth `style` key alongside the
   `borderRadius/borderColor/borderWidth` triple discovered 2026-05-19.
   Hex string. Verified across viz, container, and control elements.
2. **`style` applies to `container` and `control`** — not just viz.
   Containers in the retail-sales spec carry `style` objects with
   `backgroundColor + borderColor + borderWidth`; controls carry
   `backgroundColor + borderRadius`. Earlier skill text saying
   "container body is `{id, kind}` only" superseded.
3. **Partial styling is accepted.** Any subset of the four `style` keys
   is valid. Spacer containers omit `borderRadius`; KPI tiles omit
   `backgroundColor` so the container behind shows through.

**Negative finding — UI-only, doesn't round-trip.** The retail-sales
design spec (`prompts/library/train_format_retail_sales_performance.md`)
mentions `padding`, `ContainerSpacing`, and `gap` but none appear in the
JSON or layout XML on GET-back. These are UI-side toggles only. Layout
XML attributes remain limited to `gridColumn`, `gridRow`,
`gridTemplateColumns`, `gridTemplateRows`, `elementId`, `type`, `id`.

**Co-harvest blockers — same failure mode reproduced 4×.** Four other
Capability-1 candidate workbooks all returned `service_error` on
GET-spec — `Claims-Command-Center-vREL-updated`,
`Sales-MBR-Sentinel-Services-Co` (original + two strip passes), and
`Healthcare-Aesthetic-Dashboard-v2_REL`. Version rollback via
`?version=N` query param confirmed unhelpful (all 4 versions of the
MBR returned the same error). Each design spec mentions features
documented as not supported in workbooks-as-code:

- Maps (`Healthcare-Aesthetic`, `Claims-Command-Center`)
- Pivot cell-color conditional formatting (suspected on MBR)
- Buttons (`Healthcare-Aesthetic`)
- Modal/overlay pages (`Healthcare-Aesthetic`)

This confirms the failure mode documented at
`reference/element-shapes.md` → "GET-spec can 500 when UI features
aren't representable." All four blocked workbooks were omitted from
this capability's encoding.

**Out-of-scope finding (deferred to Capability 7 — chart-type updates).**
The retail-sales spec uses a chart-axis shape that diverges from
existing exemplars: `xAxis: {columnId: "..."}` / `yAxis: {columnIds:
[...]}` (vs. the existing `xAxis: {id}` / `yAxis: [{id}]` form). Both
POST cleanly per existing exemplars round-tripping fine, but GET-back
returns the `columnId` form. Decision deferred — encode in Capability
7. The exemplar uses the new form so future authoring against it
inherits the modern shape automatically.

**Out-of-scope finding (deferred to Capability 7).** The retail-sales
spec uses two color-by modes that extend the documented `{by, column}`:
`color: {by: "scale", column: "..."}` (continuous heat-map color, new
for bar-chart) and `color: {by: "category", column: "...", scheme:
["#hex", ...]}` (custom palette array on scatter). Existing skill text
("Chart series colors ... not per-element-spec-able") is partially
contradicted by `scheme`; updating that claim is also deferred to
Capability 7.

Rules going forward:

- `reference/element-shapes.md` → `style` section augmented with
  `backgroundColor`, partial-style note, container/control scope, and
  Common style recipes subsection.
- `reference/element-shapes.md` → Container element shape + Element-
  kinds table updated to remove "`{id, kind}` only" claim.
- `reference/element-shapes.md` → new "What `style` does NOT capture"
  subsection covering padding/spacing/gap UI-only.
- New exemplar `examples/styled-card-dashboard.json` +
  `.prompt.md` added to SKILL.md catalog.
- `scripts/workbook-manifest.py` → recognized name-object keys expanded
  to `{text, color, fontSize, fontWeight, visibility}`; dynamic-text
  heuristic narrowed to Sigma template syntax (`{{...}}`) so inline
  HTML stops triggering false positives.
- `scripts/api/harvest-workbook.sh` → fail-fast on `service_error`
  responses with diagnostic message + cleanup of bogus spec.json.
