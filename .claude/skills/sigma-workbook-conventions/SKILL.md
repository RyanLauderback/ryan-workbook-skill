---
name: sigma-workbook-conventions
description: >-
  Use when authoring, editing, or reviewing any Sigma workbook/data-model spec
  in this repo. Encodes project conventions on element naming, page/folder
  layout, ID semantics on create-vs-update, secret handling, and common
  pitfalls when generating Sigma JSON specs. Pair with sigma-data-models for
  field-level reference, and with a domain-specific workbook-pattern skill
  when one is available for the dashboard type being built.
---

# Sigma Workbook Conventions

Project-wide conventions for Sigma workbook/data-model specs. Read this before
generating or editing any `spec.json` in `workbooks/` or `examples/`.

## Inputs

This skill is reference-only — no scripts. It assumes:

- The user has already authenticated via the `sigma-api` skill.
- `sigma-data-models` is available for endpoint mechanics and field semantics.
- The local mirror at `vendor/sigma-agent-skills/` is available to consult when a
  field-level question isn't answered here.

## Session modes

Sessions in this workspace run in one of two modes, signaled by an
explicit phrase in the user's first message:

| Mode | Trigger | Behavior |
|---|---|---|
| **Training** (default) | `initialize training mode session` | Full agentic co-development. Propose plans, ask clarifying questions, surface inference choices, and after the build promote recurring findings into skills / reference / memory. Recommend skill modifications when a pattern recurs. |
| **Test** | `initialize test mode session` | Build-only. Focus exclusively on producing the requested workbook using this skill as it currently exists. Do NOT propose skill modifications. Do NOT offer to promote findings. Do NOT editorialize about the iteration process. Solve blockers quietly within the build. The skill is treated as fixed reference material. |

If neither phrase is used at init, default to training mode.

**Why two modes:** test mode supports recording demo videos for
customers. The spotlight in those demos is on what Sigma + Claude can
deliver right now, not on the meta-process of co-developing the skill.
Skill-promotion chatter (even when valuable) pollutes the demo
narrative.

The rest of this skill — the plan-first workflow, naming, gotchas, and
reference material — applies in both modes. The only thing test mode
suppresses is the meta-layer where you'd normally surface findings for
future skill improvement.

## Workflow: resolve user input before planning

**Use the bash helpers in `scripts/api/` for any read-only discovery
against the existing Sigma workspace** — search, lookup, inspect. The
MCP wrappers (`scripts/api/mcp-search.sh`, `scripts/api/mcp-describe.sh`)
call Sigma's MCP server (`/mcp/v2`) using the same OAuth token as the
REST API and return richer output than the REST endpoints with less
bash plumbing.

For Sigma **function references** and **REST API endpoint shapes**
(not workspace discovery), use the native `mcp__claude_ai_Sigma_Docs__*`
tools — no bash, no auth, no `WebFetch`. See `reference/workbook-spec-api.md`
→ "Looking up Sigma functions."

Route by what the prompt actually contains:

| Prompt contains | Use first |
|---|---|
| Names or topics ("the PLUGS data model", "find the sales workbook") | `scripts/api/mcp-search.sh "<query>" [--types workbook,dataModel,dataModelElement,table] [--limit N]` |
| URL slugs (`/b/<id>`, `…-<urlId>`) | `scripts/api/find-file-by-urlid.sh <urlId>` |
| Warehouse paths (`<DB>.<SCHEMA>.<table>`), `/s/<id>` or `/t/<id>` schema URLs, or mixed prose | `scripts/sigma-resolve.py "<prompt-verbatim>"` |

After resolution, use `scripts/api/mcp-describe.sh` against the resolved
id (`table`, `datamodel`, `datamodel-element`, `workbook`,
`workbook-element`) to inspect — returns SQL DDL with column types,
descriptions, formulas, and the metrics catalog. Replaces hand-walking
`GET /v2/dataModels/{id}/spec` JSON.

**Batch `mcp-describe.sh` calls in parallel after the first datamodel
overview.** The flow is: one `mcp-describe.sh datamodel <id>` to list
elements (sequential — you need its output to know which element IDs
exist), then **all subsequent `mcp-describe.sh datamodel-element <dm>
<el>` calls in a single Bash batch** (parallel tool calls). Each
element describe is independent and Sigma's MCP server handles
concurrent reads fine. Don't interleave reasoning between describes —
batch them, then reason once over the combined output.

The REST primitives in `scripts/api/` (`list-connections.sh`,
`lookup-path.sh`, `list-table-columns.sh`, `list-folders.sh`,
`probe-schema-tables.sh`) are fallbacks for cases MCP doesn't cover —
raw connection enumeration, folder browsing by name pattern, warehouse-
schema probing. Reach for them only when MCP + resolver don't.

