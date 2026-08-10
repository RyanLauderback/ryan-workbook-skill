---
name: sigma-workbook-conventions
description: >-
  Use when authoring, editing, reviewing, or publishing any Sigma workbook
  or dashboard JSON spec in this repo — including whenever the user says
  "start build mode", mentions Sigma workbooks, dashboards, or specs, asks
  to build/edit/POST/PUT a workbook, references data models, KPIs, charts,
  tables, controls, layouts, filters, maps, or the `/v2/workbooks/spec`
  endpoint. Encodes project conventions on element naming, page/folder
  layout, ID semantics on POST/PUT, secret handling, and common pitfalls
  when generating Sigma JSON specs. Pair with `sigma-data-models` for
  field-level reference, and with a domain-specific workbook-pattern
  skill when one is available for the dashboard type being built.
---

# Sigma Workbook Conventions

Project-wide conventions for Sigma workbook/data-model specs. Read this before
generating or editing any `spec.json` in `workbooks/` or `examples/`.

## Inputs

This skill is reference-only — no scripts. It assumes:

- Sigma auth is bootstrapped by the repo-local `scripts/api/_env.sh`
  (see "Auth is auto-bootstrapped" below). The upstream `sigma-api`
  plugin is optional — used only when `SIGMA_TOKEN_FETCHER` points at
  its `get-token.sh`.
- `sigma-data-models` is available for endpoint mechanics and field semantics.
- The local mirror at `vendor/sigma-agent-skills/` is available to consult when a
  field-level question isn't answered here.

## Session kickoff

Sessions start with a 3-question `AskUserQuestion` gate. The user can trigger
it explicitly with `start build mode`, or it fires implicitly on any prompt
that asks to build/edit/POST a Sigma workbook. The gate captures the raw
inputs the planner needs; the plan-first workflow (below) is what
authorizes any state-changing API call.

### The 3-question kickoff

The very first action of a build-mode session is `AskUserQuestion` with three
questions. Each question has a defined branch behavior:

**Q1: Is your `.env` set up?**

- **Yes** — Claude runs two actions in sequence to verify auth end-to-end:
  1. `bash scripts/api/_env.sh` — warms the token cache at a per-user `$SIGMA_TOKEN_CACHE` path (55-min TTL).
  2. `scripts/api/whoami.sh` — actively probes `/v2/files?limit=5` to confirm the token works against the live API and surfaces 5 recent files the user can confirm visually.

  Why both: passive bootstrap (`_env.sh`) succeeds even when credentials are wrong as long as `.env` has the variables filled in. The active `whoami` probe catches expired clients, wrong region URLs, and revoked tokens *before* recon starts — not mid-build.

- **No** — Claude shares `.env.example` contents + a link to Sigma's "Administration → Developer Access" docs for OAuth client creation, then re-prompts Q1 once the user confirms setup.

**Q2: What data source will you build against?**
- **Data model** (recommended) — URL/slug (`Customer-Financials-461QUZu2VPny8KxImgSmfF`)
  or name. Prefer this when one plausibly covers the request: confirmed
  live (2026-08-07, `reference/history.md`) that a data model's full
  spec — friendly column names, descriptions, and the metrics catalog —
  comes back in a single REST call, while a raw warehouse table's REST
  equivalent returns only raw warehouse column names, no metrics. See
  `reference/specification/sources.md` → "If no data model fits, fall
  back to `warehouse-table` — don't manufacture a model" for when a
  table is the right call anyway.
- Warehouse table path (`<CONN>.<DB>.<SCHEMA>.<TABLE>` or `/t/<id>` URL).
  **If the user names table(s) without their schema/DB, ask for it here**
  before Recon — confirmed live that resolving a bare table name without
  a known schema means guessing across schemas, which cost 29 wasted
  calls with zero hits in one real test. See `reference/workflows/discover.md`
  → "Routing: raw warehouse tables."
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
        [enters Recon — GET /v2/dataModels/{id}/spec on the data model]
        [drafts the Plan, surfaces for user approval]
