---
name: sigma-workbook-conventions
description: >-
  Use when authoring, editing, or reviewing any Sigma workbook/data-model spec
  in this repo, or whenever the user kicks off with "start build mode" or
  "start training mode" (the project's two session-mode triggers). Encodes
  project conventions on element naming, page/folder layout, ID semantics
  on create-vs-update, secret handling, and common pitfalls when generating
  Sigma JSON specs. Pair with sigma-data-models for field-level reference,
  and with a domain-specific workbook-pattern skill when one is available
  for the dashboard type being built.
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

Sessions run in one of two modes. The user signals which mode by their first
message — `start build mode` or `start training mode`. These phrases are a
**Sigma-specific convention layered on top of Claude skills**; they're not
part of Anthropic's generic skill model.

| Mode | Trigger | Purpose |
|---|---|---|
| **Build** (default for production work) | `start build mode` | Produce a workbook in Sigma. Kicks off with a 3-question `AskUserQuestion` gate that collects environment state, data source, and the verbatim user prompt — then proceeds through Recon → Plan → Approval → POST → GET → Visual verify. The plan-first workflow is the gate before any state-changing API call. |
| **Training** | `start training mode` | Locally enrich the skill for the user's session context (e.g., migrating 100 Tableau reports, adding domain-specific patterns). May write to skill files with a `local-` filename prefix so additions are visually separable from canonical content. No 3-question gate — opens with "what are we capturing this session?" |

If neither phrase is given at init, default to **build mode** (the more common case).

### Why two modes

Build mode is the high-volume production path. Customer/colleague sessions
will almost always be builds; the structured kickoff exists to remove the
friction patterns we've observed (env not set, ambiguous data source,
implicit destination folder).

Training mode is the enrichment path. When a user needs domain-specific
context that doesn't belong in the published skill (Tableau-mapping notes,
account-specific data-model exemplars, an industry-specific dashboard
pattern), they capture it in training mode. The `local-` prefix keeps it
visually separable so it never accidentally gets promoted into the published
skill.

### Build mode — the 3-question kickoff

The very first action of a build-mode session is `AskUserQuestion` with three
questions. Each question has a defined branch behavior:

**Q1: Is your `.env` set up?**

- **Yes** — Claude runs two actions in sequence to verify auth end-to-end:
  1. `bash scripts/api/_env.sh` — warms the token cache at `/tmp/.sigma_token` (55-min TTL).
  2. `scripts/api/whoami.sh` — actively probes `/v2/files?limit=5` to confirm the token works against the live API and surfaces 5 recent files the user can confirm visually.

  Why both: passive bootstrap (`_env.sh`) succeeds even when credentials are wrong as long as `.env` has the variables filled in. The active `whoami` probe catches expired clients, wrong region URLs, and revoked tokens *before* recon starts — not mid-build.

- **No** — Claude shares `.env.example` contents + a link to Sigma's "Administration → Developer Access" docs for OAuth client creation, then re-prompts Q1 once the user confirms setup.

**Q2: What data source will you build against?**
- Data model URL/slug (`Customer-Financials-461QUZu2VPny8KxImgSmfF`)
- Warehouse table path (`<CONN>.<DB>.<SCHEMA>.<TABLE>` or `/t/<id>` URL)
- Mixed prose (the resolver handles it)

**Q3: What would you like to build, and where would you like the workbook placed in Sigma?**

Free-text. Captured verbatim as the prompt-of-record and written to
`workbooks/<name>/prompts/<timestamp>.md`. The "where" portion captures the
destination folder URL/slug/name at the kickoff layer, so the planner doesn't
have to re-ask. If the user doesn't name a destination here, the plan must
surface it as an Open Decision before POST — destination is never silently
defaulted.

### Worked example — what a build-mode kickoff looks like

```
User: start build mode

Claude: [calls AskUserQuestion with Q1, Q2, Q3 above]

  Q1 → Yes
Claude: [bash scripts/api/_env.sh]
        [scripts/api/whoami.sh]
        → "Authenticated to api.sigmacomputing.com. Recent files: ..."

  Q2 → "Customer-Financials-461QUZu2VPny8KxImgSmfF data model"
  Q3 → "customer profitability + attrition workbook in
        Claude-Testing-3Kzaga67BMlB7vVJQksjlX folder"

Claude: [writes the verbatim prompt to workbooks/<name>/prompts/<ts>.md]
        [resolves URL slugs via scripts/api/find-file-by-urlid.sh]
        [enters Recon — mcp-describe.sh on the data model]
        [drafts the Plan, surfaces for user approval]
```

