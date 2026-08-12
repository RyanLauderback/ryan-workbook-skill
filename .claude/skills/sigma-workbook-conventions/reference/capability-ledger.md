# Capability ledger

A dated, sourced record of what has actually been verified against a live
Sigma org — in both directions. This file exists because a phantom
limitation (`others.md` → "What about buttons and modals?", retracted
2026-08-03) sat in this skill claiming five working features were
unsupported, for reasons that were never re-tested. The skill's own
doctrine already treats hallucinated capabilities and phantom limitations
as the same class of bug (`reference/history.md` → the `DivideSafe`
incident); this ledger is that doctrine applied specifically to
**"is X supported"** claims, since those are exactly the claims that
steer an agent away from building something that would have worked.

**Every entry below names the workbook(s), the date, and what was
actually checked** (GET-spec HTTP status, a validator pass, or an actual
POST). A claim with no entry here is not yet load-bearing — treat it as
"probably true, unverified," not as settled fact.

## The retest protocol — apply this before adding a new "unsupported" claim anywhere in this skill

1. **Find a reference workbook that appears to use the feature.**
   `scripts/api/search-files.sh "<name>"` / browsing the org, or ask
   the user for one (opportunistically `mcp-search.sh`, expect exit 3
   — see `reference/workflows/discover.md` → "MCP status").
2. **Pull its live shape via the `kind`-discriminator `jq` recipe** against
   a cached OpenAPI spec, or just `GET /v2/workbooks/<id>/spec` and
   inspect the element directly. Do not infer "unsupported" from a single
   malformed POST attempt or a generic `Invalid kind` error — per
   `reference/workflows/validate.md` → "Decoding cryptic validation
   errors," that error almost always means the *inner shape* was wrong
   for the `kind`/`controlType` claimed, not that the kind is rejected.
   A GET-spec 500 on a workbook using several features at once doesn't
   tell you *which* feature broke the serializer.
3. **If GET-spec succeeds (HTTP 200) and the feature's shape is present
   in the response, it is supported.** Record it below with the workbook
   id, date, and what you checked.
4. **Only write "not supported" after step 2 fails on a workbook
   confirmed (by a human, or by working UI behavior) to actually use the
   feature.** Even then, prefer "unverified — probe pending" over a flat
   negative claim unless you have a specific POST rejection message to
   cite.

## Verified supported (positive claims)

All of the following were retracted from an incorrect "not supported"
claim on 2026-08-03 (see `reference/specification/others.md` and
`reference/scope-and-edge-cases.md`). Evidence: clean `GET
/v2/workbooks/<id>/spec` (HTTP 200), full element fidelity, across these
workbooks:

