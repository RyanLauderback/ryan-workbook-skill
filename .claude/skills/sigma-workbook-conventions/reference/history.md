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