If `whoami.sh` returns non-zero, the agent surfaces the Sigma error verbatim
and stops — does NOT continue into Recon with broken auth.

### Plan-first reaffirmation

The kickoff captures **raw inputs**. It does NOT replace the plan-first workflow.

After the kickoff, the agent proceeds through Recon → Plan proposal → User approval → Build → GET-back → Visual verify, per `docs/iteration-playbook.md`. **Plan approval is the only authorization for state-changing API calls** (POST/PUT to `/v2/workbooks/spec`, `/v2/dataModels/*/spec`). The 3-gate does not pre-authorize anything except the auth warm-up itself.

### Training mode — session-local marker convention

Training mode may write to skill files (`.claude/skills/sigma-workbook-conventions/`)
when the user is enriching for a specific session context. To keep these
additions visually separable from canonical content, use the **`local-`
filename prefix**:

```
.claude/skills/sigma-workbook-conventions/
├── reference/
│   ├── naming.md                          # canonical
│   ├── function-reference.md              # canonical
│   ├── element-shapes.md                  # canonical
│   ├── layout-and-cross-element.md        # canonical
│   ├── scope-and-edge-cases.md            # canonical
│   ├── history.md                         # canonical
│   └── local-tableau-migration.md         # session-local — added in training mode
└── examples/
    ├── data-model-sourced-overview.json        # canonical
    └── local-cohort-tableau-port.json          # session-local
```

Why the prefix and not a `local/` subdir: Anthropic's skill-creator rule keeps
references one level deep from `SKILL.md` (Claude's partial reads otherwise
miss nested files). The `local-` prefix is one-level-deep AND globbable
(`ls reference/local-*` lists every session-local addition).

Optionally, each `local-*.md` file may start with a header banner:

```markdown
> **Session-local enrichment** — added 2026-05-18 for Tableau migration project.
> Not canonical skill content; do not promote upstream.
```

Training mode is the only place this prefix is used. Build mode treats both
canonical and `local-` files as readable reference (it can use them) but does
not create new ones in this namespace.

## Workflow: resolve user input before planning

**Use the bash helpers in `scripts/api/` for any read-only discovery
against the existing Sigma workspace** — search, lookup, inspect. The
MCP wrappers (`scripts/api/mcp-search.sh`, `scripts/api/mcp-describe.sh`)
call Sigma's MCP server (`/mcp/v2`) using the same OAuth token as the
REST API and return richer output than the REST endpoints with less
bash plumbing.

For Sigma **function references** and **REST API endpoint shapes**
(not workspace discovery), use the native `mcp__claude_ai_Sigma_Docs__*`
tools — no bash, no auth, no `WebFetch`. See `reference/function-reference.md`
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

### Required reading before authoring (HARD GATE)

Before writing ANY spec JSON, `Read` the chunk files mapped to the task type
below. This is not optional, and not a "scan the index then proceed." The
agent must `Read` the actual chunk files in the current session and cite
chunk + section in the plan.

| Task type | Required chunks |
|---|---|
| Every build (always) | `reference/layout-and-cross-element.md` |
| Viz-heavy build (>2 chart kinds, KPI rows, pivots) | + `reference/element-shapes.md` |
| Formula-heavy build (custom calcs, metrics, Lookup, Rollup) | + `reference/function-reference.md` |
| Round-trip / edge-case work (POST failures, format fields, axis controls) | + `reference/scope-and-edge-cases.md` |

If chunks are skipped, the agent is operating on memory of prior sessions —
which is exactly how the 2026-05-19 regression happened (passthrough collapse +
metric carryover across DM switch). See `reference/history.md`.

The plan output (per the next section) must include a "Chunks Read"
line listing the files consulted. A plan without that line is incomplete
and not approvable.

### Plan content

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

## Load-bearing rules — always-loaded summary

Four rules carry most of the round-trip failures from prior sessions.
Inline here because they are too important to live only in chunks. Each
links to the chunk for full edge cases. **Read the chunks anyway** per
the hard gate above — these summaries are insurance, not substitutes.
**Always visually verify** the workbook in the UI after a POST/PUT —
the API doesn't validate cross-element column resolution or visualization
quality.