| Feature | Workbooks (id, date checked) | What was checked |
|---|---|---|
| `button` element + `actions[]` | GET-spec: Claims Command Center (`0de447af-35f8-4831-af80-a2ea8eac32a2`), Insurance P4P Analytics (`691fa937-e296-4f88-bc81-afc10bb123ef`), Workbooks Demo 2026 (`9c0cb6a7-f25e-4045-a896-6de9e46a364b`), Marketing Control Center (`7eb36f00-5c3b-4471-861d-e8b679cab731`) — 2026-08-03. **POST-verified**: `189db290-7674-4032-9ff7-7fad59dc14fa` — 2026-08-03 (Wave 2 / C3 probe) | GET-spec 200; `kind:"button"` present with `actions:[{trigger, effects}]`. **Authored from scratch and POSTed** — 8 buttons, one per effect, all round-tripped byte-for-byte. See `actions.md`. |
| `modal` pages (`type:"modal"`) | Claims Command Center (9 modal pages), Workbooks Demo 2026 (1), Marketing Control Center (1) — 2026-08-03 GET-spec; **`b9e4bc48-afa8-4085-b94d-fdd61c06bf0d` — 2026-08-03 POST-verified** | GET-spec 200; `pages[].type:"modal"` + `modal:{width,header,footer}` present. **Authored from scratch and POSTed** (Wave 1 probe) — confirmed the JSON shape round-trips AND discovered the modal page's layout grid is silently normalized to 12 columns (not 24) on GET-back. See `pages.md`. |
| `tabbed-container` | Claims Command Center (5), Marketing Control Center (3), Bergey's Unified Insights (5) — 2026-08-03 GET-spec; **`b9e4bc48-afa8-4085-b94d-fdd61c06bf0d` — 2026-08-03 POST-verified** | GET-spec 200; `kind:"tabbed-container"` + `tabs:[{name}]` present; layout XML confirms `<TabbedContainer>`/`<Tab>` tags. **Authored from scratch and POSTed** — confirmed `<Tab>` has no `elementId` (positional binding to `tabs[]` order) and `<TabbedContainer>` is a direct child of `<Page>`, byte-for-byte round-trip. See `pages.md` + `layout.md` → "Five-tag grammar." |
| `page-break` | Workbooks Demo 2026 — 2026-08-03 GET-spec; **`b9e4bc48-afa8-4085-b94d-fdd61c06bf0d` — 2026-08-03 POST-verified** | GET-spec 200; `kind:"page-break"` present. **Authored from scratch and POSTed** — round-trips with no fields beyond `id`/`kind`. |
| All 9 effects (`set-control-value`, `clear-control`, `open-overlay`, `close-overlay`, `navigate`, `select-tab`, `open-url`, `insert-rows`, `delete-rows`) | GET-spec: all 5 harvested workbooks — 2026-08-03. **POST-verified**: `set-control-value`+`open-overlay` via a real build (`fe0140e9-3798-4a9a-a30b-03af8ddbc8ef`); the other 7 via `189db290-7674-4032-9ff7-7fad59dc14fa` (Wave 2 / C3 probe) — 2026-08-03 | **All 9 authored from scratch and POSTed**, byte-for-byte round-trip. Referential semantics confirmed: `set-control-value.control`/`clear-control.scope.control` = `controlId`; `open-overlay.overlayId`/`navigate.target.page` = page `id`; `select-tab.tabbedContainer` = element `id`, `selectedTab.index` 0-based; `insert-rows`/`delete-rows.table` = input-table element `id`. See `actions.md`. |
| 4 of 5 dynamic-value forms (`constant`, `formula`, `column`, `control`) | Wave 2 / C3 probe — 2026-08-03 | **Authored from scratch and POSTed**, byte-for-byte round-trip, including `{{formula}}` string interpolation with a bare `[controlId]` reference in a modal header title. `agent-input` remains GET-spec-only pending the agent surface. See `dynamic-values.md`. |
| `input-table` element (`empty`+`linked` source, all 6 column shapes, `insert-rows`/`delete-rows` writeback) | GET-spec: all 5 harvested workbooks (27 instances combined) — 2026-08-03. **POST-verified**: `b7fead6d-504e-48e7-b623-e41576ce8eb5` — 2026-08-04 (Wave 3 / C5 probe) | GET-spec 200; field names cross-confirmed against the real upstream `sigma-workbooks` skill's `tables.md` (independent source, same conclusion: column field is `type`, not `columnType`). **Authored from scratch and POSTed** — both `empty` (real connectionId) and `linked` (`from` + bare-column-id `key`, correcting the harvest's `inode-<id>/COL` assumption) source variants, all 6 column shapes, and both writeback effects via a button, all round-tripped byte-for-byte. See `input-tables.md`. |
| `agents[]` + `chat` element (incl. agent tool `insert-rows` writeback + `agent-input` values) | GET-spec: Insurance P4P Analytics, Workbooks Demo 2026, Marketing Control Center, Bergey's Unified Insights — 2026-08-03. **POST-verified**: `b7fead6d-504e-48e7-b623-e41576ce8eb5` — 2026-08-04 (Wave 3 / C6 probe, same workbook as the input-table probe) | GET-spec 200; `agents:[{id,name,instructions,dataSources,tools}]` present; `tools[].steps[]` reuse the same effect vocabulary as buttons. **Authored from scratch and POSTed** — `chat` element + `agents[]` with a tool writing to a real input-table via `insert-rows` + `agent-input` dynamic values + `{{formula}}`-interpolated `instructions`, all round-tripped byte-for-byte. See `agents.md`. |
| `image` element (`source:{kind:"url"|"upload"}`) + `{{formula}}` URL + inline `data:image/svg+xml;base64,...` | GET-spec: Workbooks Demo 2026, Marketing Control Center — 2026-08-03. **POST-verified**: `b77b5b05-d1f5-40ba-96eb-00458726da29` — 2026-08-04 (Wave 4 / C7 probe) | GET-spec 200 confirmed `{{If(...)}}` URLs and 2 valid lucide-icon inline SVGs. **Authored from scratch and POSTed** — surfaced and fixed a real field-shape bug (flat `url` is wrong; real shape is `source:{kind:"url", url}`), both the `{{formula}}` URL and the inline-SVG data URI round-tripped byte-for-byte in the corrected shape. Resolves the previously-open "WAF-403 on inline SVG" question — not observed. See `others.md`. |
| Container `backgroundImage` (`source:{kind:"url"|"upload"}`) + theme color reference (`{kind:"theme", ref}` as a color value) | GET-spec harvest (backgroundImage) — 2026-07-02; `themeOverrides`/theme colors GET-spec — `sales-mbr-sentinel`, 2026-07-02. **POST-verified**: `b77b5b05-...` — 2026-08-04 (Wave 4 / C7 probe) | **Authored from scratch and POSTed** — surfaced and fixed the same `backgroundImage.url` → `backgroundImage.source.url` bug as the image element; also corrected a false claim that `{kind:"theme", ref}` was a standalone element kind (live-POST rejected as an element; confirmed as a color-value form used in `style.borderColor` instead). See `containers.md` and the new `theming.md`. |
| `navigation` element | Workbooks Demo 2026 — 2026-08-03 GET-spec; **`b9e4bc48-afa8-4085-b94d-fdd61c06bf0d` — 2026-08-03 POST-verified** | GET-spec 200; `kind:"navigation"` + `mode` present. **Authored from scratch and POSTed** — `mode:"auto"` round-trips unchanged. |
| `plugin` element | Claims Command Center — 2026-08-03 | GET-spec 200; `kind:"plugin"` + `pluginId` + `config` present |
| Page-level RBAC (`visibility.kind:"specific-users-and-teams"`) | Bergey's Unified Insights — 2026-08-03 | GET-spec 200; `assignments.teams:[uuid,...]` present on 6 pages |
| `controlType:"synced"` (cross-page control sync) | Bergey's Unified Insights — 2026-08-03 | GET-spec 200; one primary `segmented` control + 4 `synced` stubs sharing one `controlId` |