Rules:

- Use resolved IDs directly in the plan. Don't re-derive with raw curl.
- MCP `search` is **semantic / fuzzy** — it returns the top matches even
  when relevance is low. Always confirm a match against the user's
  stated name/intent before building on it. Surface "I found two named
  'Sales Performance' — A in `My Documents/Demo`, B in `Org Shared/Q4`.
  Which?" — never expose endpoint errors or HTTP codes.
- Schema/table URL slugs (`/s/<id>`, `/t/<id>`) are not reversible via
  Sigma's public API. If unresolved, ask the user for "<DB>.<SCHEMA>"
  and the connection name.
- Known gap: `mcp-search.sh` results of type `dataModelElement` don't
  always carry the parent `dataModelId`. If you need to chain into
  `mcp-describe.sh datamodel-element`, resolve the data-model first via
  search or `find-file-by-urlid.sh` against the URL's slug.

Auth is handled inside the scripts — each `scripts/api/*.sh` sources
`scripts/api/_env.sh` on first call, which loads `.env`, fetches an
OAuth token via the `sigma-api` skill, and caches it at
`/tmp/.sigma_token` (mode 0600, 55-min TTL). No env-prelude or token
chaining needed from the caller. Override the token-fetcher path via
`SIGMA_TOKEN_FETCHER` if your install differs from the marketplace
plugin default.

### Installing this skill in a new project

