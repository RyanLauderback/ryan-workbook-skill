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
   `scripts/api/mcp-search.sh` / browsing the org, or ask the user for one.
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
| `button` element + `actions[]` | Claims Command Center (`0de447af-35f8-4831-af80-a2ea8eac32a2`), Insurance P4P Analytics (`691fa937-e296-4f88-bc81-afc10bb123ef`), Workbooks Demo 2026 (`9c0cb6a7-f25e-4045-a896-6de9e46a364b`), Marketing Control Center (`7eb36f00-5c3b-4471-861d-e8b679cab731`) — all 2026-08-03 | GET-spec 200; `kind:"button"` present with `actions:[{trigger, effects}]`; 9 distinct effect types observed across the corpus |
| `modal` pages (`type:"modal"`) | Claims Command Center (9 modal pages), Workbooks Demo 2026 (1), Marketing Control Center (1) — 2026-08-03 | GET-spec 200; `pages[].type:"modal"` + `modal:{width,header,footer}` present |
| `tabbed-container` | Claims Command Center (5), Marketing Control Center (3), Bergey's Unified Insights (5) — 2026-08-03 | GET-spec 200; `kind:"tabbed-container"` + `tabs:[{name}]` present; layout XML confirms `<TabbedContainer>`/`<Tab>` tags |
| `page-break` | Workbooks Demo 2026 — 2026-08-03 | GET-spec 200; `kind:"page-break"` present |
| Action sequences (multi-effect `actions[]`) | All 5 harvested workbooks — 2026-08-03 | GET-spec 200; effects observed: `set-control-value`, `open-overlay`, `clear-control`, `navigate`, `insert-rows`, `delete-rows`, `select-tab`, `close-overlay`, `open-url` |
| `input-table` element | All 5 harvested workbooks (27 instances combined) — 2026-08-03 | GET-spec 200; field names cross-confirmed against the real upstream `sigma-workbooks` skill's `tables.md` (independent source, same conclusion: column field is `type`, not `columnType`) |
| `agents[]` + `chat` element | Insurance P4P Analytics, Workbooks Demo 2026, Marketing Control Center, Bergey's Unified Insights — 2026-08-03 | GET-spec 200; `agents:[{id,name,instructions,dataSources,tools}]` present; `tools[].steps[]` reuse the same effect vocabulary as buttons |
| `image` with `{{formula}}` URL | Workbooks Demo 2026 — 2026-08-03 | GET-spec 200; `image.source.url` containing `{{If(...)}}` |
| `image` with inline `data:image/svg+xml;base64,...` | Marketing Control Center — 2026-08-03 | GET-spec 200; two lucide-icon SVGs decoded and confirmed valid |
| `navigation` element | Workbooks Demo 2026 — 2026-08-03 | GET-spec 200; `kind:"navigation"` + `mode` present |
| `plugin` element | Claims Command Center — 2026-08-03 | GET-spec 200; `kind:"plugin"` + `pluginId` + `config` present |
| Page-level RBAC (`visibility.kind:"specific-users-and-teams"`) | Bergey's Unified Insights — 2026-08-03 | GET-spec 200; `assignments.teams:[uuid,...]` present on 6 pages |
| `controlType:"synced"` (cross-page control sync) | Bergey's Unified Insights — 2026-08-03 | GET-spec 200; one primary `segmented` control + 4 `synced` stubs sharing one `controlId` |

**Not yet POST-tested.** Every row above is a GET-spec (read) confirmation.
None of these have been round-tripped through an actual `POST
/v2/workbooks/spec` from this skill yet — that's the Wave 0 probe, still
pending. "Supported" here means "the live API emits this shape for a
working, currently-rendering workbook," which is strong evidence but not
proof that authoring it from scratch will be accepted identically.

## Unverified — probe pending (do not treat as fact either way)

| Claim | Source | Status |
|---|---|---|
| `top-n` as a dedicated `controlType` | Real upstream `sigma-workbooks` skill says yes; local `controls.md` explicitly says no (filter-only) | Direct disagreement with the *real* engineering skill — needs a live probe, not a guess |
| Inline `data:image/svg+xml` accepted on **POST** (not just observed on GET) | Harvest confirms GET; a third-party fork (`cmiller-coder/millersigma`) ships it in production | Probe pending |
| `plugin.config` column bindings — bare `columnId` string vs. `{kind:"column", columnId, source}` object | Disagreement between two third-party forks, neither authoritative | Probe pending |
| `clear-control` effect scope (`page` only vs. `control`/`container`) | Disagreement between two third-party forks | Probe pending |
| `DateTrunc([control], ...)` with a dynamic first argument | Local `controls.md` shows this; one third-party fork claims it errors and must be wrapped in `Switch` | Probe pending |
| `displayColumnId` on a control's `source` | Observed in one third-party fork's corpus; zero occurrences in this skill's 5-workbook harvest | Probe pending |
| Cascading controls (control A restricts control B's value list) | No source has documented this | Genuine, unaddressed gap — not even a claim to verify yet |

**On third-party forks:** `cmiller-coder/millersigma` and a repo initially
mistaken for a mirror of the real upstream skill (`twells89/sigma-migration-skills`)
are both derivative work, not Sigma's own engineering documentation.
Per project direction, the latter's workbook-authoring conventions are
excluded from this skill's decisions entirely — it's retained only for its
plugin-packaging patterns (see the portability work). Where a fork's claim
appears above, it's flagged as unverified, never adopted as fact.
