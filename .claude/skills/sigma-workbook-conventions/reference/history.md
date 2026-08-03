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