**POST-verification status.** `modal` pages, `tabbed-container`,
`page-break`, and `navigation` were authored from scratch and POSTed as
part of the Wave 1 / C2 probe (2026-08-03, workbook
`b9e4bc48-afa8-4085-b94d-fdd61c06bf0d`, folder "Claude Testing"). `button`
+ all 9 effects + 4 of 5 dynamic-value forms were authored from scratch
and POSTed as part of the Wave 2 / C3 probe (2026-08-03, workbook
`189db290-7674-4032-9ff7-7fad59dc14fa`) plus a real build-mode session
(`fe0140e9-3798-4a9a-a30b-03af8ddbc8ef`). `input-table` (both source
variants, all 6 column shapes), `agents[]` + `chat`, agent tool
`insert-rows` writeback, and the 5th dynamic-value form (`agent-input`)
were authored from scratch and POSTed as part of the Wave 3 / C5+C6
probe (2026-08-04, workbook `b7fead6d-504e-48e7-b623-e41576ce8eb5`).
`image` (all variants), container `backgroundImage`, and the
`{kind:"theme", ref}` color-value form were authored from scratch and
POSTed as part of the Wave 4 / C7 probe (2026-08-04, workbook
`b77b5b05-d1f5-40ba-96eb-00458726da29`) — this probe also caught and
fixed two real field-shape bugs (`image`/`backgroundImage`'s flat `url`
should have been `source:{kind:"url", url}`) and one false claim
(`theme` is not a standalone element kind). None of those are
GET-spec-only anymore. Everything else in the table above (`plugin`)
is still GET-spec (read) confirmation only — "supported" for those
means "the live API emits this shape for a working, currently-
rendering workbook," which is strong evidence but not proof that
authoring it from scratch will be accepted identically. Probe each
before asserting it as a canonical, clone-able shape.