### 1. Passthrough is mandatory; the only carve-out is Lookup-derived columns

Every viz element (chart, KPI, pivot) declares the FULL passthrough column
set from its source table. Default is passthrough-all. Right-click drill in
the Sigma UI surfaces ONLY columns the viz declares — a 2-column chart has
a 2-column drill, period.

The ONLY exception: if the source table contains a `Lookup(...)`-derived
column that produces a phantom series in a specific viz (e.g. a chart
plotting `Sum([Metric])` accidentally splits by the Lookup column), strip
**that specific Lookup column** from **that specific viz** only.

This carve-out NEVER generalizes:
- It does not apply to base data-model columns.
- It does not apply to other vizs on the same page.
- It does not justify "no chart passthroughs beyond x/y axes" — that
  phrasing is the 2026-05-19 regression mode and is wrong.

Full rule + recipe: `reference/layout-and-cross-element.md` → "Drill-down corollary."

### 2. `[Metrics/<Name>]` resolution + hard rule on DM switch

`[Metrics/<Name>]` references resolve against the data-model element a
spec sources from. `mcp-describe.sh datamodel-element <dm> <el>` returns
the metric catalog FOR THAT ELEMENT. Treat that catalog as the source of
truth — if a metric isn't listed there, do not reference it from a spec
that sources off that element.

Slashes within metric names (`Cost/Member/Month`) are not safely
encodable as `[Metrics/Cost/Member/Month]`. Either rename the metric in
the data model, or fall back to a hand-derived formula. Never assume
slash-name references parse — and never claim "round-tripped through
GET" as evidence that they do; round-trip preserves strings, it does
not validate them at render.

**On data-model switch mid-session: re-derive every `[Metrics/...]`
reference from the new recon. Never carry metric names forward from a
previous DM's plan.** The 2026-05-19 regression was caused by carrying
`[Metrics/Cost per Unit] * [Metrics/Encounter Volume]` from the original
DM's plan into a spec sourced against a different DM that did not
contain those metrics.

Full rule: `reference/function-reference.md` → "Use data-model metrics" + `reference/scope-and-edge-cases.md` → "Metric resolution semantics."

### 3. Inference anchor — every formula traces to recon

Every formula in a proposed plan must trace to one of:
- a `[Metrics/X]` confirmed in `mcp-describe` output for the source element, OR
- a column declared on the source table that recon confirmed exists.

"Reasonable assumption" formulas are forbidden. If recon doesn't show the
field the user's prompt implies, the plan surfaces it as an Open Decision
(item 6 in the plan structure), it does NOT silently assume the field
exists. The cost of one extra clarification turn is far lower than the
cost of a plan + spec that fails at render time.

This applies equally to vague prompts ("build me a cost analysis") and
specific ones ("show NIM by region"). For vague prompts, the agent's job
is to lean into the recon and propose what's actually computable — not to
imagine a dashboard and hope the data supports it.

### 4. Control/column ID collision

A control's `controlId` MUST NOT match any column `name` or `id` on the
elements it filters. When names collide, Sigma resolves `[Date]` (and
similar bare references) to the control, not the column. Downstream
formulas like `Month([Date])` or `Year([Date])` silently break.

Always prefix controls or use a distinct name: `DateRange`, `StoreFilter`,
`PlanTypeCtrl`. When in doubt, fully-qualify column references in formulas:
`[<ElementName>/Date]` instead of `[Date]`.

Full rule: `reference/scope-and-edge-cases.md` → "Control/column ID collision."

---

The deeper edge-case checklist (column-declaration, explicit-`name`,
control wiring, visualization clarity, containers, `format` field shape,
summary-bar pattern, bar-chart `orientation` rule) lives in the chunks
linked from "Reference and examples" below. The 4 rules in this section
are the ones that, when violated, ship a broken workbook — so they're
inline.

## Publishing — use `publish-workbook.sh`

```bash
scripts/api/publish-workbook.sh post     workbooks/<name>/spec.json   # POST (auto-validates first)
scripts/api/publish-workbook.sh get-spec <workbookId> | jq . > workbooks/<name>/spec.json
scripts/api/publish-workbook.sh get-meta <workbookId>                  # url, name, path, folderId
```

The wrapper runs `validate-spec.py` before POST (fail-fast on silent-rewrite
gotchas) and uses `sigma_curl` for auth-injected, 401-retrying requests. No
`delete` subcommand — DELETE goes direct-curl so it hits the `ask` pattern in
`.claude/settings.json`.