When dropping this skill into another project, merge the rules in
`recommended-permissions.json` (alongside this `SKILL.md`) into that
project's `.claude/settings.json` under `permissions`. With those rules
in place, every script in `scripts/api/*` runs without an approval
prompt; `curl` calls for workbook authoring/publishing still prompt
(by design — they're state-changing). Without them, every discovery
call surfaces a prompt because no allow pattern matches.

### Invoking scripts

The deployment expectation is that `ryan-workbook-skill/` is the
Claude Code primary working directory. Invoke `scripts/api/*.sh` and
`python3 scripts/*.py` **bare** — no `cd <repo> &&` prefix needed. The
`Bash(scripts/api/*)` allowlist pattern matches bare invocations and
runs silent. Prepending an absolute or relative `cd` defeats the
pattern match, adds verbosity, and creates no functional benefit when
CWD is already the repo root.

`sigma-resolve.py` (for the messy-input case) returns structured JSON:

```json
{
  "sources":    [ {"kind": "warehouse-schema|warehouse-table|workbook|datamodel|folder|...", ...} ],
  "folder":     { "id", "urlId", "name", "path" } | null,
  "candidates": { "folder": [...], "sources": [...] },
  "unresolved": [ ... ],
  "hints":      { "db", "schema", "connection", "folder_name" }
}
```

When `candidates` is populated, surface names to the user; when
`unresolved` has warehouse-path entries, ask for the missing
`<DB>.<SCHEMA>` and connection name. For warehouse-schema sources, the
resolver also returns the table inventory it found via
`probe-schema-tables.sh`; if the intended tables aren't there, ask the
user to name the missing ones so the resolver can re-probe.

## Workflow: propose a plan before building

Workbook prompts often underspecify the dashboard — the user names the data
and the question, not the visualizations or the filter set. Do not jump
straight to JSON. Before authoring any spec, surface a written plan and
wait for explicit approval.

The plan must include:

1. **Destination.** Where the workbook (or data-model update) will be
   published — folder `name` + `path` + `urlId`, resolved from the
   user's prompt via `sigma-resolve.py`. If the user named a folder
   inline, restate it back so they can correct it. If the user did NOT
   name a folder, this becomes an Open Decision (item 6) the plan must
   ask, not a default the agent picks. **Plan approval IS the
   authorization to POST/PUT** — there is no separate "are you sure?"
   prompt at publish time. The destination must therefore be named
   explicitly in the plan, never implied.
2. **Data inventory.** What table(s) and which columns are actually
   available — pulled via `scripts/api/mcp-describe.sh datamodel-element
   <dm-id> <el-id>` (returns column types, descriptions, formulas, and
   the data model's metrics catalog), not assumed. Name any column
   that's missing from your assumed schema (e.g. there *is* a customer
   dimension; there *isn't* a margin field) so the user can correct
   before you build on a wrong premise.
3. **Inference rationale.** For each visualization you propose, one line
   on *why this chart, this dimension, this metric* answers the user's
   question. "Quantity, not revenue, because popularity is a unit-volume
   question" beats "bar chart of products."
4. **Filter set with reasoning.** Filters aren't free — each one earns
   its place by mapping to an axis the user is likely to interrogate.
   List the filters in priority order with a one-line reason, and note
   what you considered and dropped.
5. **Layout sketch.** A textual block-diagram of the page is enough
   (header / KPI row / chart grid / detail). Don't draw the XML yet.
6. **Open decisions.** Anywhere you had to guess (proxy for a missing
   dimension, scope of demographic data to bring in, whether to modify a
   shared data model, **missing/ambiguous destination folder**). Phrase
   as questions the user can yes/no.

Only after the user approves should you write spec JSON. This convention
exists because rebuilding a wrong dashboard costs more iterations than
the 60 seconds spent writing the plan, and because the user can correct
data-model assumptions you'd otherwise discover at POST time.

If the user has already given you an explicit plan, skip to building —
don't re-propose.

### Approval model — plan is the only gate

Plan approval authorizes **every state-changing API call covered by the
plan, except DELETE**. POST/PUT to `/v2/workbooks/spec` and
`/v2/dataModels/*/spec` run silently — `.claude/settings.json` allowlists
both `Bash(scripts/api/*)` (which covers `publish-workbook.sh`) and the
direct curl patterns. The user reviews one plan, approves, and the
build + publish proceed without further interruption.

The rules:

- **POST/PUT inside the workbook/data-model namespace:** silent. Plan
  approval is the authorization.
- **POST/PUT outside that namespace** (e.g. `/v2/connections`,
  `/v2/files` mutations): not pre-authorized — surface to the user.
- **DELETE on any endpoint:** always asks. The `ask` patterns in
  `.claude/settings.json` (`Bash(curl * -X DELETE *)` and
  `Bash(scripts/api/delete-*)`) override the broad `Bash(scripts/api/*)`
  allow. Even when the plan mentions deletion, every DELETE call is
  surfaced for explicit confirmation.

That contract puts the burden on the agent:

- The plan MUST name the destination folder (item 1 above) and any
  shared object it intends to mutate (data models, exemplars). If a
  state-changing call wasn't covered in the plan, do not make it — go
  back and amend the plan first.
- Any future deletion-wrapper script must be named `scripts/api/delete-*`
  so the ask pattern catches it. Do not bypass via a different name.

## Conventions

### Naming

- **Pages** use Title Case ("Variance Detail", not "variance_detail" or "variance detail").
- **Columns** use snake_case for IDs and Title Case for display labels.
- **Metrics** start with a verb: `total_revenue`, `count_orders`, `avg_ticket`. Display labels stay human-readable ("Total Revenue").
- **Filters/Controls** are named after the dimension they bind to, suffixed with `_filter` or `_control`.
- Avoid Sigma's auto-generated names (`Calculation 1`, `Filter 2`); always rename before saving an iteration.

### Page/folder layout

- First page = **Overview** (KPI tiles + a single primary visualization).
- Subsequent pages drill from coarse → fine: Overview → Trend → Detail → Exception list.
- Group related controls into a single Filter Bar at the top of each page rather than scattering.
- Use folder groupings for any model with >10 elements; flat models are hard to read.

### ID semantics (CRITICAL)

When round-tripping specs, IDs behave differently per operation:

- **CREATE (POST):** Sigma remaps IDs server-side. Don't depend on the IDs you sent.
- **GET:** Returned IDs are source-of-truth. Save them.
- **UPDATE (PUT):** Existing IDs MUST be preserved. New elements added in an UPDATE
  body are assigned new IDs. Do not reuse a deleted element's ID.

When generating a spec from scratch, use stable human-readable placeholder IDs
(`col_revenue`, `metric_total_revenue`); after the first POST, GET back the
authoritative spec and use it as the new baseline.

### Constraints (from upstream `sigma-data-models`)

- Partial updates are NOT supported — both CREATE and UPDATE require the complete spec.
- A single model cannot contain multiple identically-named tables.
- Input tables, Python elements, and references to other Sigma elements in custom
  SQL are **not supported** by the round-trip endpoints. Avoid generating these.

### Secrets

- Never bake `$SIGMA_API_TOKEN`, `$SIGMA_CLIENT_SECRET`, or any credential into a
  spec, prompt, or note file.
- Do not write tokens to files under the workspace.
- Tokens belong only in the `Authorization` header.

### Iteration hygiene

- Save each generation attempt under `workbooks/<name>/iterations/<timestamp>.json`
  alongside the prompt that produced it in `prompts/<timestamp>.md`. This makes
  diffs across attempts cheap and turns each session into evidence.
- When a fix recurs across 2+ iterations, promote the rule into this file or into
  a domain skill's `reference/`. See `docs/iteration-playbook.md`.

## Common pitfalls

1. Generating fields the round-trip endpoint doesn't support (input tables, Python).
2. Keeping Sigma's auto-generated names; downstream readers can't tell what they do.
3. Reusing a stale ID from an earlier CREATE response after an UPDATE.
4. Embedding controls inside a single page when they should be model-level so
   they can drive multiple pages.
5. Forgetting that columns must reference an existing source — declare sources first.

## Workbook spec gotchas (load `reference/workbook-spec-api.md` BEFORE authoring)

For workbook specs specifically (not data models), ten rules from past
iteration failures:

1. **No implicit column inheritance.** A chart sourced from a sibling table
   must redeclare every column it references. The CREATE endpoint accepts
   broken specs that fail silently at render time.
2. **Set explicit `name` on every column referenced by a sibling element.**
   Inferred names (passthrough formulas with no `name` field) work in a
   GET-back exemplar but fail at POST time with `dependency not found`.
   Always write `name: "Date"` etc. on columns that downstream KPIs,
   charts, or controls will reference by display name.
3. **Verify data-model columns resolve before building on them.** A
   column listed in `GET /v2/dataModels/{id}/spec` is not guaranteed to be
   queryable from a workbook — orphaned/stale columns can pass through
   the data-model spec and still fail formula resolution. When pulling
   newer/unfamiliar columns, do a minimal one-table POST as a probe
   first; if it returns 400, source from the warehouse table directly.
4. **Always check the data model's `metrics` first.** Use `[Metrics/<Name>]`
   instead of redoing aggregations in the workbook — preserves formatting
   (currency, percent) and keeps a single source of truth. Caveat:
   metrics live on data-model elements only. Warehouse-sourced workbook
   tables have no access — replace with inline `Sum(...)` aggregations.
5. **Controls bind by column `id`, not name.** `filters[].columnId` must
   match a column id you've declared on the target element.
6. **Visualization clarity is non-negotiable.** Every page gets a title
   `text` element at the top (workbook `name` is metadata, not a visible
   heading); every chart/KPI gets a descriptive `name`; KPIs over time-series
   metrics get a date-dimension column for sparkline + period comparison;
   KPIs need ~8–10 grid rows of height for the sparkline to read.
7. **Use containers for page structure.** Wrap related elements (header
   bar, KPI row + chart) in `kind: container` elements with `<GridContainer>`
   layout XML so the page reads as logical blocks rather than a flat grid.
8. **Omit column `format` at POST.** The `format` object requires a
   `kind` field whose exact shape is undocumented; specs that include
   `format` are rejected with `Missing "kind" field`. Configure currency
   /percent formatting in the UI and rely on GET-back to learn the shape.
9. **Derive complex per-row calcs on a parent table, not on the
   viz.** Putting `If([Margin] >= Median([Margin]), …)` directly on a
   chart where `[Margin]` is already an aggregated metric creates a
   recursive aggregate ("Column has a recursive formula"). The
   pattern: aggregate to the right grain in a parent table via
   `groupings`, hold the scalar (median/mean/percentile) in that
   table's `summary` array (**singular `summary`**, not `summaries`),
   put the bucket/label column inside the grouping's `calculations`
   referencing both the per-row metric and the summary value by local
   name, and let the chart source from the parent and pass the bucket
   column through. See `reference/workbook-spec-api.md` →
   "Summary bar and aggregate-then-categorize pattern."
10. **Pass through every source-table column on each visualization.**
    Sigma's right-click drill-down on a chart only exposes columns
    that chart declares. If a Revenue-by-Region bar only declares
    `region` + `revenue` + the metric's material columns, the user
    can't drill region → state → city → store even though those
    columns exist on the source. Default: every chart/KPI/pivot
    declares the full passthrough column set from its source (plus
    any chart-specific derived columns). Exceptions only when the
    source has 50+ columns and most are irrelevant to the page.

Full patterns, source kinds, formula namespaces, KPI/text/container shapes,
GridContainer layout XML, and the page-structure pattern live in
`reference/workbook-spec-api.md`. Always visually verify the workbook in
the UI after a CREATE — the API doesn't validate cross-element column
resolution or visualization quality.

## Publishing — use `publish-workbook.sh`

Workbook POST/GET goes through the wrapper:

```bash
# POST (creates a new workbook). Auto-runs validate-spec.py first.
scripts/api/publish-workbook.sh post workbooks/<name>/spec.json

# GET the spec back as JSON — that's the new source of truth.
scripts/api/publish-workbook.sh get-spec <workbookId> | jq . > workbooks/<name>/spec.json

# GET workbook metadata (url, name, path, folderId).
scripts/api/publish-workbook.sh get-meta <workbookId>
```

The wrapper:
- Runs `validate-spec.py` before POST (fail-fast on the silent-rewrite
  gotchas: missing `pages[].layout`, unplaced elements, empty containers,
  column `format`, duplicate `controlId`).
- Uses `sigma_curl` from `_env.sh`, which auto-injects
  `Authorization: Bearer ...` and `Accept: application/json` headers and
  retries once on HTTP 401 (cache eviction + refetch).
- Doesn't have a `delete` subcommand. DELETE stays on the direct-curl
  path so it always hits the DELETE ask pattern in `.claude/settings.json`.

The validator catches the silent-rewrite failure mode from 2026-05-11
(per-page `layout` fields ignored; charts stacked in a 1/13-wide single
column). Run it via the wrapper; never skip.

## Reference and examples

- `reference/naming.md` — naming rubric.
- `reference/workbook-spec-api.md` — **the load-bearing reference.** Read
  before authoring any workbook spec. Contents:
  - **Element kinds — verified table** (top of file) — maps every viz
    intent (bar / line / area / combo / scatter / pie / donut / KPI /
    pivot / table / control / container / text) to its `kind` value and
    encoding fields.
  - **Per-kind shape sections** with required fields, optional encodings,
    and a minimal example for each kind. Bar/line/area/combo share one
    section; pie/donut share another; scatter, pivot, KPI, table-with-
    groupings each have their own.
  - **Control catalog** — `controlType` values (`date-range`, `list`,
    `text`, `number-range`, `segmented`) and the controls-as-formula-
    values pattern (`[ControlId]` referenced inside formulas).
  - **Aggregation patterns** — multi-level table `groupings` (with
    `groupBy` + `calculations`), aggregated-sibling-plus-Lookup as the
    legible default, `Rollup` as the inline alternative, the
    materialize-then-window rule, and the **summary-bar pattern**
    (`summary: [...]` on a parent table for scalars like median, used
    by an in-grouping bucket column to label per-row data — see
    "Summary bar and aggregate-then-categorize pattern").
  - **Cross-element formulas** — `Lookup`, formula namespaces, data-model
    metric references.
  - **Spec correctness checks** — column-declaration rule, explicit-`name`
    rule, **drill-down passthrough rule** (every chart/KPI/pivot
    declares the full source-table passthrough column set so right-click
    drill works), two-tier sourcing pattern, verifying via generated SQL.
  - **Edge cases** — misleading `Invalid kind` errors, GET-spec 500 when
    UI features aren't representable, unsupported kinds (maps, box plot,
    sankey, etc.), the `format` field, `controlId` workbook-uniqueness.
  - **Layout** — `<Page>` / `<GridContainer>` / `<LayoutElement>` 24-col
    grid; page-structure pattern (header → body → detail).
  - **Looking up Sigma functions** — convention for using the native
    `mcp__claude_ai_Sigma_Docs__*` MCP tools (`search` + `fetch`) when
    the formula you need isn't already documented here.
- `examples/` — known-good specs to seed generation. Treat as immutable
  references; clone-and-modify rather than editing in place.
  - `data-model-sourced-overview.json` — minimal data-model-fed dashboard.
  - `data-model-sourced-kpi-overview-with-containers.json` — KPI row +
    bar chart + detail table, wrapped in containers (the canonical
    page-structure exemplar).
  - `data-model-sourced-multi-level-aggregated-table.json` — multi-level
    `groupings` with `groupBy` + `calculations`; hierarchical
    aggregations + `DateLookback` lag.
  - `additional-workbook-features-chart-and-control-catalog.json` — one
    of every supported chart kind (combo, donut, pie, area × 3, scatter)
    and the newer control types (text, number-range, segmented). Source
    when you need a verified shape for a kind not previously authored.
  - `data-model-sourced-cohort-pivot.json` — **the canonical cohort
    pattern.** Two-tier sourcing (raw passthrough → derived cohort
    sibling); `Rollup(Min([Date]), [Cust Key], ...)` for first-purchase-
    per-customer; `Greatest(DateDiff(...), 0)` non-negative guard; pivot
    with weekly rows × weeks-since-first columns; KPI row using data-
    model metrics; supporting line + bar charts. Clone-and-modify for
    any "cohort / retention / weeks-since-first-action" prompt — only
    the data-model IDs and folder ID need replacement.

For data-model field-level mechanics (columns, metrics, relationships,
filters, controls, formatting, folders, column-level security, workflows)
defer to the upstream `sigma-data-models` skill — its `reference/` folder is
the authoritative answer for those topics.
