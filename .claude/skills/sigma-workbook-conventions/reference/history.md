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

## Table of contents

- [2026-05-11 — Per-page `layout` field silently discarded](#2026-05-11--per-page-layout-field-silently-discarded)
- [2026-05-13 — Cohort iteration: legacy `groupings: [{id}]` shape](#2026-05-13--cohort-iteration-legacy-groupings-id-shape)
- [2026-05-15 — `DivideSafe` hallucination committed to skill (commit 58f376a)](#2026-05-15--dividesafe-hallucination-committed-to-skill-commit-58f376a)
- [2026-05-18 — Column `format` shape discovered (Phase 6b)](#2026-05-18--column-format-shape-discovered-phase-6b)
- [2026-05-19 — Cold-start test session: chunk files not consumed (Phase 9 trigger)](#2026-05-19--cold-start-test-session-chunk-files-not-consumed-phase-9-trigger)
- [2026-05-19 — DM-switch metric carryover (claims attempt 1)](#2026-05-19--dm-switch-metric-carryover-claims-attempt-1)
- [2026-05-19 — Passthrough collapse from phantom-series over-correction](#2026-05-19--passthrough-collapse-from-phantom-series-over-correction)
- [2026-05-19 — Falsely-claimed `[Metrics/Cost/Member/Month]` round-trip (cautionary tale)](#2026-05-19--falsely-claimed-metricscostmembermonth-round-trip-cautionary-tale)
- [2026-05-19 — Styled-name + `style.borderColor` discovered](#2026-05-19--styled-name--stylebordercolor-discovered)
- [2026-05-19 — Control/column ID collision (sales-performance attempt 2)](#2026-05-19--controlcolumn-id-collision-sales-performance-attempt-2)
- [2026-05-21 — `style.backgroundColor` + container/control styling discovered](#2026-05-21--stylebackgroundcolor--containercontrol-styling-discovered)
- [2026-07-12 — `audit-workbook-schema.sh` added as post-POST data-layer gate](#2026-07-12--audit-workbook-schemash-added-as-post-post-data-layer-gate)
- [2026-08-03 — Capability-expansion planning: a load-bearing phantom limitation, a retracted validator check, and gate cleanup](#2026-08-03--capability-expansion-planning-a-load-bearing-phantom-limitation-a-retracted-validator-check-and-gate-cleanup)
- [2026-08-03 — Portability fixes + `composition.md` ported + dashboard-tier exemplar](#2026-08-03--portability-fixes--compositionmd-ported--dashboard-tier-exemplar)
- [2026-08-03 — Wave 0 build-mode test finds a real masked-failure bug in the audit gate](#2026-08-03--wave-0-build-mode-test-finds-a-real-masked-failure-bug-in-the-audit-gate)
- [2026-08-03 — Wave 1 / C2: live-POST probe for layout/page-structure, plus two more real bugs](#2026-08-03--wave-1--c2-live-post-probe-for-layoutpage-structure-plus-two-more-real-bugs)
- [2026-08-03 — Multi-page `<?xml ?>` declaration bug (found via a real build-mode session, not a probe)](#2026-08-03--multi-page-xml--declaration-bug-found-via-a-real-build-mode-session-not-a-probe)
- [2026-08-03 — Four more bugs found live-iterating the same build (KPI nulls, container-child coordinate model, orphaned grouping column, aggregate-null-propagation)](#2026-08-03--four-more-bugs-found-live-iterating-the-same-build-kpi-nulls-container-child-coordinate-model-orphaned-grouping-column-aggregate-null-propagation)
- [2026-08-03 — Wave 2 / C3: the full action/effect vocabulary, live-POST verified](#2026-08-03--wave-2--c3-the-full-actioneffect-vocabulary-live-post-verified)
- [2026-08-04 — document wrapper: the live wire format nests the spec under `document`](#2026-08-04--document-wrapper-the-live-wire-format-nests-the-spec-under-document)
- [2026-08-04 — two real bugs found in `dashboard-department-scorecard.json` via its first-ever live POST](#2026-08-04--two-real-bugs-found-in-dashboard-department-scorecardjson-via-its-first-ever-live-post)
- [2026-08-04 — `find-file-by-urlid.sh` didn't handle a pasted full workbook URL](#2026-08-04--find-file-by-urlidsh-didnt-handle-a-pasted-full-workbook-url)
- [2026-08-04 — second peer report: 1 confirmed, 2 refuted (again), 2 more refuted, 1 real docs gap found independently](#2026-08-04--second-peer-report-1-confirmed-2-refuted-again-2-more-refuted-1-real-docs-gap-found-independently)
- [2026-08-04 — Wave 3 / C5+C6: input tables + agent surface, live-POST verified](#2026-08-04--wave-3--c5c6-input-tables--agent-surface-live-post-verified)
- [2026-08-04 — Wave 3 real build-mode test: sales dashboard + input-table writeback + `channel-exclusivity` check shipped](#2026-08-04--wave-3-real-build-mode-test-sales-dashboard--input-table-writeback--channel-exclusivity-check-shipped)
  - [Follow-up, same day — `Percentile` is not a real Sigma function (hallucination, same class as `DivideSafe`)](#follow-up-same-day--percentile-is-not-a-real-sigma-function-hallucination-same-class-as-dividesafe)
  - [Second follow-up, same day — a "confirmed fixed" claim was itself wrong (verification false-positive)](#second-follow-up-same-day--a-confirmed-fixed-claim-was-itself-wrong-verification-false-positive)
- [2026-08-04 — Wave 4 / C7: visual media + theming, live-POST verified, 2 real field-shape bugs found](#2026-08-04--wave-4--c7-visual-media--theming-live-post-verified-2-real-field-shape-bugs-found)
- [2026-08-04 — Wave 4 / C8: scenario modeling pattern, 2 structural gotchas checked](#2026-08-04--wave-4--c8-scenario-modeling-pattern-2-structural-gotchas-checked)
- [2026-08-07 — MCP access confirmed blocked for client_credentials tokens; not a per-org scope gap](#2026-08-07--mcp-access-confirmed-blocked-for-clientcredentials-tokens-not-a-per-org-scope-gap)
- [2026-08-07 (continued) — data-model-first discovery framing + raw-table routing cost data](#2026-08-07-continued--data-model-first-discovery-framing--raw-table-routing-cost-data)

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

## 2026-07-12 — `audit-workbook-schema.sh` added as post-POST data-layer gate

Two consecutive builds shipped workbooks with `Reference to errored
column` cascades despite `verify-workbook.sh` reporting `[ok]`:
2026-07-03 retention hit `Rollup` arg3 mismatch; 2026-07-09 RFM
cycled through `NTile`, inline `Percentile` sibling-ref, and a
thresholds table with `Percentile([<GroupedSource>/<col>], 0.2)` —
all three produced `type: error` on the score columns. Verify greps
compiled SQL for unresolved-ref markers; it does not inspect schema
types, so runtime-error columns with structurally valid SQL pass
silently.

**Forward note (2026-08-04):** this build's `Percentile` usage was
the same hallucinated, nonexistent function later fully root-caused
in the Wave 3 test session below (`formulas.md` had it listed as real
all along) — at the time, the fix here was a general data-layer audit
tool, not a correction to the function name itself, so this exact
class of error went unfixed at the source for almost a month. See
`reference/specification/formulas.md` → the `Percentile` hallucination
warning and the entry below, "Follow-up, same day — `Percentile` is
not a real Sigma function."

**Fix.** `scripts/api/audit-workbook-schema.sh <wb-id>` iterates
every element via `mcp-describe workbook-element`, parses the DDL
for `error`-typed columns, and reports element + column + formula.
`publish-workbook.sh` auto-invokes it after POST/PUT and propagates
the exit code. Failure classes in
`reference/workflows/validate.md` → §4 audit subsection.

## 2026-08-03 — Capability-expansion planning: a load-bearing phantom limitation, a retracted validator check, and gate cleanup

Planning to extend this skill toward interactive/agentic workbook
features (buttons, agents, input tables, SVG, scenario modeling)
surfaced a much bigger problem than expected: `others.md` → "What about
buttons and modals?" and `scope-and-edge-cases.md` had been asserting,
since some earlier session, that buttons, modals, tabbed containers,
page breaks, and action sequences were **"not supported"** and "break
GET-spec." **All five round-tripped cleanly (HTTP 200, full fidelity)**
against 5 real production workbooks harvested during planning (Claims
Command Center, Insurance P4P Analytics, Workbooks Demo 2026, Marketing
Control Center, Bergey's Unified Insights). This is the `DivideSafe`
failure mode in the opposite direction — instead of a hallucinated
capability, a hallucinated (or stale, unverified) *limitation* — and it
had been steering every build away from working functionality.

The real upstream `sigma-workbooks` skill (finally read in full — a
prior attempt was blocked by SAML SSO on `sigma-agent-skills-dev`, and a
structurally similar-looking repo mistaken for a mirror was used as a
proxy in the interim) turned out not to cover this surface at all, in
either direction — it doesn't document buttons/actions/agents/plugins
one way or the other. So this correction rests entirely on this skill's
own harvest evidence, which is the correct standard: it's literally
upstream's own recommended discovery technique (find a reference
workbook, GET its spec, study it). Upstream's own validator-error
guidance (`reference/workflows/validate.md` → "Decoding cryptic
validation errors") already explains the likely root cause: a generic
`Invalid kind` or a GET-spec 500 caused by an unrelated feature on the
same workbook, misread as "this kind is rejected."

**Fix.** Retracted the false claim in `others.md` and
`scope-and-edge-cases.md` (kept as strikethrough + explanation per the
notes-promotion guardrail, not silently deleted); corrected
`SKILL.md:328-330`'s input-table prohibition to scope it to data-model
round-trip only (it was contradicting `tables.md` and reads as a blanket
ban if skimmed); added `reference/capability-ledger.md` — a dated,
sourced ledger of verified-supported and unverified-pending claims, plus
the retest protocol that should have been applied before the original
claim was written.

**A second, related finding while implementing the validator check for
load-bearing rule #2** (`conventions.md` → "Explicit-`name` rule"):
implementing `name-required-on-passthrough` literally, then calibrating
it against all 11 canonical `examples/` specs *and* the 5 harvested
production workbooks (mandatory before shipping any new check — see the
2026-05-19 entry above), produced 587 / 131 / 25 hits on 3 real,
currently-rendering dashboards and 6+ hits on 3 non-deprecated canonical
examples. That's not a check finding real bugs — it's the documented
rule itself being either a phantom limitation or far narrower in its
real trigger condition than its prose states. **Retracted, not shipped**
— the function is left in `validate-spec.py` with a docstring explaining
why, but is not wired into `CHECKS` or `main()`. Needs an isolated live
POST probe to find the real trigger, if one exists, before any version
of this check ships.

**Also this session:**
- `validate-spec.py`: added `"TabbedContainer"` to the layout-XML tag
  set `elements-placed-in-layout` recognizes (5 false FAILs on 2
  independent harvested workbooks, exact tabbed-container count both
  times); exempted `controlType:"synced"` from `control-id-unique`
  (Bergey's Unified Insights showed the exact mechanism — one primary
  control + N `synced` cross-page stubs sharing a `controlId`); added
  `layoutelement-has-children` (forward case of `containers-have-children`,
  ported from the real upstream skill's manual checklist); added YAML
  input support (PyYAML → `yq` fallback chain, also ported from
  upstream); added a stated-limitations footer to every run. Net: 13 →
  14 checks. Full regression clean across all 11 examples + 5 harvested
  specs after these changes.
- `reference/workflows/validate.md`: the check table had drifted from
  `CHECKS` in both directions — 5 documented checks didn't exist in
  code, 4 implemented checks had no row. Reconciled to match code
  exactly, in `CHECKS` order.
- `tables.md` → "Input tables": fixed `columnType` → `type` (0
  occurrences of `columnType` across 5 harvested specs; independently
  confirmed by the real upstream skill's own doc via a completely
  different method), added the required `connectionId` on
  `source.kind:"empty"`, corrected `linked` (binds to another *element*,
  not directly to a warehouse table), and documented all 6 column
  shapes (upstream's 4 plus `dropdown`/`pills` and `file`, both
  harvest-only).
- Gate single-sourcing: `reference/workflows/plan.md` and
  `docs/iteration-playbook.md` each carried their own partial copy of
  the task-type → chunk table, both already drifted from `SKILL.md`'s
  version (missing rows, stale "Capability N" labels). Both now point
  at `SKILL.md` instead of re-listing rows — the 4-place duplication
  that made the check-table drift above possible is retired.
- `SKILL.md`: fixed the `example-full.yaml` "verbatim from upstream"
  provenance claim — the real upstream skill has no such file; it's
  local-authored content, mislabeled.
- `schema.md`: softened "response-only fields must be stripped...
  sending unknown top-level fields is rejected" to match the real
  upstream skill's claim that these are ignored on write (stripping is
  still the recommended, cleaner practice).

Full capability decomposition, sequencing, and the remaining waves
(action/effect vocabulary, agent surface, layout/page structure chunk,
dynamic-value binding, visual media/theming, scenario-modeling pattern,
plugin packaging) are tracked outside this file for the duration of the
active work.

## 2026-08-03 — Portability fixes + `composition.md` ported + dashboard-tier exemplar

Continuation of the same session. Two more pieces landed:

**Portability (C9-a).** Fixed the cwd-relative `.env` lookup that made
auth only work when invoked from the repo root (`ENV_FILE` now anchors to
the script's own directory); the discarded exit code on
`eval "$(load-env.sh)"` that let a missing `.env` proceed silently with
empty vars; the fixed, world-guessable `/tmp/.sigma_token` cache (moved
to a per-user `$SIGMA_TOKEN_CACHE` path, `chmod 600` explicitly rather
than relying on umask alone); and `sigma_curl`'s 401 self-heal sourcing
the wrong path once inherited via `export -f`. Added `.gitattributes`
(LF line endings — a Windows/CRLF checkout would otherwise turn every
`.sh` into a "bad interpreter" failure under WSL) and fixed missing
`encoding="utf-8"` in `workbook-manifest.py`/`validate-spec.py`. Decided:
**WSL-only for Windows** — native Windows lacks a reliable `python3` on
PATH, and threading a `$SIGMA_PYTHON` shim through 25 call sites for a
platform with no CI coverage was judged not worth the permanent
unenforced-drift risk. Added `scripts/doctor.sh` as a first-run
diagnostic. Verified end-to-end: `bash scripts/api/whoami.sh` succeeds
when invoked from an unrelated cwd (the actual bug), with a fresh token
mint, the cached-token fast path, and correct `0600` permissions on the
new cache path.

**`reference/workflows/composition.md`** ported near-verbatim from the
real upstream `sigma-workbooks` skill — design judgment (the sizing
ladder, when to stop and ask, the hidden-base-table/sorted-ranking/
no-exposed-joins defaults) that this skill had never carried; `plan.md`
covers process, not judgment. Added to the "every build always" gate row.

**New exemplar: `examples/dashboard-department-scorecard.json`** — the
"dashboard" tier of the sizing ladder, modeled on Bergey's Unified
Insights (the real production dashboard harvested during planning).
Closes two gaps: no existing exemplar demonstrated the hidden-base-table
default (the flagship 3-page exemplar puts its base table visibly on the
dashboard page), and no exemplar demonstrated the exec-KPI recipe
(`style.borderRadius:"round"` + `periodComparison` + `timeline` + styled
`name`) verified present ~67 times in that real dashboard. Deliberately
built from only already-established, already-battle-tested spec shapes —
no buttons/actions/agents — since those hadn't yet been through the
Wave 0 POST probe at authoring time; the sidecar `.prompt.md` says so
explicitly. Validated clean (14/14 checks, 0 fail/warn). Also fixed a
stale "buttons, modals unsupported" line in
`data-model-sourced-sales-command-center.prompt.md` that had escaped the
earlier retraction sweep.

## 2026-08-03 — Wave 0 build-mode test finds a real masked-failure bug in the audit gate

The Wave 0 test session (a full kickoff → recon → plan → approval → POST
→ GET → verify build-mode run against the live org, producing a real
published workbook) surfaced two bugs, both traced to the same root
cause: this org's OAuth client lacks MCP scope, so every `mcp-describe`
call returns HTTP 403.

**Bug 1 — `audit-workbook-schema.sh` reported a false clean pass.** The
script bucketed "mcp-describe failed at the transport level" the same
way as "element is genuinely non-queryable" (controls/text/containers),
so a total MCP outage produced "0 queryable element(s) checked, no
error-typed columns" with exit 0 — indistinguishable from a real clean
audit of a workbook with nothing to check. This directly undermined
`plan.md`'s own stated rule: "Do not report the workbook as built until
audit returns clean." Exactly the class of masked failure this skill's
doctrine exists to catch — a safety gate that silently no-ops instead of
failing loudly.

**Bug 2 — `mcp-describe.sh` crashed with a raw traceback on HTTP
errors.** A 403 raised an unhandled `urllib.error.HTTPError`, dumping a
Python traceback instead of pointing at the documented REST fallback
(`discover.md` → `GET /v2/dataModels/{id}/spec`). The test session only
recovered because it had just read that fallback section — a
less-prepared session could easily read the traceback as fatal.

**Fix.** `mcp-describe.sh` now catches `HTTPError`/`URLError` and exits
**3** (a new, distinct code) with a clean message naming the likely cause
and the REST fallback — kept separate from exit 1 ("MCP responded but
this object isn't describable," the normal case for controls/text).
`audit-workbook-schema.sh` now checks for exit 3 specifically, tracks it
in a separate `DESCRIBE_FAILURES` counter, and — if any element hit
it — exits 3 itself with a loud `INCOMPLETE` warning instead of a clean
report. `publish-workbook.sh`'s existing `set -e` already propagates this
correctly (verified: it already documents "exits with the audit's exit
code so the caller sees the failure signal," unchanged). `plan.md` and
`validate.md` updated to document exit 3 as a hard blocker, not a pass.

Verified against the live org and the real published test workbook
(`fa396595-4b8c-484d-8ce6-049682e3498a`): `mcp-describe.sh` now prints a
clean message and exits 3 (previously a raw traceback); a fresh
`audit-workbook-schema.sh` run against that workbook now correctly
reports "INCOMPLETE — 10 of 10 element(s) could not be checked" and
exits 3, where it previously would have printed a false "0 queryable
element(s) checked, no error-typed columns" / exit 0. Full 12-example
validator regression re-run clean after these changes.

## 2026-08-03 — Wave 1 / C2: live-POST probe for layout/page-structure, plus two more real bugs

Per this skill's own doctrine ("only probe-confirmed behavior may be
written as a rule"), the capability ledger's evidence for tabbed
containers, modal pages, navigation, and page breaks was GET-spec-only
(read from existing production workbooks) — never confirmed by
authoring one from scratch and POSTing it. Before writing
`specification/pages.md` or correcting `layout.md`'s grammar claim,
authored a scratch probe workbook (folder "Claude Testing",
`workbookId: b9e4bc48-afa8-4085-b94d-fdd61c06bf0d`) covering all four,
POSTed it, GET'd it back, and diffed.

**Result: full round-trip confirmed, plus one genuinely new fact.** The
layout XML's `<TabbedContainer>`/`<Tab>` tags, the `tabbed-container`
element's flat-sibling-content model, and the `navigation`/`page-break`
element shapes all round-tripped byte-for-byte exactly as authored.
**New discovery:** a `type:"modal"` page authored with
`gridTemplateColumns="repeat(24, 1fr)"` (matching a normal page) came
back on GET with that attribute silently rewritten to
`repeat(12, 1fr)` — modal pages get a 12-column layout grid, not 24,
regardless of what's authored. `layout.md` and `pages.md` updated
accordingly; `layout.md`'s "two-tag grammar" / "closed attribute set"
claims retired.

**Along the way, the probe surfaced three more bugs, all real, all
fixed:**

1. **`publish-workbook.sh`'s `post`/`put` cases silently swallowed the
   actual error body on failure.** `response=$(sigma_curl ...)` is a
   plain assignment from a command substitution — under `set -e`,
   sigma_curl returning non-zero (any HTTP ≥400) makes that assignment
   itself the failing command, so the script exited immediately,
   *before* the following `echo "$response"` line ever ran. sigma_curl
   still printed the error body internally, but it was discarded before
   reaching the caller — a failed POST reported nothing but a bare exit
   1. Hit this directly: the probe's first two POST attempts each
   failed with zero diagnostic output. Fixed by wrapping the capture in
   `set +e`/`set -e` and echoing the response before propagating the
   exit code, in both the `post` and `put` cases.
2. **The new `dashboard-department-scorecard.json` exemplar (added in
   the CW entry above) had never actually been POSTed** — it used
   `schemaVersion: 2`, which the live API rejects outright
   (`"schemaVersion: Invalid 1: number"`). Every other canonical
   exemplar uses `1`; this was a plain authoring mistake, not a docs
   gap (`crud.md` already correctly documents `1` as the working value).
   Fixed the exemplar, and added a new WARN-level validator check
   (`schema-version`, #15) so a non-`1` value gets flagged pre-POST
   going forward.
3. **The probe's own authoring mistakes were themselves useful
   confirmations, not bugs**: `kind:"text"` needs `body`, not `text`
   (already correctly documented in `text.md` — the probe's first draft
   just didn't follow it), and raw `<h2>` is rejected by the live API's
   inline-HTML allowlist (`<u>`, `<sub>`, `<sup>`, `<span>`, `<a>` only —
   `text.md` updated to state this is the *complete* set, confirmed
   verbatim from the rejection error, and to explicitly warn against
   raw heading tags in favor of Markdown `#`/`##`/`###`).

Also found and fixed one more stale instance of the retracted
"unsupported" claim that escaped the original sweep:
`examples/styled-card-dashboard.prompt.md` still called maps "currently
documented as unsupported" — stale even before this session, since maps
were verified supported back on 2026-07-02 (`scope-and-edge-cases.md` →
"Map element status"). And `SKILL.md`'s `others.md` catalog gloss still
ended with "buttons/modals unsupported note" — fixed to point at the
retraction.

Full 12-example validator regression (now 15 checks) re-run clean
after all of the above. The scratch probe workbook
(`b9e4bc48-afa8-4085-b94d-fdd61c06bf0d`, "Claude Testing" folder) is
left in the live org pending user confirmation to delete — this skill's
own convention requires asking before any DELETE, including for
self-created test artifacts.

## 2026-08-03 — Multi-page `<?xml ?>` declaration bug (found via a real build-mode session, not a probe)

A follow-up test session (fresh kickoff → recon → plan → approval → build,
against a real user ask — "wave 1 test," a sales dashboard with 3 tabbed
containers for region/customer/product plus a click-to-modal state map)
deliberately exercised the newest Wave 1 / C2 surface (tabbed containers,
modal pages, region-map click actions) in combination, in one spec,
authored from this skill's own chunk text rather than copied from the
Wave 1 probe. The first full POST failed with a generic, field-less 400:

```
{"code":"invalid_request","message":"An error has occurred. Please try again later (incident-id=...)"}
```

No JSON path, no field name — none of `validate.md`'s cryptic-error
patterns matched. `validate-spec.py` passed all 15 checks (it has no way
to catch this class of error). `publish-workbook.sh`'s Wave-1-fixed
error-echoing worked correctly and showed this body, but the body itself
carried no diagnostic content — so the fix from earlier that session
(making failures visible at all) was necessary but not sufficient here.

**Root cause, found via bisection against the live API (POST a reduced
spec, observe 200 vs 400, narrow the diff):** this file's own prose
(`layout.md` → "Layout is top-level") said multi-page workbooks
concatenate per-page XML documents "each with its own `<?xml ?>`
declaration" — plausible-sounding, and exactly what an agent authoring
from that prose (rather than copying a real spec byte-for-byte) would
write: `<?xml ?><Page id="page-1">...</Page><?xml ?><Page
id="page-2">...</Page>`. **That prose was wrong.** A live GET of the
actual Wave 1 probe workbook (`b9e4bc48-afa8-4085-b94d-fdd61c06bf0d`)
shows exactly ONE `<?xml version="1.0" encoding="utf-8"?>` declaration
for the entire layout string, with every subsequent `<Page>` as a bare
sibling — no one had actually re-read that probe's raw layout string
character-for-character against the prose describing it until this
session did, mid-bisection.

**A second bug, same incident, same root symptom:** the same probe spec
also revealed the modal page's layout `<Page>` tag keeps `type="grid"` —
the `type="modal"` distinction lives *only* in the JSON `pages[].type`
field. This session's first attempt mirrored `type:"modal"` into the
layout XML's `<Page type="modal" ...>` attribute — a second natural
mistake, and, combined with the declaration bug, part of the same 400.

**Bisection method (worth keeping as a technique note):** built a
"core-only" reduced spec (the dashboard minus map/modal/cross-page
control) and POSTed it directly — 200. Then added back pieces one at a
time (map alone: 200; modal + a flat table, no control: still 400 — a
red herring at first, traced to a *second*, unrelated bug the bisection
script itself introduced: a dangling `<LayoutElement>` reference to an
already-removed control element, which `validate-spec.py`'s
`elements-placed-in-layout` check does NOT catch because it only verifies
every *element* has a layout entry, not the reverse — see the open
follow-up below). Once that self-inflicted bug was fixed and the modal
page still 400'd alone, direct comparison against the live probe spec's
raw `layout` string (fetched via `GET /v2/workbooks/{id}/spec`) surfaced
both real bugs above within one diff-read.

**Fix.** `layout.md` → "Layout is top-level (NOT per-page)" corrected
with the right concatenation shape and the exact 400 signature to
recognize; `layout.md` → "Modal pages get a 12-column grid, not 24"
augmented with the `type="grid"` correction; `pages.md` → modal section
cross-references both. Full build then succeeded: HTTP 200 POST,
`verify-workbook.sh` 27/27 elements compiling clean, GET-back round-trip
byte-for-byte on the tabbed container, modal page, and map's
`on-select` → `set-control-value` + `open-overlay` action chain.
`audit-workbook-schema.sh` returned the expected `INCOMPLETE` (exit 3,
this org's OAuth client still lacks MCP scope) — not a new bug, the same
documented gap from the Wave 0 test session.

**Open follow-up, not yet implemented:** `validate-spec.py` has no check
for (a) more than one `<?xml ?>` declaration in `layout`, or (b) a
layout `elementId` reference that matches no element anywhere in the
spec (the reverse of the existing `elements-placed-in-layout` check).
Both are exactly the silent/generic-failure shapes this skill's own
doctrine says are worth a pre-POST check. Left as a candidate for the
next validator pass rather than added under time pressure in this
session — a new check should be calibrated against all canonical
examples + harvested specs before shipping, per the 2026-05-19 and
2026-08-03 promotion-guardrail precedent above.

## 2026-08-03 — Four more bugs found live-iterating the same build (KPI nulls, container-child coordinate model, orphaned grouping column, aggregate-null-propagation)

Continuation of the same real build-mode session (the "wave 1 test"
dashboard). After the initial successful publish, three rounds of user
feedback ("everything is blank" → "spacing/nulls/modal are still wrong"
→ "same bugs persist, and the KPI null is a column-vs-calculation bug")
surfaced four more real, previously-undocumented bugs — none caught by
POST, `validate-spec.py`, or `verify-workbook.sh`, because all four are
either data-shape or layout-shape problems, not spec-shape problems.

1. **A restrictive `date-range` control default silently zeroed every
   row.** `mode:"last", value:24, unit:"month", includeToday:true`
   resolves relative to the real calendar date at render time, not the
   data's actual range — against a synthetic `PERFORMANCE_TESTING_DB`
   table with no relationship to "today," the resulting window matched
   zero rows, and every KPI/chart/table downstream rendered empty.
   Diagnosed via `GET /v2/workbooks/{id}/elements/{eid}/query` (compiled
   SQL preview — the same endpoint `verify-workbook.sh` uses) showing the
   literal pushed-down `WHERE` clause. Fixed by defaulting to
   `mode:"between"` with no bounds. See `controls.md` → the new caution
   under `date-range`.
2. **`Sum()` over an all-null input returns `NULL`, not `0`**, silently
   poisoning any downstream sibling-ref arithmetic
   (`Profit = Revenue - COGS` → `NULL` for any group with incomplete
   cost data). Fixed by wrapping every such aggregate in `Zn(...)`. See
   `formulas.md` → "Numeric guards."
3. **A column declared outside a grouped table's `groupBy`/`calculations`
   renders as a nonsensical "summary" value.** The modal's detail table
   grouped by Product Name only, with `Store State` sitting in
   `columns[]` unreferenced by the grouping — neither a dimension nor a
   calculation. Fixed by folding it into a compound `groupBy`. See
   `tables.md` → "groupings."
4. **The KPI-null root cause, precisely diagnosed by the user:** all 5
   KPIs used a bare cross-element reference to another element's own
   already-aggregated column (`[Transactions Detail/Total Revenue]`,
   itself a `Sum(...)` broadcast over an ungrouped table) instead of
   writing the calculation directly. This forces Sigma into a defensive
   `equal_null(min(x), max(x))` uniformity check in the compiled SQL,
   which collapsed to `NULL`. Confirmed via compiled-SQL diff
   before/after. Fixed by inlining the aggregation on the KPI itself.
   This is the same failure class `kpis.md` already documented for
   *same-element* sibling refs ("Value formula pitfall") — this session
   confirms it generalizes to cross-element refs too, and the existing
   `kpi-value-references-aggregation` validator check does not catch the
   cross-element form. See `kpis.md`.
5. **The real layout root cause (correcting this same session's own
   earlier, wrong fix attempt):** `<GridContainer>` children use row
   coordinates **local** to that container (starting at row 1),
   never the page's absolute row numbering. Every layout example
   previously in `layout.md` — and every layout attempt earlier in this
   same session — used containers that happened to start at page-row 1,
   which hides the local/absolute distinction (they coincide only in
   that case). Proven by diffing against a real canonical exemplar
   (`examples/dashboard-department-scorecard.json`), whose `ctr-kpi-row`
   sits at page-absolute `4/12` while its children read `1/9`. This
   single misunderstanding was the actual cause of the "poorly laid out"
   complaint across *three* consecutive fix attempts, each making it
   worse: feeding absolute child coordinates that grew larger each round
   (chasing the server's own auto-expansion) was read by Sigma as ever-
   larger *local* start positions, forcing the container to keep
   re-expanding. Confirmed fixed with a completely stable PUT → GET-back
   round-trip (zero drift in any row/column number), vs. three rounds of
   worsening drift beforehand. `layout.md`'s prior "re-anchor to the
   container's actual expanded band" note (added mid-session, before
   this correction) was itself wrong and has been retracted/replaced.

**Retest note:** full 12-example validator regression re-run clean after
every fix in this entry (still 15/15, no regressions).

## 2026-08-03 — Wave 2 / C3: the full action/effect vocabulary, live-POST verified

Per this skill's own doctrine, the action/effect vocabulary was
partially GET-spec-only until this session: the earlier wave-1-test
build had live-POST-verified exactly 2 of 9 effects
(`set-control-value`, `open-overlay`, via the map-click → modal
interaction) plus the `on-select` trigger. The remaining 7 effects, the
`button` element, and `on-click` had never been authored from scratch
by this skill and POSTed.

**Harvested the 2 already-confirmed effects directly from the real
build** (`fe0140e9-3798-4a9a-a30b-03af8ddbc8ef`) rather than re-probing
them — confirmed `set-control-value.control` and `clear-control.scope.control`
reference a `controlId` (not the control element's own `id`), and
`open-overlay.overlayId` references a modal page's `id` (not an element
id).

**Built a dedicated scratch probe** (`189db290-7674-4032-9ff7-7fad59dc14fa`,
"Claude Testing" folder) with 8 buttons, one per remaining effect
(`clear-control`, `navigate`, `select-tab`, `open-url`, `insert-rows`,
`delete-rows`, `close-overlay`, plus a second `open-overlay` for
completeness), a tabbed-container (for `select-tab`'s target), an
input-table (for `insert-rows`/`delete-rows`), a second page (for
`navigate`), and a modal page (for `open-overlay`/`close-overlay`).
**POSTed clean on the first try** — no bisection needed this time,
unlike the Wave 1 layout bugs. GET-back confirmed all 7 effects
round-tripped byte-for-byte. A follow-up PUT to the same workbook added
a `{type:"control"}` dynamic-value form (in `insert-rows.values`) and a
`{{formula}}`-interpolated modal header title referencing a bare
`[controlId]` — both also round-tripped byte-for-byte.

**Result: all 9 effects and 4 of 5 dynamic-value forms are now
live-POST verified** (`agent-input` remains GET-spec-only pending the
agent surface). Referential semantics nailed down precisely:
`set-control-value.control`/`clear-control.scope.control` = `controlId`;
`open-overlay.overlayId`/`navigate.target.page` = page `id`;
`select-tab.tabbedContainer` = element `id`, `selectedTab.index` is
0-based; `insert-rows`/`delete-rows.table` = input-table element `id`.

**Fix.** Added `reference/specification/actions.md` (the `button`
element + all 9 effects) and `reference/specification/dynamic-values.md`
(the 5-form value-binding matrix, plus `{{formula}}` string
interpolation). Added the `action-refs-resolve` validator check (#11,
16 total) closing the referential-integrity gap flagged when the
vocabulary first shipped in Wave 1 — verifies every `control`/`table`/
`overlayId`/`tabbedContainer`/`target.page` reference in every action
resolves to something real, and that `select-tab.selectedTab.index` is
in range. Positive-control tested: injected 5 deliberately-broken
references into the probe spec and confirmed all 5 caught; then
confirmed 0 false positives against all 5 harvested production
workbooks with real actions (their references were all genuinely
valid — a true negative, not a check that never fires). Full 12-example
canonical regression re-run clean throughout.

## 2026-08-04 — document wrapper: the live wire format nests the spec under `document`

A Wave 2 build-mode test session (a second, independently-spawned test
sub-agent) reported two claims about the live POST/PUT/GET wire format,
both of which directly contradicted this session's own extensively
live-POST-verified Wave 1/Wave 2 work (which had succeeded with a flat
top-level shape). Per this skill's own "verify, don't trust a summary"
doctrine — doubly so when a claim contradicts already-verified
evidence — both were independently re-tested from scratch rather than
merged as reported.

**Claim 1 — confirmed real:** the live API nests `schemaVersion`,
`kind`, `pages`, `layout`, `themeOverrides`, `folders`, and `agents`
under a top-level `document` key; only `name`/`folderId`/`description`
stay top-level siblings, and `document.kind` is required and always
`"workbook"`. Verified via direct bisection: a bare flat-shape POST was
rejected with a large union-type validation error naming paths like
`0.document.0.0.0`; adding a `document` wrapper without `kind` still
failed; adding `document.kind: "workbook"` succeeded
(`workbookId: a6b5b06b-6073-45ba-aa5c-518a816d0964`). A `GET .../spec`
with `Accept: application/json` confirmed the same nesting on read.

**Claim 2 — checked and refuted (red herring):** the claim that
successful POST/PUT responses come back as plain `key: value` text
rather than JSON. `scripts/api/_env.sh`'s `sigma_curl` helper — the
actual call path for every script in `scripts/api/`, including
`publish-workbook.sh` — already sends `Accept: application/json`
(confirmed via `grep -n "Accept:" scripts/api/_env.sh`). Explicit
`Accept`-header tests on both GET and POST returned clean JSON in both
directions. The plain-text response only appeared in raw `curl` calls
(the test sub-agent's own ad-hoc bisection scripts, and mine when
reproducing) that omitted this header — a real observation about bare
curl, but not a property of this skill's actual tooling.

**Why this didn't surface earlier in the same session:** unresolved.
The Wave 1/C2 probe (`b9e4bc48-...`) and Wave 2/C3 probe
(`189db290-...`) both succeeded earlier in this same session using a
flat top-level shape via direct `curl`, not through
`publish-workbook.sh` (which had no wrapping logic until this fix).
Whether the API's requirement changed mid-session, whether those
earlier probes were in fact hand-wrapped and this went unremarked in
the transcript, or some other explanation, was not conclusively
determined. Treat the `b9e4bc48-...`/`189db290-...` evidence rows in
`capability-ledger.md` as correct for what they proved (the element
shapes and referential semantics) but do not assume they demonstrate
the flat top-level shape is POST-able today — re-verify the wire
format specifically before relying on it.

**Fix.** Added `wrap_flat_to_wire()`/`unwrap_wire_to_flat()` to
`scripts/api/publish-workbook.sh`, wired into `post`/`put` (wraps
before sending, via a temp file to avoid `ARG_MAX` limits on large
specs) and `get-spec` (unwraps after receiving). The flat shape stays
the one authoring convention across every example, validator, and doc
in this skill — the wrapping is invisible to normal use. Documented in
`reference/specification/schema.md` → "Wire format — the live API
wraps the document under a `document` key". Did **not** carry over the
test sub-agent's dual-format (`extract_field`/`is_success`) response
parsing — it solves a problem that doesn't exist on this skill's real
`sigma_curl`-based call path.

**Verification.** `bash -n` clean on the edited script. End-to-end
tested against a real exemplar
(`examples/dashboard-department-scorecard.json`, POSTed to the "Claude
Testing" folder under a scratch name) through the actual fixed
`publish-workbook.sh post` — this surfaced two more real,
previously-latent bugs in that exemplar (see next entry), independent
of the wrapper fix itself, which is what end-to-end testing an
exemplar that had never actually been POSTed before was for.

## 2026-08-04 — two real bugs found in `dashboard-department-scorecard.json` via its first-ever live POST

The Wave 0/CW "dashboard tier" exemplar had been locally validated
(`validate-spec.py`, all checks passing) but never actually POSTed to
the live API before the document-wrapper end-to-end test above. Two
independent, real bugs surfaced:

**Bug 1 — `text` vs `body` on the `text` element.** `txt-hero-title`
used `"text": "<h2>Department Scorecard</h2>"`; the correct field is
`"body": "## Department Scorecard"` (Markdown, not raw inline HTML —
see `reference/specification/text.md` for the inline-HTML allowlist).
This is the exact bug class caught in this session's own Wave 1/C2
probe first draft, but that catch was never checked back against this
already-committed exemplar since the exemplar itself had never been
POSTed. Fixed directly.

**Bug 2 — invalid `orientation: "vertical"` on the bar-chart.**
`chart-rev-by-region` set `"orientation": "vertical"`, which POSTed as
`"document.pages[0].elements[5]: Invalid kind: \"bar-chart\""` — a
misleading error that reads like the `kind` itself is rejected rather
than naming the actual problem. Bisected against the live OpenAPI
schema (`curl -sf https://help.sigmacomputing.com/openapi/sigma-computing-public-rest-api.json`,
`components.schemas.CommonElement.oneOf[0].oneOf[2]`): `orientation`'s
enum is `["horizontal"]` **only** — there is no `"vertical"` value at
all. Setting it to a string outside the enum fails the whole element's
`oneOf` discriminator match, which is why the error names `kind`
instead of `orientation`. Vertical is the default and can only be
reached by omitting the field.

Root cause: `reference/conventions.md`'s "Bar-chart orientation" section
still said `orientation: "horizontal" | "vertical"` (default vertical)
— directly contradicting `reference/specification/charts.md`'s already-
correct rule (`"vertical"` rejected at POST, verified 2026-07-02) in the
same skill. The stale claim in `conventions.md` is the most likely
reason `"vertical"` ended up hardcoded in this exemplar in the first
place. Since the exemplar's `chart-rev-by-region` is exactly the
categorical-axis-with-descending-sort case `charts.md`'s own rule table
calls for `orientation: "horizontal"` (not omitted), the fix sets it to
`"horizontal"` rather than just deleting the field.

**Fix.** Corrected both fields in
`examples/dashboard-department-scorecard.json`. Fixed the stale
`conventions.md` claim to match `charts.md`. Also caught and fixed a
second, unrelated documentation error while cross-referencing the live
schema: `charts.md` claimed the percent-stacked `stacking` value was
`"100"`; the live schema's enum is `"none"` | `"stacked"` | `"normalized"`
— no `"100"` value exists. Fixed.

**Verification.** Re-POSTed the fully-corrected exemplar end-to-end
(`validate-spec.py`: 16/16 clean; live POST via `publish-workbook.sh`)
— progressed cleanly past both fixed fields, and failed only on the
expected, out-of-scope placeholder UUID (`<data-model-id>`) on the
hidden data-source page, which every example in this skill uses as a
deliberate stand-in for a real data-model ID substituted at build time.

## 2026-08-04 — `find-file-by-urlid.sh` didn't handle a pasted full workbook URL

Flagged by the second Wave 2 test sub-agent: pasting a full Sigma
workbook URL (as a user naturally would, e.g. after copying it from
the browser address bar) returned `null` instead of the file metadata.
Root-caused via a live `/v2/files` lookup: the API's actual `urlId`
field is only the short trailing token (e.g.
`3R528WqcM6uEqxWIaJe6sN`), but Sigma's address bar shows a
human-readable slug prepended to that same token (e.g.
`Marketing-Control-Center-Analytics-and-Application-vREL-3R528WqcM6uEqxWIaJe6sN`,
confirmed against the real Marketing Control Center workbook,
`7eb36f00-5c3b-4471-861d-e8b679cab731`) — the script compared the
entire pasted string against each entry's urlId verbatim, so anything
beyond the bare token matched nothing.

**Fix.** `find-file-by-urlid.sh` now takes the URL's last path segment
(if given a full URL) and splits off everything before the last
hyphen. A genuine bare `urlId` has no hyphens, so this is a no-op for
that case. Verified against all three input forms — full pasted URL,
bare pretty slug with no URL wrapper, and bare short urlId (regression
check) — all three now resolve to the same, correct entry.

## 2026-08-04 — second peer report: 1 confirmed, 2 refuted (again), 2 more refuted, 1 real docs gap found independently

The same Wave 2 test sub-agent (task `addf650c9024688e2`, closing out
its session) relayed a fuller bug report via `SendMessage` after the
fixes above already landed. Per this skill's own doctrine, every claim
was independently re-tested rather than merged on the strength of the
report — several directly repeated or extended claims already handled
above, and two were new enough to warrant a fresh live probe before
writing anything into the reference docs.

**Already handled, no new action:**
- Document wrapper (claim re-stated) — already confirmed and fixed
  above; the peer's own fix sat uncommitted in its worktree and was
  not merged (this session's own implementation was kept).
- `find-file-by-urlid.sh` bare-urlId-only matching (claim re-stated)
  — already fixed above, before this report arrived.
- A heredoc-vs-`-c` stdin bug in the peer's own fix for the wrapper —
  a bug in that fix, not in this session's implementation, which
  already used `python3 -c` for exactly this reason. No action needed.

**Re-refuted with fresh, decisive evidence:** the plain-text
(non-JSON) success-response claim. Rather than rely on the earlier
GET/POST spot-check, ran a genuine fresh POST of a guaranteed-valid
minimal spec through the actual fixed `publish-workbook.sh` and
hex-dumped the raw response: `{"success":true,"workbookId":"31ee1f92-
55d3-45e1-9fd4-2a5c2905d9fb"}` — clean JSON, no plain-text framing, on
an authentic 2xx success via this skill's real call path. Two
independent agent sessions have now reported this claim; both times it
traced to a raw `curl` call (the reporting agent's own ad-hoc test)
that omitted `Accept: application/json`, not to a property of the API
itself.

**Refuted via new, targeted live probes (not previously tested):**

- *Cross-page forward references.* Claim: a page-1 element sourcing a
  hidden page-2 table fails with "Dependency not found" unless the
  source page is declared first in `pages[]`. Built a 2-page probe
  with a real, working data-model source (`3889b3c3-4657-4d9e-b568-
  5d2388cf4b4c` / `GwiskXBx0S`, reused from
  `data-model-sourced-single-page-inventory-health.json` rather than a
  placeholder, so a real dependency-resolution failure couldn't hide
  behind an unrelated "connection not found" error) with the
  *referencing* page declared first and the *source* page declared
  second — the opposite of the claimed working order. **POSTed clean**
  (`workbookId: bbd00e1d-a989-418c-b1ee-bd4e2f3867f5`). `pages[]`
  order does not affect cross-page reference resolution.

- *Table `sort` rejected alongside `groupings`.* Claim: a table-level
  `sort` referencing a column used in a grouping's calculations is
  rejected with "Sort column not found" even when the column exists in
  `columns[]`. Already directly contradicted by evidence already in
  hand: `dashboard-department-scorecard.json`'s `tbl-top-stores` has
  both `groupings` (categorize on `tts-store`/`tts-region`) and `sort`
  (`{columnId: "tts-revenue", direction: "descending"}`, `tts-revenue`
  also appearing in `summary`) together, and this exact table POSTed
  successfully as part of the full corrected exemplar's end-to-end
  test earlier in this same session. No new probe needed — this
  combination is already live-verified working.

**Not independently verified — left as an open, unverified caution:**
DM-internal RLS helper columns (a `CurrentUserAttributeText`-backed
column and its dependent boolean) reportedly not cross-element-
referenceable from a workbook table, even when named at the DM level.
Plausible given how Sigma's RLS mechanics work, but reproducing it
requires a real RLS-backed data model this session doesn't have
recon on. Added to `reference/capability-ledger.md` → "Unverified —
probe pending" rather than asserted as fact either way.

**Not from the peer report — an independent finding made while
checking one of its side-comments.** The peer mentioned in passing
that the OpenAPI URL in `schema.md`/`crud.md` "404s now" and guessed
the replacement was "a content-hash path off help.sigmacomputing.com/
reference" — the guess could not be verified and is not repeated
anywhere. But the underlying observation (the URL is dead) checked
out: `curl -I` on the documented URL returns a genuine `HTTP 404`.
Traced further than the peer did: Sigma's docs site now serves an
"Available APIs" index at `https://help.sigmacomputing.com/openapi.json`
listing exactly two bundles (`openapi/sigma-rest-api.json`,
`openapi/code-representation.json`), and **neither contains the
workbook-spec element-kind schemas** (`BarChart`, `KpiChart`,
`CommonElement`, etc.) this skill's per-element `jq` recipes rely on —
confirmed by fetching both and grepping for `"bar-chart"` (zero
matches in either) and for element-schema names. This is a real gap in
Sigma's currently-published docs, not a wrong-URL problem to solve.
Documented in `reference/specification/schema.md` → "OpenAPI reference
— known-dead URL" and `reference/workflows/crud.md`, with the fallback
guidance that live-POST bisection (as used minutes earlier in this
same session to nail down the `bar-chart` `orientation`/`stacking`
enums) is now the primary way to resolve workbook-spec field-shape
questions, not a fallback of last resort.

**Retest note:** full 12-example validator regression re-run clean
after every fix in this entry and the prior one (still 12/12 example
files — canonical count is smaller than the historical "12-example"
figure quoted in earlier entries, which included harvested production
workbooks not currently in this repo's own `examples/` directory).

## 2026-08-04 — Wave 3 / C5+C6: input tables + agent surface, live-POST verified

Per this skill's own doctrine, both `input-table` (C5) and `agents[]`+
`chat` (C6) were GET-spec-only until this wave: all 27 harvested
input-table instances and all 4 harvested agent-bearing workbooks were
read confirmation, never authored from scratch and POSTed by this
skill.

**Built one combined probe** (`b7fead6d-504e-48e7-b623-e41576ce8eb5`,
"Claude Testing" folder) exercising both capabilities together, since
C6's most useful pattern — an agent tool writing to an input table — is
the natural connection point between them: a `segmented` manual
control, an `empty`-source input-table with all 6 column shapes
(system ×5, editable text/number/datetime/checkbox, dropdown with
`values`+`pills`, formula), two buttons (`insert-rows` with constant
values, `delete-rows` with a formula `whichRows`), a `chat` element,
and a top-level `agents[]` entry with `dataSources`, `instructions`
using `{{[controlId]}}` interpolation, and one tool whose single step
writes to the input-table via `insert-rows` with `agent-input` values
for the model-supplied fields.

**One real bug hit and fixed before the first successful POST**: the
control used the same string for both its element `id` and its
`controlId` (`"ctrl-region"` for both) — rejected with `Duplicate id`.
This is exactly the documented "control/column ID collision" rule in
`conventions.md`; fixed by giving the element a distinct `id`
(`elem-ctrl-region`) while keeping `controlId: "ctrl-region"`. After
that fix, **the entire combined probe POSTed clean on the first
attempt** — no further bisection needed, unlike Wave 1's layout bugs.

**GET-back confirmed everything round-tripped byte-for-byte**,
including the previously-uncertain shapes:
- The hypothesized agent tool step shape — `{kind:"effect", effect:
  "insert-rows", table, values}`, i.e. exactly a button's effect
  object plus one added sibling key — matched the live API exactly on
  the first attempt.
- `{{[ctrl-region]}}` interpolation inside `agents[].instructions`
  round-tripped unchanged, same mechanism as the Wave 2 modal-header-
  title probe.

**A follow-up PUT to the same workbook added the `linked` input-table
variant** (a real data-model-sourced `table` element as the `from`
target, plus an input-table with `source:{kind:"linked", from:
"tbl-products"}` and a key column). This corrected a harvest-only
claim: `tables.md` previously documented the `key` field as
`"inode-<id>/SKU_NUMBER"` (an inode-prefixed path). Live-POST testing
shows **`key` is just the bare column `id` of the referenced `from`
element's own column** (`"col-sku"` in the probe) — no inode prefix
required. The original harvest's inode-style value was an artifact of
that particular `from` element happening to be a raw data-model
passthrough table with inode-style column IDs, not a required format.

**One GET-back normalization found, documented as a caution, not a
bug**: input-table columns come back reordered by category (editable
columns first, then system columns, then formula columns), not in
submission order. Field content is unaffected — only array position.
Don't diff a re-fetched input-table's `columns` array positionally;
diff by column `id`.

**Fix.** Added `reference/specification/input-tables.md` (split out of
`tables.md`, which now just points to it) and
`reference/specification/agents.md` (new). Extended
`validate-spec.py`'s `action-refs-resolve` check (refactored the
per-effect logic into a shared `_check_effect` helper) to also walk
`agents[].tools[].steps[]` with the same referential checks already
applied to `actions[].effects[]`, and added a new check that
`chat.agentId` resolves to a real `agents[].id` — closing the gap
explicitly flagged when the check first shipped in Wave 2 ("not
`agentId` — no agent-surface chunk yet"). Positive-control tested:
deliberately broke both a `chat.agentId` reference and an agent tool
step's `table` reference, confirmed both caught with clear messages,
then confirmed the full 12-example regression stayed clean (no false
positives from the refactor). Updated `dynamic-values.md` (`agent-input`
and `{{formula}}` in `agents[].instructions` now live-POST verified,
not harvest-only), `actions.md` (agent tool steps confirmed, not
GET-spec-only), and `SKILL.md` (two new required-reading gate rows:
"Editable / writeback build" and "Agent / chat build", plus updated
per-file capability summaries).

**Retest note:** full 12-example validator regression re-run clean
after every fix in this entry.

## 2026-08-04 — Wave 3 real build-mode test: sales dashboard + input-table writeback + `channel-exclusivity` check shipped

A follow-up test session (fresh kickoff → recon → plan → approval → build,
against a real user ask — "Wave 3 Test," a sales performance dashboard with
4 KPIs, a control-driven "pick your dimension/metric" pivot, a region-map
with click-to-modal, an editable input table for per-state notes filtered
live by the clicked state, and three tabbed cohort-analysis sections
(region / customer / product)) deliberately combined this skill's newest
capability waves in one real spec, authored from the chunk text plus a live
GET of an existing, structurally-similar production workbook in this org
(`fe0140e9-3798-4a9a-a30b-03af8ddbc8ef`, the original "wave 1 test" —
reused its header/KPI/map/modal/tabbed-container patterns directly rather
than reinventing them from prose).

**Recon finding, not a bug:** the data model's 5M-row transactions element
(`GwiskXBx0S`) does not pass through `Store State` — only `Store Region` —
confirmed by diffing against the sibling 500M-row element
(`LZxh6NMhnf`), which does carry `Store State`. Pulled it in via `Lookup()`
against a sibling `D_STORE`-sourced table, per `formulas.md`'s verified
dimension-passthrough recipe. Matches the user's own heads-up in the
prompt ("perform lookups to the other dim tables where necessary").

**One real bug found at first POST attempt:** `map-profit-by-state`'s
`color.column` and `label[0].id` both referenced the same column id
(`col-map-profit`) — rejected with `Column 'col-map-profit' is referenced
from both 'color' and 'label'; a column can only be on one channel at a
time`. This is the exact rule `reference/conventions.md` → "Channel
exclusivity" already documented (verified 2026-07-02 against
`exec-scorecard-v2`, 2 POST rejections) — but that check had been flagged
"planned; not yet implemented" since it was formalized. This is the
**second independent real-session recurrence** of the same failure mode,
which crossed this skill's own "promote on 2nd recurrence" threshold —
implemented `validate-spec.py`'s `channel-exclusivity` check (17th check)
rather than filing it as a 3rd occurrence to fix later. Fixed the spec
itself by duplicating the column (`col-map-profit-label`, identical
formula, distinct id) — the documented fix pattern.

The new check walks a per-element-kind channel-field map (`bar-chart`/
`line-chart`/`area-chart`/`combo-chart`/`scatter-chart`: `xAxis`, `yAxis`,
`color`, `size`; `pie-chart`/`donut-chart`: `value`, `color`, `holeValue`;
`region-map`/`point-map`/`geography-map`: region-binding field(s), `color`,
`size` (point-map only), `label`, `tooltip`; `kpi-chart`: `value`) and
extracts column id(s) from each channel's value generically (handles the
`{id}`, `{columnId}`, `{columnIds:[...]}`, and `{by, column}` shapes
observed across different element kinds under the same channel name,
plus arrays of `{id}` for `label`/`tooltip`). Flags FAIL when the same
column id appears under 2+ distinct channel names on one element.
Positive-control tested against a minimal deliberately-broken region-map
(caught correctly) and the full 13-example regression plus this session's
own spec (all clean, no false positives).

Second POST succeeded: `workbookId 22bf01a5-1ecc-4257-b9ad-b89e3b1d18c1`,
`verify-workbook.sh` 33/33 elements compiling clean, GET-back round-trip
byte-for-byte confirmed on the map's `on-select` action chain, the
hidden-page control's cross-page `filters` binding, the tabbed-container's
`tabs[]`, the modal page's `type`/`modal` config, and the pivot's
`rowsBy`/`columnsBy`/`values`. `audit-workbook-schema.sh` returned the
expected `INCOMPLETE` (exit 3) — this org's OAuth client still lacks MCP
scope, the same documented gap from every prior wave's test session, not a
new failure.

**No browser-based visual verification performed by this agent** — this
test session had no browser/screenshot tool available. All verification
was via `validate-spec.py`, live POST/GET round-trip diffing, and
`verify-workbook.sh`'s compiled-SQL check; the workbook URL was handed
back for the user to open directly. **This gap was not theoretical** —
see the follow-up below: the user opened the workbook and immediately
caught a real bug none of the automated checks had.

**Retest note:** full 13-example validator regression re-run clean after
the `channel-exclusivity` check shipped (13/13, no new false positives),
plus the deliberately-broken minimal region-map fixture (correctly
flagged FAIL).

### Follow-up, same day — `Percentile` is not a real Sigma function (hallucination, same class as `DivideSafe`)

The user opened the workbook and reported: "the aov bucket calculation is
returning reference to errored column." `tbl-customer-cohort`'s `AOV
Bucket` column referenced two `summary` columns (`AOV P33`/`AOV P67`)
computed via `Percentile([AOV], 0.33)` — a function this skill's own
`formulas.md` listed in its aggregation-functions table, but which **does
not exist in Sigma**.

**First fix attempt was wrong and was reverted at the user's explicit
instruction.** The initial hypothesis — that `summary` requires the
parent table to also have `groupings` (the table had `summary` but no
`groupings` at all) — was plausible from `conventions.md`'s documented
"Summary-bar pattern," and was promoted into `conventions.md` and
`tables.md` with a worked wrong/right example. The user reported the fix
did not work and correctly identified the real cause ("unknown percentile
calculations"). Both doc edits were reverted in full (`tables.md` fully
reverted via `git restore`; `conventions.md` had the retracted paragraph
manually removed, keeping the unrelated-and-still-valid
`channel-exclusivity` edit from earlier in the same session intact).

**Actual root cause, confirmed by reading the raw compiled SQL directly**
(`GET /v2/workbooks/{id}/elements/tbl-customer-cohort/query` — not just
`verify-workbook.sh`'s narrow marker check, which reported this element
clean both before and after the real fix): the compiled SQL contained the
literal string `'Unknown function Percentile'`, and the downstream `AOV
Bucket` column's own error ("reference to errored column") was a pure
cascade from referencing the broken `AOV P33`/`AOV P67` columns — nothing
to do with `groupings` at all. Confirmed via `WebSearch`/`WebFetch`
against `help.sigmacomputing.com` that the real functions are
`PercentileCont`/`PercentileDisc` (same argument order:
`PercentileCont([col], k)`). Renaming fixed it — reconfirmed by re-pulling
the raw compiled SQL, which now shows a real `percentile_cont(...) within
group (...)` expression and no error-string markers anywhere, on both
`tbl-customer-cohort` and the downstream `pivot-customer-cohort`.

**Why nothing in the pipeline caught this the first time:** `validate-spec.py`
only checks spec *shape*, not formula semantics. `verify-workbook.sh`
greps compiled SQL for exactly two markers ("Unknown column", "Circular
column reference") — a nonexistent function name compiles to a *third*,
different literal (`'Unknown function <Name>'`), which the script's grep
doesn't match, so it reported this element clean on both the broken and
fixed versions. Only reading the raw `sql` field directly, or a human
opening the workbook, surfaces it.

**Fix.** Corrected `formulas.md`'s aggregation-functions table
(`Percentile` → `PercentileCont`/`PercentileDisc`, with a hallucination
warning matching the existing `DivideSafe` callout's format) and added a
troubleshooting note under "When the formula fails at render" describing
this exact failure class and the raw-compiled-SQL workaround.
Deliberately did **not** extend `verify-workbook.sh`'s grep patterns this
session — this is the first confirmed occurrence of this specific gap
(unlike `channel-exclusivity` above, which was a second recurrence), and
the user was actively waiting on the real fix; flagging the gap here as a
well-evidenced candidate for a future pass rather than shipping a second
speculative change in the same session.

### Second follow-up, same day — a "confirmed fixed" claim was itself wrong (verification false-positive)

After the `PercentileCont` fix above, this agent PUT the corrected spec,
then immediately fetched the raw compiled SQL for `tbl-customer-cohort`
and saw a real `percentile_cont(...)` expression with no error markers —
and reported the bug fixed on that basis. **That report was wrong.** A
reviewing agent (relaying this session's output) independently re-checked
the same live workbook shortly after and found the stored formula was
still literally `Percentile([AOV], 0.33)` and the compiled SQL still
contained `'Unknown function Percentile'` — i.e. the exact pre-fix state,
despite this agent's fresh-looking verification moments earlier.

Re-investigating found the local spec file on disk already had the
correct `PercentileCont` formula (so the *authoring* was right), but a
fresh `get-spec` + fresh raw `query` call, done again from scratch, also
showed the live workbook still broken at that point — confirming the
reviewing agent's finding, not just taking its word for it. Re-running
the PUT → verify sequence a second time, with an explicit timestamp
logged before and after every mutating and reading call, produced
internally consistent evidence: `get-meta`'s `latestVersion` incremented
(4 → 5) with `updatedAt` matching the new PUT's timestamp to the second,
and both the fresh `get-spec` and fresh raw `query` calls made *after*
that specific PUT showed the corrected formula and clean compiled SQL.

**The exact mechanism behind the first false-positive was not
conclusively identified** — candidates include a stale/misattributed
local response, a PUT that silently didn't include the intended change,
or some transient inconsistency, but none was confirmed. What's
notable and worth carrying forward regardless of mechanism: **this
agent's own single post-PUT verification pass (PUT, then immediately
re-fetch and check) produced a confident, wrong "fixed" claim once
already in this same session** — for a bug class (`verify-workbook.sh`
blind to it) where the checking agent had already established that the
automated pipeline can't be trusted alone. The practical lesson: treat
one fresh-looking check after a mutation as good evidence, but not
infallible — a second independent check, or a short delay before the
"final" verification, would have caught this sooner. This is a process
gap in how this skill's agents self-verify fixes, not a Sigma platform
behavior — no fix is proposed to any script over it in this session;
noted here as a caution for future sessions relying on "I checked and
it's clean" as sufficient grounds to report a fix as done.

## 2026-08-04 — Wave 4 / C7: visual media + theming, live-POST verified, 2 real field-shape bugs found

Per this skill's own doctrine, `image`, container `backgroundImage`,
`themeOverrides`, and the `{kind:"theme", ref}` color form were
GET-spec-only until this wave — every prior claim came from reading
harvested production workbooks, never authoring one from scratch and
POSTing it.

**Built a combined probe** (`b77b5b05-d1f5-40ba-96eb-00458726da29`,
"Claude Testing" folder): a segmented control, an `image` element with
a `{{formula}}` URL referencing that control, a second `image` element
with an inline `data:image/svg+xml;base64,...` icon, a `container`
with both `backgroundImage` and a `style.borderColor` set to a
theme-color reference, and top-level `themeOverrides`
(`pageWidth`/`space`).

**First POST attempt rejected**, `Invalid kind: "image"` — the same
misleading error class as the Wave 3 bar-chart `orientation` bug
(inner shape wrong, not the kind itself). Pulled the live OpenAPI
schema directly (`CommonElement` discriminated by `enum:["image"]`)
rather than guessing: the real shape is `{id, kind, source:
{kind:"url", url}}` (or `{kind:"upload", key}` for a reference to an
image already uploaded into Sigma — GET/PUT-only, the spec cannot
upload a new one). Every version of `others.md` prior to this wave —
and every harvested workbook this skill had read — showed a flat
top-level `url` field instead. This is a real, previously-undocumented
bug that would have hard-failed any build using an `image` element,
not just a documentation gap.

**Same bug, same fix, on `backgroundImage`.** After correcting the
`image` elements, the next rejection was `backgroundImage.source:
Invalid value: undefined` — `containers.md` had the identical flat-`url`
bug on `backgroundImage`. Same fix: `backgroundImage.source:
{kind:"url", url}`.

**A false claim caught and retracted: `theme` is not a standalone
element kind.** The next rejection was `Invalid kind: "theme"` on a
`{kind:"theme", ref:"colors-textNeutral"}` element — `schema.md` had
documented this (from harvest evidence in `sales-mbr-sentinel`) as a
page element in its own right. Searching the OpenAPI for an exact
`enum:["theme"]` discriminator match, scoped to `CommonElement`, found
no such standalone element — instead, `{kind:"theme", ref}` appears
repeatedly as a `oneOf` alternative *inside color-typed fields*
(`style.color`, `style.borderColor`, `style.backgroundColor`,
`name.color`, `description.color`, `sparkline.color`, and the
`tableStyles`/`themeOverrides` color fields) across many element kinds.
The original harvest almost certainly misread one of these nested
color-reference objects as if it were a top-level element. Corrected
the probe to use it as `container.style.borderColor` instead — POSTed
and round-tripped clean.

**Second POST succeeded** after all three fixes. GET-back confirmed
every shape round-tripped byte-for-byte: both `image` variants
(`{{formula}}` URL and inline SVG), `backgroundImage.source` +
`backgroundImage.style`, `container.style.borderColor` as a theme
color reference, and top-level `themeOverrides`.

**Resolved a previously-open question**, flagged in
`capability-ledger.md` → "Unresolved contradictions" since planning: a
third-party fork had claimed inline `data:image/svg+xml` data URIs get
WAF-403'd on POST. **Not observed** — the exact same `source.url`
field that accepts a hosted HTTPS URL also accepted the inline SVG data
URI with no rejection, at any point in this probe.

**Bonus find while documenting `themeOverrides`:** the live OpenAPI
schema shows 16 top-level fields, not the 2 (`pageWidth`, `space`)
previously documented — including `borderRadius`, `hasCards`,
`invertTooltipColors`, `categoricalScheme`/`sequentialScheme`/
`divergingScheme`, `colorOverrides`, `elementBorder`, `tableStyles`
(workbook-wide table defaults, same shape family as a per-table
`tableStyle`), `fonts`, `titleFont`. Cataloged all 16 with type/enum
from the schema; only `pageWidth`/`space` are live-POST verified — the
rest are flagged as schema-confirmed-present but individually unprobed.

**Fix.** Corrected `others.md` → "Image" and `containers.md` →
"backgroundImage" (flat `url` → `source:{kind:"url"|"upload"}`).
Replaced `schema.md`'s wrong "theme element kind" section with a
pointer to a new `reference/specification/theming.md`, which documents
`themeOverrides` (all 16 fields) and the corrected `{kind:"theme",
ref}` color-value form. Renamed the `SKILL.md` gate row
"Container-styling-heavy build" → "Styling / theming build" per the
original plan (zero net new rows). Updated `capability-ledger.md`:
moved `image`/`backgroundImage`/theme-color-reference from GET-spec-only
to POST-verified, and removed the now-resolved inline-SVG-WAF-403
"probe pending" row.

**Retest note:** full 13-example validator regression re-run clean
after every fix in this entry.

## 2026-08-04 — Wave 4 / C8: scenario modeling pattern, 2 structural gotchas checked

Per the plan, scenario/forecasting is deliberately **not** a
`specification/` chunk — it's a composition of already-verified
primitives (parameter controls, input-table writeback, multi-series
line charts), filed under a new `reference/patterns/` directory so it
doesn't read as a dedicated Sigma feature (the same hallucination
shape the `DivideSafe` incident warns against).

**Confirmed real:** `CallVariant` — the forecasting mechanism's core
function — via Sigma's own function docs (`CallVariant(functionName,
arg1, ...)`, calls a warehouse UDF returning a `Variant`). The specific
UDF example from harvest evidence (`SNOWPARK_UDF.AUTO_TIMESERIES_MODEL`)
and its `.Prediction`/`.Lower_CI`/`.Upper_CI` accessor names remain
harvest-only — this session had no real forecasting UDF available to
test against, and those accessor names are almost certainly
UDF-specific, not a Sigma convention.

**Structural gotcha #1, partially confirmed:** live-POSTed a control
with `filters[]` targeting a real input-table (reusing the Wave 3
probe workbook). **The spec accepts it outright** — clean POST,
byte-for-byte GET-back, no rejection or stripping. This means the
millersigma claim ("controls cannot filter input tables or pivots") is
not a POST-time validation rule; this skill has not independently
confirmed the other half of the claim (that the filter is a silent
functional no-op in the rendered UI), since that requires visual
inspection this session has no tool for. Documented as
partially-confirmed, with the practical guidance (bind to a derived
normal table instead) stated as a precaution, not a proven requirement.

**Structural gotcha #2, confirmed at the schema level:** inspected the
live OpenAPI's complete field list for the `input-table` element kind
— `id`, `kind`, `source`, `inputMode`, `name`, `description`, `style`,
`noDataText`, `tableComponents`, `tableStyle`, `columns`,
`conditionalFormats`, `summary`, `sort`, `filters`. **No field exists
anywhere for seed/initial row data** — the only ways rows enter an
input table are user entry or the `insert-rows` effect. This
structurally confirms the "input-table rows cannot be seeded from
code" claim rather than just repeating it from harvest.

**Fix.** Added `reference/patterns/scenario-modeling.md`, citing the
already-verified primitive chunk for each piece (`formulas.md` for
`CallVariant`, `controls.md` for parameter controls,
`input-tables.md`/`actions.md` for writeback, `charts.md` for the
confidence-band line chart), and clearly separating what this wave
confirmed from what remains harvest-only. Added the "Scenario /
what-if / forecast build" gate row to `SKILL.md`.

**C9-b (plugin packaging/publish) deliberately deferred, not
forgotten.** The plan's remaining item — moving `scripts/` and
`.claude/skills/` into a `plugins/sigma-workbooks/` tree, adding
`.claude-plugin/{plugin.json,marketplace.json}`, and re-pathing every
reference to the moved files — was scoped and ready, but is a
full-repo restructure with a much larger blast radius than anything
else in Wave 4: it touches nearly every file in the project and would
have run while a Wave 3 test session's worktree was still active on
the old layout. Asked the user directly rather than executing it
silently; they chose to defer it to its own dedicated session once
other in-flight work is closed out. Wave 4 is otherwise complete
(C7 + C8 shipped, live-POST verified where the underlying capability
allowed it).

## 2026-08-07 — MCP access confirmed blocked for client_credentials tokens; not a per-org scope gap

A capability-expansion follow-up session diagnosed "the MCP wrapper
scripts are seemingly broken" starting from a live, reproducible 403:
`mcp-search.sh`/`mcp-describe.sh` calling `/mcp/v2` with this skill's
usual `client_credentials`-derived bearer token got
`{"error":{"code":"EACCES","errorCode":"permission_denied","message":"Missing
required scopes: mcp:access"}}` on every call. REST calls with the same
token worked fine — the rejection was specific to `/mcp/v2`.

**Ruled out: stale credentials.** The org rotated the API client's
key/secret pair mid-session; after clearing the local token cache and
confirming (via `whoami.sh` and a differing `requestId` on the retried
MCP call) that this was a genuinely fresh, non-cached call, the *exact
same* 403/`mcp:access` error reproduced with the new key. A new key from
the same client type hits the same wall — this is not a rotted secret.

**Root cause, confirmed by Sigma's own MCP engineering team (asked
directly, not inferred from docs):** `/mcp/v2`'s only supported
customer-facing auth path today is interactive user OAuth, not REST
API/`client_credentials` tokens. Change #37939 (2026-07-30) removed a
gate (`USE_AUTH_SCOPE_CHECK`) that had been letting legacy API tokens
without `mcp:access` through; that path "worked" during a pre-OAuth
testing phase but was never officially supported, and now correctly
403s. Dedicated API-key/client-credentials MCP support is "intended/in
progress" on Sigma's side, likely via a dedicated MCP scope rather than
reusing the REST API scope — no ETA given. The team's guidance for
portable skills today: use the org-specific Sigma MCP URL from
Profile → Integrations with the OAuth flow; if OAuth still 403s, check
the user's account type has "Use Sigma MCP with OAuth."

**This is not a per-org misconfiguration** — it affects every
installation of this skill using its documented `.env`/`client_credentials`
auth model (CLAUDE.md → "Authentication"), permanently, until Sigma
ships the dedicated scope. Sigma's public docs are consistent with this:
pages covering MCP access always describe it via an account-type
permission granted through interactive login; pages covering API/OAuth
clients (`configure-a-sigma-oauth-application`,
`configure-oauth-with-write-access`) never mention MCP or `mcp:access`
at all.

**Two smaller, real bugs found during the same diagnostic:**
1. `mcp-search.sh` had no exception handling around its MCP call and
   crashed with a raw `urllib.error.HTTPError` traceback on any
   transport failure. `mcp-describe.sh` got the equivalent fix in Wave 0
   (2026-08-03, this same failure class) but it was never ported to
   `mcp-search.sh`. Fixed to match: catches `HTTPError`/`URLError`,
   exits 3, explains the likely cause and points at `search-files.sh`.
2. `_env.sh`'s repo-root resolution (`dirname "${BASH_SOURCE[0]}")/../..`)
   silently computes a wrong, too-shallow root when `BASH_SOURCE[0]` is
   empty — which happens when the file is `source`d from a non-bash
   shell (e.g. zsh, the macOS/many-Linux-distro default login shell)
   instead of from inside a bash script. Found by accident while
   sourcing `_env.sh` directly to get `sigma_curl` for an ad hoc probe;
   not reachable through any documented usage pattern (every documented
   call goes through `bash scripts/api/<name>.sh`, which guarantees a
   bash context), but a real trap for anyone doing the same. Fixed to
   fail loudly instead of silently walking to the wrong directory.

**Fix.** Added `scripts/api/search-files.sh` — REST-based (`/v2/files`
with repeated `typeFilters` params, confirmed live: a comma-joined value
400s with "Expecting Array<...> at typeFilters.0"), substring not
semantic, no `url` field (not present on `/v2/files` entries) — as the
default discovery-by-name tool, promoted from a documentation gap (no
REST equivalent existed for "find a workbook/data model by name," only
for connections/columns/folders/schema-probing) to a real script.
Rewrote `reference/workflows/discover.md` to lead with REST and state
the MCP-blocked status plainly rather than framing MCP as "preferred,
covers ~90%"; `SKILL.md`, `sources.md`, and `CLAUDE.md` updated to
match. The MCP sections of `discover.md` are kept, not deleted — for
if/when Sigma ships client-credentials MCP support.

**Not built:** an interactive user-OAuth flow so this skill's own
scripts could reach `/mcp/v2` today. Sigma's team says dedicated
client-credentials support is in progress; a heavy, browser-dependent
OAuth flow now risks being thrown away, and cuts against this skill's
headless/same-code-path-CLI-and-web design goal (CLAUDE.md →
"Authentication"). Revisit if/when that scope ships.

## 2026-08-07 (continued) — data-model-first discovery framing + raw-table routing cost data

Two follow-up live tests (background sub-agents, same session as the MCP
block above) quantified the actual cost of REST-only discovery instead
of guessing:

**Test 1 — data model vs. raw table richness.** `GET
/v2/dataModels/{id}/spec` on the real "PLUGS Data Model vREL"
(`3889b3c3-4657-4d9e-b568-5d2388cf4b4c`) returned 28.9KB, 8 elements, 117
columns, **28 metrics** — friendly names, descriptions, and metric
formulas all inline, in one call, matching MCP `describe`'s depth
exactly. `list-table-columns.sh` on a real warehouse table (D_STORE, in
the "Big Buys" data model's underlying `SE_DEMO_DB.BIG_BUYS` schema)
returned only raw names (`STORE_KEY`, `STORE_NAME`, ...) — no
descriptions, no metrics, unrecoverable via REST without a data model to
borrow friendly names from.

**Test 2 — does naming specific tables beat schema-level probing?** No,
not unless the schema is also confirmed. Given 3 table names
(`F_POINT_OF_SALE`, `F_SALES`, `D_PRODUCT`) without a stated schema:
`find-file-by-urlid.sh` returned null on all 3 (warehouse tables aren't
a `/v2/files` type — confirmed, not assumed). `D_PRODUCT` resolved in 2
calls once the correct schema (`BIG_BUYS`) was known. `F_SALES` and
`F_POINT_OF_SALE` did not exist under `BIG_BUYS`; chasing them across
guessed sibling schemas cost **29 calls with zero hits** — worse than a
schema-only probing run from the same investigation, which found 3/3
real tables in 11 guessed calls. Naming tables without a known schema is
not a shortcut; it's a worse strategy than schema-level probing.

**Bonus finding:** `discover.md` claimed `/s/<id>`/`/t/<id>` schema URL
slugs are flatly "not reversible via Sigma's public API." Tested live:
there IS a real endpoint (`/v2/connections/paths`, already wired into
`scripts/sigma-resolve.py`'s `find_path_by_urlid`) that reverses them —
but it's a full org-wide paginated enumeration (4,225+ entries and still
paginating in one run, one unthrottled retry hit a 429). Technically
reversible, practically useless for a single lookup. The doc's
conclusion (ask the user instead) was right for the wrong stated reason;
corrected to name the real one.

**Fix.** Added `discover.md` → "Prefer data models over raw tables"
(cites the Test 1 numbers) and → "Routing: raw warehouse tables" (a
3-way split: table+confirmed-schema → straight to `lookup-path.sh`, no
probing; table without confirmed schema → **ask the user, don't
guess-cascade**; schema-only → `probe-schema-tables.sh` as before).
Corrected the "not reversible" claim in two spots to name the org-wide
enumeration cost instead. Mirrored the schema-confirmation requirement
into `SKILL.md`'s Q2 kickoff question, and fixed two stale
`mcp-describe.sh`-as-default references inside `SKILL.md` itself (the
kickoff worked example, and the "Data inventory" plan-checklist item)
that this same sweep surfaced.

**Not fixed, flagged for the dedicated contradiction-review pass
instead:** the same grep sweep found `mcp-search.sh`/`mcp-describe.sh`
still presented as the default (not a blocked path) in
`reference/conventions.md`, `reference/workflows/plan.md`,
`reference/workflows/validate.md`, `reference/specification/{schema,
controls,formulas}.md`, `reference/capability-ledger.md`,
`docs/iteration-playbook.md`, and one `examples/*.prompt.md` file.
Fixing all of those was judged out of scope for this specific ask (data-
model-first framing + schema confirmation) — bundling an unbounded sweep
into a narrowly-scoped change is exactly the kind of ad hoc partial fix
that creates fresh inconsistency instead of resolving it. Left for the
skill's own planned full contradiction review.

## 2026-08-08 — Full contradiction review: a real KPI bug in 5 examples, plus doc drift across ~20 files

The deferred "full contradiction review" ran as 4 parallel sub-agents
(stale-MCP sweep, cross-file rule-duplication sweep, file-placement
audit, examples-vs-conventions sweep), each independently verified
before acting — several claims were spot-checked directly (structural
JSON parse, live grep, header lookup) rather than relayed as-is.

**Real bug, not just doc drift — 20 KPIs across 5 non-deprecated
examples used the pre-fix `value:{"id":...}` shape** instead of
`value:{"columnId":...}` (`kpis.md`'s own rule: `value.id` "will be
silently ignored or rejected"). `data-model-sourced-cohort-pivot.json`
and `styled-card-dashboard.json` are both named elsewhere in the skill
as *the* canonical clone target for their pattern. Fixed via a
format-preserving, kind-scoped substitution — critically, a first
attempt using a blind text-pattern match found 23 matches, not the
expected 20; investigating the discrepancy surfaced that `donut-chart`
and `pie-chart` elements legitimately use `value:{"id":...}` too (a
different, correct shape — they reference locally-declared `columns[]`
entries by `id`, same as every OTHER chart kind; `kpi-chart` is the
one exception requiring `columnId`). A blind regex would have
"fixed" 20 real bugs while introducing 3 new ones. Rewrote the fix to
walk the JSON structurally and scope the substitution to confirmed
`kpi-chart` elements only, verified via a fresh structural re-parse
post-fix (all `kpi-chart` → `columnId`, all `donut-chart` → `id`
untouched) and a full `validate-spec.py` pass (0 fail across all 13
examples, pre-existing warnings unchanged).

**Doc contradictions fixed:**
- `text.md` claimed `<u>/<sub>/<sup>/<a>` was "the **complete**"
  allowed-inline-HTML-tag set, then in the same sentence quoted a live
  rejection error listing `<span>` as allowed too — and the file's own
  next section documents `<span style="color...">` as supported.
  Corrected the "complete" list to include `<span>`.
- `kpis.md`'s "Known limitations" claimed no delta/comparison field
  exists on the KPI element; `dashboard-department-scorecard.json`
  uses `timeline`+`periodComparison` for exactly this, verified live
  (grabbed the real field values from the example) and already noted
  elsewhere in this file as "verified ~67 times." Retracted the false
  limitation, added a "Period-over-period comparison" section
  documenting the real shape. `reference/scope-and-edge-cases.md` and
  `SKILL.md` both repeated the same false claim — fixed both to match.
- `pages.md`'s `modal.width: "large"` entry deferred to "`agents.md`-
  adjacent findings once that chunk exists" — `agents.md` has existed
  since Wave 3 (2026-08-04) and contains no such content. Corrected to
  flag `"large"` as unverified rather than pointing at a citation that
  doesn't exist.
- `tables.md`'s intro still described covering `input-table`, moved to
  `input-tables.md` on 2026-08-04 (the file's own TOC already knew this
  — only the intro paragraph was stale).

**Stale MCP-as-default references (Wave 1 of this finding, 2026-08-07,
only covered `discover.md`/`SKILL.md`/`sources.md`) — extended to 9
more files** this session: `conventions.md`, `plan.md`, `validate.md`,
`schema.md`, `controls.md`, `formulas.md`, `capability-ledger.md`,
`sources-warehouse.md`, one exemplar `.prompt.md`, and
`docs/iteration-playbook.md`'s default Recon step (the single most
operationally significant one — it's the primary per-attempt protocol
every build follows). All now lead with the REST call and mention
`mcp-describe.sh`/`mcp-search.sh` only as an "opportunistically try,
expect exit 3" aside, matching `discover.md`'s established pattern.

**Duplication collapsed to single sources of truth** (the same failure
class as the 2026-08-03 "4-place gate-row duplication" fix, just not
generalized to these other tables at the time): `SKILL.md`'s "Plan
content" and "Approval model" sections fully restated `plan.md`'s
content instead of pointing to it — and had already drifted on the
"Data inventory" step (one said `mcp-describe.sh`, the other said
REST) before this session's MCP-staleness fixes even landed, direct
proof the duplication is a real, live risk, not a hypothetical one.
Trimmed both `SKILL.md` sections to summaries + pointers, matching the
"insurance, not substitutes" framing already used for the adjacent
Load-bearing-rules block. Same treatment for a 9-field response-only-
fields list independently hardcoded in `schema.md`, `crud.md`, and
`docs/iteration-playbook.md` — `schema.md` is now canonical (it also
carries the field's actual on-write behavior, ignored not rejected,
which the other two copies lacked).

**Structural fixes:** `SKILL.md`'s own routing index filed
`reference/patterns/scenario-modeling.md` under the "Specification
files" heading despite the bullet's own text saying it's deliberately
not there — gave `patterns/` its own heading. Fixed "`reference/` is
split into three groups" → "four" to match. Fixed "11 accepted
controlTypes" → "14" (the actual distinct `controlType` string count
per `controls.md`'s own TOC). Added "insurance, not substitutes"
framing to `SKILL.md`'s inline Conventions block, pointing at
`naming.md`/`conventions.md`, matching the pattern already used one
section below it.

**Cosmetic:** stale `../specification/` link-label prefix in `maps.md`;
`evals/` added to `CLAUDE.md`'s Layout section.

**Net effect on `SKILL.md` line count:** 614 (session start) → 599
(item 2, narrative trim) → 546 (this item's Plan-content/Approval-model
trim) → 556 (net, after this item's correctness additions — a few
lines of accurate content is a reasonable trade against a stale or
contradictory claim; not chased further at the expense of correctness).

**Deliberately not fixed, flagged as unbacked/unverifiable within this
session's scope:** the "explicit-name rule / rename-cascade corollary"
check across all examples was attempted but the sub-agent reported it
was too noisy to distinguish real violations from intentional unnamed
drill-down passthrough columns via static analysis alone — would need
render-time verification. Not treated as a finding either way.

## 2026-08-10 — Example-set rationalized around 3 independent complexity axes; 2 real gaps documented

Reviewed the 13-file `examples/` set structurally (element kinds, page
counts, controls, containers extracted programmatically, not just
SKILL.md's descriptions — which item 3 already caught drifting from
reality once this session) rather than assuming the file count itself
was the problem.

**Deleted 2 files, not just relabeled — confirmed genuinely redundant,
not merely overlapping:**
- `data-model-sourced-kpi-overview-with-containers.json` — already
  marked deprecated (pre-fix KPI shape + `controlId` collision), but
  still cited from `reference/specification/layout.md:361` as the
  canonical nested-container example. Verified `styled-card-dashboard.json`
  has the identical outer-section/inner-KPI-row nesting pattern and
  isn't deprecated; redirected the citation there before deleting.
  Keeping a file explicitly marked "do not clone" inside a folder whose
  own stated convention is "known-good specs to seed generation... 
  clone-and-modify" was itself a contradiction worth resolving, not
  just documenting.
- `additional-workbook-features-chart-and-control-catalog.json` — its
  entire teaching value (3 area-chart stacking modes, pie-chart) is
  already fully documented inline in `reference/specification/charts.md`
  with working JSON snippets (confirmed: the stacking values section,
  and "pie chart — same shape as donut"). Not cited anywhere else in
  `reference/`. A whole-workbook exemplar earns its place by teaching
  composition across elements/pages; this one added nothing beyond
  already-required reading.

**Corrected 1 mislabeled description, kept the file:**
`data-model-sourced-multi-level-aggregated-table.json` was described as
a "combo-chart shape reference" — but combo-chart is *also* already
fully documented in `charts.md` (same redundancy pattern as the deleted
file above). Confirmed its real, unique value: a live 3-level
`groupings` table that `reference/specification/tables.md` itself cites
by name (`tables.md`'s own inline example only goes 2 levels). Fixed
the description to match what the file is actually for.

**Restructured `SKILL.md`'s catalog around 3 independent complexity
axes** (page complexity, calculation complexity, writeback complexity)
instead of the prior ad hoc grouping (Minimal/3-page-canonical/
Catalog/Editable/Pattern-specific/Deprecated) — a build can be simple
on one axis and complex on another, and the old grouping conflated
them. Added a light cross-reference from `composition.md`'s sizing
ladder (which is really just the page-complexity axis) to this fuller
map, without rewriting the ladder itself.

**2 real coverage gaps found and documented, not built yet (next
session's work, per user direction — "reorg first, then address the
new examples"):**
- No example demonstrates plain writeback (an editable `input-table`,
  no AI agent) — the only writeback example bundles input-table +
  agent + chat together, forcing anyone who wants basic writeback to
  wade through agent complexity irrelevant to their need.
- No example demonstrates an approval handoff between two users on top
  of scenario modeling (enter params → generate a forecast → a second
  user approves it before it's final). Sketched a composition using
  already-verified primitives only (a `status` column, a filtered
  approver view, direct inline cell editing since there's no
  `update-rows` effect in the verified 9-effect vocabulary) — this
  should not need new capability probing, just live verification of
  the composed shape before it's documented as a working pattern.

Net: 13 → 11 example files. `validate-spec.py` re-run clean on all 11
survivors post-deletion (0 fail; pre-existing warnings on 2 files
unchanged, unrelated to this change).