**Wire-format caveat (2026-08-04).** The live POST/PUT/GET wire format
nests the spec under a top-level `document` key (see
`reference/specification/schema.md` → "Wire format" and
`reference/history.md` → "2026-08-04 — document wrapper"). The
`b9e4bc48-...` and `189db290-...` POST-verified workbooks referenced
above were POSTed via flat-shape `curl` calls made directly during Wave
1/Wave 2, before this wrapper requirement was discovered — whether the
API changed mid-session or those calls were wrapped in a way not
reflected in this ledger's evidence rows was not conclusively
determined. This does not undermine what those probes proved (the
element shapes, field names, and referential semantics are unaffected
by wire-level nesting), but if you need to re-run one of those probes
verbatim, wrap it in `document`/`kind:"workbook"` first — or use
`scripts/api/publish-workbook.sh`, which does this for you.

## Unverified — probe pending (do not treat as fact either way)

| Claim | Source | Status |
|---|---|---|
| `top-n` as a dedicated `controlType` | Real upstream `sigma-workbooks` skill says yes; local `controls.md` explicitly says no (filter-only) | Direct disagreement with the *real* engineering skill — needs a live probe, not a guess |
| `plugin.config` column bindings — bare `columnId` string vs. `{kind:"column", columnId, source}` object | Disagreement between two third-party forks, neither authoritative | Probe pending |
| `clear-control` effect scope (`page` only vs. `control`/`container`) | Disagreement between two third-party forks | Probe pending |
| `DateTrunc([control], ...)` with a dynamic first argument | Local `controls.md` shows this; one third-party fork claims it errors and must be wrapped in `Switch` | Probe pending |
| `displayColumnId` on a control's `source` | Observed in one third-party fork's corpus; zero occurrences in this skill's 5-workbook harvest | Probe pending |
| Cascading controls (control A restricts control B's value list) | No source has documented this | Genuine, unaddressed gap — not even a claim to verify yet |
| A `dataset` source `kind` (alongside the documented `table`/`data-model` kinds) | 2026-08-10 wire-format shape-diff audit — observed in live GET responses, cross-referencing 3 real workbooks against every `reference/specification/` file | Additive, non-breaking. Not yet probed by authoring one from scratch; not documented anywhere in `reference/`. Logged, not built, per explicit user direction ("log tier 2 as a future step for review") |
| SQL element `{{Control}}:start` / `{{Control}}:end` interpolation syntax (for range-typed controls feeding a raw-SQL element) | Same 2026-08-10 audit | Additive. Only the bare `{{Control}}` form is documented today; the `:start`/`:end` suffix form was observed but not independently authored/POSTed |
| Conditional `trigger` objects on `conditionalFormats` entries (beyond the documented static-threshold form) | Same 2026-08-10 audit | Additive. Shape observed in a live GET response; not cross-checked against a from-scratch POST |
| KPI `comparison`/`trend` styling fields beyond what `kpis.md` documents (additional color/format sub-fields) | Same 2026-08-10 audit | Additive. Exact field set not fully cataloged — needs a dedicated KPI-styling probe, not just a re-read of one harvested example |
| Donut-chart `hole` / `innerRadius` sizing fields | Same 2026-08-10 audit | Additive. `charts.md`'s donut section doesn't currently document a hole-size control; observed present in a live spec |
| Chart `lineAreaStyle` field (line/area chart rendering variant, distinct from the documented `stacking` values) | Same 2026-08-10 audit | Additive. Not documented in `charts.md`; exact enum values unconfirmed |
| DM-internal RLS helper columns (`CurrentUserAttributeText`-backed column + dependent boolean) not cross-element-referenceable from a workbook table, even when named at the DM level | A Wave 2 build-mode test session, 2026-08-04 | Plausible given Sigma's RLS mechanics, but not independently reproduced — this session has no recon on a real RLS-backed data model. Two other claims from the same report (cross-page forward-reference ordering, table `sort`+`groupings` rejection) were checked and refuted via live probes the same day — see `reference/history.md` → "2026-08-04 — second peer report," so this one is flagged, not assumed true by association. |
| `GET /v2/dataModels/{id}/spec` 500s (`service_error: unsupported dataset source`) on a data model with a CSV-uploaded dataset source | health-plan-enterprise-stars-portfolio build session, 2026-08-11 | One data source type, one session. Workaround used: `GET /v2/dataModels/{id}/elements` + `/columns` return full column/type schema without hitting the broken path (no `metrics` catalog, which only lives in `/spec`). Needs retest against another CSV-sourced data model before treating as a general CSV-source limitation, not just this org's dataset. |
| `controlType: "toggle"` / `"checkbox"` reject at POST with generic `Invalid kind: "control"` | health-plan-enterprise-stars-portfolio build session, 2026-08-11 | Generic-error signal only — per this ledger's own retest protocol (see "The retest protocol" above), not reliable "unsupported" evidence on its own. `controls.md`'s own toggle example carries no verification citation either (unlike confirmed entries elsewhere in that file). Needs a live bisection probe, not just this session's rejection. |
| `bar-chart` + `orientation:"horizontal"` + `color:{by:"single"}` rejects (`Invalid kind: "bar-chart"`) unless `"stacking"` is also present | health-plan-enterprise-stars-portfolio build session, 2026-08-11 | Generic `Invalid kind` error; `charts.md`'s prose calls `stacking` an independent "adds" feature, not load-bearing. Needs a bisection retest to confirm `stacking` is actually required vs. some other missing sibling field. |
| `dataLabel: {labels, labelDisplay}` (the documented subset shape) breaks the whole `bar-chart` element | health-plan-enterprise-stars-portfolio build session, 2026-08-11 | Generic `Invalid kind` error, bisected to this field in one session only — possibly needs more required sibling fields (`valueFormat`, `totals`) than `charts.md` marks optional, rather than `dataLabel` itself being broken. Needs retest. |
| `conditionalFormats` (`backgroundScale` variant) rejected at POST/PUT on every element kind tried — plain `table`, `table` with `groupings`, `pivot-table`, and `input-table` (4 for 4) | health-plan-enterprise-stars-portfolio build session, 2026-08-11 | Stronger signal than the three rows above (consistent across 4 distinct kinds) and contradicts `reference/specification/tables.md`'s existing "assume `conditionalFormats` on `table` works" hedge. **Top-priority retest** — either this org regressed since the 2026-05-21 verification, or the verified shape has drifted a newly-required field. |
| Top-level `sort` on a `table` with `groupings` fails at PUT (`"Sort column not found: table X, column Y"`) when `sort` references a `groupings.calculations` column | health-plan-enterprise-stars-portfolio build session, 2026-08-11 | **Conflicts with an already-refuted version of this same general claim**: `reference/history.md` → "2026-08-04 — second peer report" refuted a general `sort`+`groupings` rejection using `dashboard-department-scorecard.json`'s `tbl-top-stores` (`groupings` + `sort` together, POSTed clean). This 2026-08-11 finding may be narrower — specifically sorting *by a `groupings.calculations`-derived column*, vs. the refuted case's sort target which reads as a plain/summary column. Don't treat either claim as settled; the retest should specifically isolate that distinction rather than re-testing the general case again. |

**On third-party forks:** `cmiller-coder/millersigma` and a repo initially
mistaken for a mirror of the real upstream skill (`twells89/sigma-migration-skills`)
are both derivative work, not Sigma's own engineering documentation.
Per project direction, the latter's workbook-authoring conventions are
excluded from this skill's decisions entirely — it's retained only for its
plugin-packaging patterns (see the portability work). Where a fork's claim
appears above, it's flagged as unverified, never adopted as fact.