PUT (full-spec update of an existing workbook) is not in the wrapper; use
direct curl with the same headers and run `validate-spec.py` manually first.

## Reference and examples

`reference/` is split into 5 focused files, all one level deep. Load only what
the current task needs:

- `reference/naming.md` — naming rubric (columns, metrics, controls, pages).
- `reference/function-reference.md` — function quick-reference (date / aggregate / scalar / numeric guards / strings / casting / column-reference syntax) + formula namespaces + `[Metrics/<Name>]` usage + Sigma_Docs MCP lookup convention for functions not listed here.
- `reference/element-shapes.md` — per-kind spec shape for every element (KPI, bar/line/area/combo, pie/donut, scatter, pivot, container, text, controls), the **bar-chart `orientation` rule**, series breakout / color-by, visualization clarity, the misleading-`Invalid kind` error pattern.
- `reference/layout-and-cross-element.md` — layout XML (24-col grid, `<GridContainer>`, `<LayoutElement>`), the page-structure pattern, the column-declaration rule + drill-down corollary, the explicit-`name` rule, `Lookup` / `Rollup` patterns, table `groupings`, summary-bar pattern, two-tier sourcing, the canonical recipe.
- `reference/scope-and-edge-cases.md` — what the code spec does NOT represent (KPI period comparison, pivot heatmap, axis-label rotation), GET-spec 500 cases, the `format` field (verified shape), warehouse-table fallback, verifying via generated SQL, twells89-adopted patterns (schema-drift fallback, persist-spec).
- `reference/history.md` — dated incident log. Inline rules in the chunks are evergreen; this file carries when each rule was verified and the incident that surfaced it.

`examples/` — known-good specs to seed generation. Treat as immutable
references; clone-and-modify rather than editing in place. Each `.json`
exemplar pairs with a sibling `.prompt.md` describing the source intent +
templated placeholders (when applicable).

  - **Single-page / minimal:**
    - `data-model-sourced-overview.json` — minimal data-model-fed dashboard.
    - `data-model-sourced-kpi-overview-with-containers.json` — KPI row + bar chart + detail table, wrapped in containers (canonical page-structure exemplar).
  - **Catalog / kitchen-sink:**
    - `data-model-sourced-multi-element-catalog.json` (Phase 7 — templated IDs) — single-page reference covering 6 chart kinds (bar, line, area, donut, scatter, pivot) + 3 KPIs + 4 control types (`list`, `date-range`, `text`, `segmented`) + multi-level `groupings` table (2-col `groupBy` + 3 calcs + sort) + plain table. The first exemplar to load when authoring a new visualization-heavy dashboard.
    - `data-model-sourced-multi-level-aggregated-table.json` (legacy — hardcoded IDs) — combo-chart + container + 4 controls + 3 KPIs + 1 table; covers `combo-chart` shape which the multi-element catalog omits.
    - `additional-workbook-features-chart-and-control-catalog.json` (legacy — hardcoded IDs) — 3 area-charts (stacking variants), combo, donut, **pie-chart**, scatter, 3 controls. Source when you need `pie-chart` or area-stacking-mode shapes.
  - **Pattern-specific:**
    - `data-model-sourced-cohort-pivot.json` (templated IDs) — two-tier sourcing (raw → derived cohort) + `Rollup(Min([Date]), [Cust Key], ...)` for first-purchase-per-customer + `Greatest(DateDiff(...), 0)` guard + pivot with weekly rows × weeks-since-first columns + KPI row + supporting line + bar charts. Clone for any cohort / retention / weeks-since-first-action prompt.
    - `data-model-sourced-multi-page-profitability-attrition.json` (Phase 7 — templated IDs) — **multi-page reference**. 4 pages (Profitability Overview / Drivers / Attrition Signals / Data Sources). Demonstrates per-page source-table architecture (`Lookup()` requires same-page siblings), horizontal-orientation rule for categorical bar charts, drill-passthrough, `format: {kind: "number", formatString: ...}` verified shape, data-model metrics. The canonical multi-page reference.

For data-model field-level mechanics (columns, metrics, relationships,
filters, controls, formatting, folders, column-level security, workflows)
defer to the upstream `sigma-data-models` skill — its `reference/` folder is
the authoritative answer for those topics.