```

If `whoami.sh` returns non-zero, the agent surfaces the Sigma error verbatim
and stops — does NOT continue into Recon with broken auth.

### Plan-first reaffirmation

The kickoff captures **raw inputs**. It does NOT replace the plan-first workflow.

After the kickoff, the agent proceeds through Recon → Plan proposal → User approval → Build → GET-back → Visual verify, per `docs/iteration-playbook.md`. **Plan approval is the only authorization for state-changing API calls** (POST/PUT to `/v2/workbooks/spec`, `/v2/dataModels/*/spec`). The 3-gate does not pre-authorize anything except the auth warm-up itself.

### Optional: session-local enrichment via `local-` prefix

To add project-specific context (Tableau migration notes, account-specific
exemplars, industry patterns) directly to the skill, use a **`local-`
filename prefix** on the added file — e.g. `reference/local-tableau-migration.md`
or `examples/local-cohort-tableau-port.json`. The prefix stays at the same
directory level as canonical files so partial reads surface it, and
`ls reference/local-*` lists every enrichment cleanly. Optionally open the
file with a banner (`> **Local enrichment** — <date>, <purpose>`) so future
readers know it's opt-in, not canonical.

## Discovery: use the bash helpers

Read-only discovery against the Sigma workspace routes through the bash
helpers in `scripts/api/`. Full protocol — routing table
(name/URL/messy-prose), REST-first / MCP-blocked status, `mcp-describe`
batching rules, resolver JSON shape, friendly-vs-raw column-name
normalization, troubleshooting — lives in `reference/workflows/discover.md`.
Load it before any recon step.

For Sigma **function references** and **REST API endpoint shapes** (not
workspace discovery), use the native `mcp__claude_ai_Sigma_Docs__*`
tools instead. See `reference/specification/formulas.md` → "Looking up
Sigma functions."

### Auth is auto-bootstrapped

Each `scripts/api/*.sh` sources `_env.sh` on first call — loads `.env`
(or reads already-exported `SIGMA_*` env vars, e.g. in Claude Code web
sessions), mints an OAuth token via the repo-local
`scripts/api/get-token.sh` (a self-contained `client_credentials`
exchange against `/v2/auth/token`), and caches it at a per-user path
under `$SIGMA_TOKEN_CACHE` (mode 0600, 55-min TTL). Callers pass no env vars,
no tokens. **CLI and web run identical code** — the skill owns auth
end-to-end rather than delegating to the upstream `sigma-api` plugin
(which isn't installed in web sessions opened from a downloaded zip).
Override the fetcher via `SIGMA_TOKEN_FETCHER=/abs/path/to/get-token.sh`
if you want to point at the plugin's fetcher or a custom one.

### Installing this skill in a new project

When dropping this skill into another project, merge the rules in
`recommended-permissions.json` (alongside this `SKILL.md`) into that
project's `.claude/settings.json` under `permissions`. With those rules
in place, every script in `scripts/api/*` runs without an approval
prompt; `curl` calls for workbook authoring/publishing still prompt
(by design — they're state-changing).

### Invoking scripts — workspace-level, not skill-bundled

Scripts live at the **workspace root** (`scripts/`, `scripts/api/`), not
inside this skill's folder. This is intentional: the same scripts are
shared across every skill and workbook in this workspace, so bundling
them per-skill would fork identical code across skills. When the
workspace root is your working directory, invoke `scripts/api/*.sh` and
`python3 scripts/*.py` **bare** — no `cd <repo> &&` prefix needed. The
`Bash(scripts/api/*)` allowlist pattern matches bare invocations and
runs silent; prepending `cd` defeats the pattern match, adds verbosity,
and creates no functional benefit.

## Sources of truth

This skill is verified-from-incident recipes + gotchas layered on top of
two authoritative sources:

1. **Sigma OpenAPI** — canonical schema for every request/response shape
   and field. `https://help.sigmacomputing.com/openapi/sigma-computing-public-rest-api.json`
2. **Existing workbooks on the user's org** — concrete working specs,
   accessible via `GET /v2/workbooks/{id}/spec` (or via
   `scripts/api/publish-workbook.sh get-spec <wb-id>`).

**When this skill and the OpenAPI disagree, the OpenAPI wins.** For the
`jq` recipes to fetch and inspect the OpenAPI, and the schema-drift
fallback protocol, see `reference/specification/schema.md` → "Consulting
the OpenAPI" and "Schema-drift signal."

## Spec format — JSON or YAML

The Sigma API accepts both `application/json` and `application/yaml`
on `POST /v2/workbooks/spec`. **This skill's tooling defaults to JSON**
— all canonical exemplars in `examples/` are `.json`,
`scripts/validate-spec.py` reads JSON, `scripts/workbook-manifest.py`
reads JSON, `scripts/api/publish-workbook.sh` doesn't care.

YAML is fine for hand-authoring and the upstream `sigma-workbooks`
skill prefers it for human readability. If you receive a YAML spec
from a user or upstream tool, convert via `yq -o=json` or PyYAML
before running this skill's validators. Don't migrate existing JSON
exemplars to YAML — the tooling expects JSON and a mixed-format
`examples/` directory is harder to maintain.

## Workflow: propose a plan before building

### Required reading before authoring (HARD GATE)

Before writing ANY spec content, `Read` the chunk files mapped to the
task type below. This is not optional, and not a "scan the index then
proceed." The agent must `Read` the actual chunk files in the current
session and cite chunk + section in the plan.

| Task type | Required chunks |
|---|---|
| Every build (always) | `reference/conventions.md` + `reference/workflows/plan.md` + `reference/workflows/composition.md` + `reference/specification/schema.md` + `reference/specification/layout.md` |
| Viz-heavy build (>2 chart kinds, KPI rows, pivots) | + each `reference/specification/<kind>.md` for the kinds in the plan (`charts.md`, `kpis.md`, `tables.md`, etc.) |
| Formula-heavy build (custom calcs, metrics, Lookup, Rollup) | + `reference/specification/formulas.md` |
| Conditional-formatting build (table/pivot cell coloring) | + `reference/specification/tables.md` |
| Styling / theming build (container styling, background images, `themeOverrides`, theme color references) | + `reference/specification/containers.md` + `reference/specification/theming.md` |
| Image / divider / embed / dynamic-text build | + `reference/specification/others.md` + `reference/specification/text.md` + `reference/specification/dynamic-values.md` (for `{{formula}}` interpolation) |
| Map-bearing build (`geography-map`, `point-map`, `region-map`) | + `reference/specification/maps.md` |
| Multi-surface build (tabbed containers, modal pages, navigation, page breaks) | + `reference/specification/pages.md` + `reference/specification/layout.md` → "Five-tag grammar" |
| Interactive build (buttons, on-select, overlays, tab-switching, input-table writeback) | + `reference/specification/actions.md` + `reference/specification/dynamic-values.md` |
| Editable / writeback build (input tables, `insert-rows`/`delete-rows`) | + `reference/specification/input-tables.md` + `reference/specification/actions.md` |
| Agent / chat build (`agents[]`, `chat` element, agent tools) | + `reference/specification/agents.md` + `reference/specification/actions.md` + `reference/specification/dynamic-values.md` |
| Scenario / what-if / forecast build | + `reference/patterns/scenario-modeling.md` + `reference/specification/controls.md` + `reference/specification/input-tables.md` |
| Round-trip / edge-case work (POST failures, format fields, axis controls) | + `reference/scope-and-edge-cases.md` + `reference/workflows/validate.md` + `reference/capability-ledger.md` |
| Deciding whether a feature is "supported" (before writing any "not supported" claim) | + `reference/capability-ledger.md` → the retest protocol, first |
| From-image build (screenshot / mockup reproduction) | + `reference/workflows/from-image.md` (load BEFORE data discovery) |

If chunks are skipped, the agent is operating on memory of prior sessions —
which is exactly how the 2026-05-19 regression happened (passthrough collapse +
metric carryover across DM switch). See `reference/history.md`.

The plan output (per the next section) must include a `Chunks Read:`
line listing the files consulted. A plan without that line is incomplete
and not approvable. Full plan-first methodology in
`reference/workflows/plan.md`.

### Plan content

Workbook prompts often underspecify the dashboard — the user names the data
and the question, not the visualizations or the filter set. Do not jump
straight to JSON. Before authoring any spec, surface a written plan and
wait for explicit approval. The plan has 6 required sections — Destination,
Data inventory, Inference rationale, Filter set with reasoning, Layout
sketch, Open decisions. **Full spec, wording, and worked example:
`reference/workflows/plan.md` → "Plan content — 6 required sections."**
This summary is insurance, not a substitute — `plan.md` is already
required reading on every build per the hard gate above.

If the user has already given you an explicit plan, skip to building —
don't re-propose.

### Approval model — plan is the only gate

Plan approval authorizes **every state-changing API call covered by the
plan, except DELETE** — POST/PUT to `/v2/workbooks/spec` and
`/v2/dataModels/*/spec` run silently, DELETE always asks regardless of
what the plan says. **Full rules and rationale:
`reference/workflows/plan.md` → "Approval model — plan is the only
gate."** The practical upshot: the plan must name the destination
folder and any shared object it intends to mutate before you build —
if a state-changing call wasn't covered in the plan, amend the plan
first rather than making it.

## Conventions

Quick-reference summaries — insurance, not substitutes. The naming
rubric's full detail lives in `reference/naming.md`; the cross-cutting
rules (passthrough mandate, ID collisions, etc.) live in
`reference/conventions.md`, required reading on every build per the
hard gate above.

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

### ID semantics

Workbook spec IDs (pages, elements, columns) are **preserved verbatim**
on POST/PUT. Use stable human-readable IDs (`col-revenue`,
`page-overview`, `tbl-transactions-master`) and reuse them across
iterations. Layout `elementId` references stay valid across POST/PUT.

Verified 2026-07-02: skill-authored workbooks retain 100% of their
kebab-case IDs after POST → GET round-trip. See
`reference/specification/schema.md` → "ID rules" and
`reference/workflows/crud.md` → "ID preservation on CREATE."

Note: `sigma-data-models` (data model round-trip endpoint) has its own
ID semantics and is separate from this workbook-spec behavior.

### Constraints (from upstream `sigma-data-models`)

- Partial updates are NOT supported — both CREATE and UPDATE require the complete spec.
- A single model cannot contain multiple identically-named tables.
- Python elements, and references to other Sigma elements in custom
  SQL are **not supported** by the *data-model* round-trip endpoints
  (`sigma-data-models` skill scope). Avoid generating these in a data-model spec.
  **Correction (2026-08-03):** this line previously also named input tables,
  which read as a blanket prohibition and contradicted
  `reference/specification/input-tables.md`. Input tables are a
  *workbook* spec element (`kind: "input-table"`), not a data-model
  construct — they are fully supported, **live-POST verified**
  (2026-08-04, Wave 3 / C5) after starting from GET-spec confirmation
  against 5 real production workbooks holding 27 input-table instances
  combined. See `reference/capability-ledger.md`. This constraint is
  scoped to data-model round-trip only.

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

## Load-bearing rules — always-loaded summary

Four rules carry most of the round-trip failures from prior sessions.
Inline here as one-line summaries because they're too important to live
only in chunks. **Read `reference/conventions.md` for the full versions**
— required on every build per the hard gate above. These summaries are
insurance, not substitutes. **Always visually verify** the workbook in
the UI after a POST/PUT — the API doesn't validate cross-element column
resolution or visualization quality.

1. **Passthrough is mandatory.** Every viz element declares the full
   passthrough column set from its source table. The only carve-out is
   stripping a `Lookup`-derived column that produces a phantom series
   from that one viz — the exception is scoped to the specific viz;
   generalizing it to "no passthroughs anywhere" is what caused the
   2026-05-19 regression.
   `reference/conventions.md` → "Passthrough mandate."
2. **`[Metrics/<Name>]` resolution + DM-switch hard rule.** Metrics
   resolve against the data-model element a spec sources from. On any
   data-model switch mid-session, re-derive every `[Metrics/...]` from
   the new recon — carrying metrics forward from a previous DM's plan
   invalidates them silently, and the resulting POST fails at render
   without any spec-level error.
   `reference/conventions.md` → "`[Metrics/<Name>]` resolution +
   DM-switch hard rule."
3. **Inference anchor — every formula traces to recon.** Every formula
   in a plan must trace to a `[Metrics/X]` in the recon catalog OR a
   column declared on the recon-confirmed source. "Reasonable
   assumption" formulas are forbidden; missing fields surface as Open
   Decisions. `reference/conventions.md` → "Inference anchor."
4. **Control/column ID collision.** A control's `controlId` must NOT
   match any column `name` or `id` on filtered elements. `[Date]`
   resolves to the control before the column when names collide;
   downstream `Month([Date])` silently breaks.
   `reference/conventions.md` → "Control/column ID collision."

The deeper edge-case checklist (explicit-`name`, rename-cascade,
bar-chart orientation, summary-bar, two-tier sourcing) lives in
`reference/conventions.md`. The 4 rules above are the ones that, when
violated, ship a broken workbook.

## Publishing

Use `scripts/api/publish-workbook.sh` for POST / PUT / GET / metadata —
it auto-runs `validate-spec.py` before writes, injects auth, 401-retries
via `sigma_curl`, and auto-runs `audit-workbook-schema.sh` after every
successful POST/PUT to catch `error`-typed columns that
`verify-workbook.sh` misses. Full subcommand reference, DELETE via
direct-curl, and the response-only-fields-to-strip list live in
`reference/workflows/crud.md`.

## Reference and examples

`reference/` is split into four groups. Load only what the current task
needs — see "Required reading before authoring" above for the hard-gate
mapping.

**Top-level orchestration:**

- `reference/conventions.md` — the ryan-specific cross-cutting rules
  (passthrough mandate, drill-down corollary, explicit-`name` rule,
  rename-cascade corollary, `[Metrics/<Name>]` resolution + DM-switch
  hard rule, control/column ID collision, bar-chart orientation,
  summary-bar pattern, two-tier sourcing, notes-promotion guardrail).
  **Required on every build.**
- `reference/scope-and-edge-cases.md` — what the code spec does NOT
  represent (chart series theme palette, pivot heatmap status,
  axis-label rotation), GET-spec 500 cases, warehouse-table fallback,
  verifying via generated SQL.
- `reference/history.md` — dated incident log. Inline rules in the
  chunks are evergreen; this file carries when each rule was verified
  and the incident that surfaced it.
- `reference/naming.md` — naming rubric (columns, metrics, controls,
  pages) — style guide, not load-bearing.

**Workflow files (`reference/workflows/`):**

- `plan.md` — the 6-section plan format, `Chunks Read:` requirement,
  plan-is-the-only-gate approval model. **Required on every build.**
- `composition.md` — design judgment, not spec shape: the sizing ladder
  (single thing / focused view / dashboard), when to stop and ask, three
  defaults (hidden base tables, sort ranked tables by the ranked metric,
  never expose intermediate joins), and surfacing structural choices in
  the build summary. Ported 2026-08-03 from the real upstream
  `sigma-workbooks` skill. **Required on every build.**
- `crud.md` — POST/GET/PUT mechanics + ID preservation on POST +
  response-only fields to strip on PUT + the `publish-workbook.sh`
  wrapper.
- `discover.md` — REST-first discovery (`search-files.sh` sequencing,
  data-model-vs-table routing, raw-table schema-confirmation rule),
  friendly-vs-raw warehouse name normalization, MCP status (blocked).
- `validate.md` — `validate-spec.py` (pre-submit, 17 checks) +
  `verify-workbook.sh` (SQL-compile check) +
  `audit-workbook-schema.sh` (data-layer schema audit, auto-run by
  `publish-workbook.sh`) + cryptic-error decoding table.
- `from-image.md` — image-to-spec workflow (screenshot, mockup,
  PDF, BI-tool export). Load BEFORE data discovery when the user
  supplies a target image.

**Specification files (`reference/specification/`):**

Per-element-kind recipes + gotchas. Each file opens with the relevant
OpenAPI `jq` recipe. Dated verification status and correction history
for these files lives in `reference/history.md` and
`reference/capability-ledger.md`, not here — this list is a routing
index, not a changelog.

- `schema.md` — top-level workbook spec shape, response-only fields,
  ID preservation on POST, top-level `folders` + `themeOverrides` +
  `theme` element kind, minimal working example.
- `formulas.md` — formula DSL: column-reference rules,
  `[Metrics/<X>]`, boolean operators trap (`Not` requires space),
  JSON dot notation, window functions, `&` for string concat.
- `formatting.md` — d3-format + strftime cheat sheets, SI prefix
  currency.
- `layout.md` — top-level layout XML (24-col grid), XML-vs-object
  `layout` distinction, `<GridContainer>` vs `<LayoutElement>`
  silent failure, `gridTemplateRows` normalization quirk,
  page-structure pattern.
- `containers.md` — `kind: container` + `style` (bg + border) +
  `backgroundImage` (`source:{kind:"url"|"upload"}` + fit/align/tiling
  style) + 5-recipe catalog.
- `charts.md` — bar/line/area/combo/scatter/pie/donut + canonical
  `columnId`/`columnIds` axis shape + `refMarks` + `trendlines` +
  `dataLabel`/`seriesDataLabel` + 3-variant `color` channel
  (single/category/scale) + `top-n` filter fields + `gap` for bar
  spacing.
- `kpis.md` — `kpi-chart` shape (`value.columnId`), sparkline via
  date dimension, styled-name object form, element-level `layout`
  object (`anchor`), polymorphic `description`, no-delta limitation.
- `tables.md` — `table` + `pivot-table` +
  `conditionalFormats` (4 variants) + `tableStyle` +
  `tableComponents` + styled-name + `noDataText` + `summary` bar.
  (`input-table` moved to `input-tables.md`.)
- `controls.md` — 14 accepted controlType values (`list`, `date-range`,
  `date`, `text`, `text-area`, `number`, `number-range`, `slider`,
  `range-slider`, `toggle`/`switch`/`checkbox`, `segmented`,
  `hierarchy`) + 8 date-range modes + `top-n` filter + multi-binding
  patterns + control/column collision reference. Note:
  `controlType: "dropdown"` / `"radio"` currently POST-reject; use
  `list + selectionMode: "single"` instead.
- `text.md` — Markdown subset + inline HTML (color, font-size,
  single-family font, paragraph alignment) + `{{formula}}` dynamic
  text embeds with d3 format suffix.
- `others.md` — `divider` (with `direction`/`align`/`style`) +
  `image` + `embed` elements + `{{formula}}` in URLs +
  `data:image/svg+xml;base64,...` inline SVG.
- `theming.md` — top-level `themeOverrides` (`pageWidth`, `space`, +
  14 more fields cataloged from the live schema) + the reusable
  `{kind:"theme", ref}` color-value form usable across many elements'
  color fields.
- `pages.md` — `tabbed-container` (labels-only element + flat
  tab-content siblings), `type:"modal"` pages, `navigation`,
  `page-break`.
- `actions.md` — `button` element + the `actions[]`/`effects[]`
  vocabulary: all 9 effects (`set-control-value`, `clear-control`,
  `open-overlay`/`close-overlay`, `navigate`, `select-tab`,
  `open-url`, `insert-rows`/`delete-rows`).
- `dynamic-values.md` — the slot → accepted-form matrix for dynamic
  values: all 5 structured `{type: ...}` forms (`constant`, `formula`,
  `column`, `control`, `agent-input`), plus `{{formula}}` string
  interpolation.
- `input-tables.md` — `input-table` element: `empty`/`linked` source,
  all 6 column shapes (system, key, editable, dropdown, formula, plus
  `filters`/`sort`/`conditionalFormats`), `insert-rows`/`delete-rows`
  writeback.
- `agents.md` — top-level `agents[]` + `chat` element + agent
  `tools[].steps[]` (reusing the `actions.md` effect vocabulary,
  `agent-input` for model-supplied values) + `{{formula}}` in
  `instructions`.
- `maps.md` — `geography-map` + `point-map` + `region-map` (with
  `regionType` enum) + single-vs-array shape gotcha on binding
  fields.
- `sources-warehouse.md` — path formats per warehouse + formula
  prefixes + friendly-name normalization.
- `sources.md` — `table` / `data-model` / `join` / `union` / `sql` /
  `transpose` source kinds + two-tier sourcing pattern reference.
- `example-full.yaml` — multi-page reference spec (KPIs, charts, join
  sources, controls, custom layout) authored locally for this skill.
  Read this when in doubt about overall shape.

**Pattern files (`reference/patterns/`):**

Compositions of already-verified `specification/` primitives, not a
spec surface of their own — deliberately filed separately.

- `scenario-modeling.md` — forecasting via `CallVariant` + what-if via
  parameter controls + 2 structural gotchas (controls can't usefully
  filter input-tables/pivots; input-table rows can't be seeded from
  code).

`examples/` — known-good specs to seed generation. Clone-and-modify
rather than editing in place. `.prompt.md` sidecars (where present)
describe design intent. Match your task along **three independent
axes** — page complexity, calculation complexity, and writeback
complexity — not one ladder; a build can be simple on one axis and
complex on another (e.g. a 1-page dashboard with a cohort pivot).

**1. Simple 1-page dashboards:**
- `data-model-sourced-overview.json` — smallest data-model-fed dashboard.
- `data-model-sourced-single-page-inventory-health.json` — 10-element, conditional formatting + two shared controls. Canonical minimal ops-triage exemplar.
- `dashboard-department-scorecard.json` — KPI row (period-comparison + timeline styling) + one ranked chart + one ranked table, base table on a hidden page. **First load for a plain read-only exec dashboard, no interactivity.**

**2. Complex multi-page dashboards:**
- `data-model-sourced-sales-command-center.json` — 50-element 3-page workbook. **First load for any modern multi-page build.**
- `data-model-sourced-exec-kpi-scorecard.json` — 35-element 3-page workbook with a US-state `region-map` and a two-tier anomaly-detection derived table. Clone for geographic viz or anomaly detection.
- `data-model-sourced-multi-page-profitability-attrition.json` — 4-page reference with per-page source tables + `Lookup()` demographic passthrough.

**3. Specialized calculation approaches:**
- `data-model-sourced-cohort-pivot.json` — two-tier sourcing (raw → derived) + `Rollup` + weeks-since-first-action pivot. Clone for cohort/retention.
- `data-model-sourced-multi-level-aggregated-table.json` — a live 3-level `groupings` example (`tables.md`'s own inline example only goes 2 levels).
- `reference/patterns/scenario-modeling.md` — `CallVariant` forecasting + what-if parameter controls. **No example workbook yet** — a documented gap, not silently missing; don't assume one exists.

**4. Simple writeback (notes / value overrides, no agent):**
- **No example yet** — a documented gap. Compose directly from `reference/specification/input-tables.md`: an `input-table` with editable columns, no agent, no buttons beyond `insert-rows`/`delete-rows` if needed.

**5. Complex writeback (scenario modeling + approval workflow):**
- `input-table-agent-scenario-planner.json` — editable input-table + AI agent generating scenario rows via `agent-input`. Covers "enter parameters, generate a forecast." **Does not cover an approval handoff to a second user** — a documented gap; if asked for one, compose from already-verified primitives (a `status` column, a filtered approver view, inline cell editing — there's no `update-rows` effect, so approval is direct edit, not a button) and live-verify the composed shape before treating it as settled.

**Other (cross-cutting, not use-case-specific):**
- `data-model-sourced-multi-element-catalog.json` — 6 chart kinds, 3 KPIs, 4 control types side by side in one page. Reach for this when you need to see several chart kinds at once, not as a realistic dashboard to clone wholesale.
- `styled-card-dashboard.json` — five-recipe element styling system (card framing, accent borders, subtle controls) and the canonical nested-`GridContainer` page-structure example (see `reference/specification/layout.md`).

For data-model field-level mechanics (columns, metrics, relationships,
filters, controls, formatting, folders, column-level security, workflows)
defer to the upstream `sigma-data-models` skill — its `reference/` folder is
the authoritative answer for those topics.
