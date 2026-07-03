# Iteration Playbook

Sigma workbook spec JSON is **net-new to LLMs** — not in pretraining data, and
the public help docs don't always match the API. The fastest path to one-shot
quality is a tight feedback loop where every attempt becomes evidence and
recurring fixes get promoted into skills.

## The loop

```
recon  ─►  propose plan  ─►  draft  ─►  POST  ─►  GET back  ─►  visually verify  ─►  promote
  ▲                                                                                    │
  └────────────────────────────────  refine  ◄────────────────────────────────────────┘
```

The **visual verification** step is non-negotiable. The CREATE endpoint
returns HTTP 200 for specs whose cross-element column references can't be
resolved at render time — the workbook still gets created, but elements
silently fail to render. Trusting HTTP 200 alone produces broken dashboards.

## Session start (build mode)

Before the per-attempt protocol runs, a build-mode session opens with a
3-question `AskUserQuestion` gate (full spec in
`.claude/skills/sigma-workbook-conventions/SKILL.md` → "Session modes"):

- **Q1: Is your `.env` set up?**
  - Yes → run `bash scripts/api/_env.sh` to warm the token cache, then
    `scripts/api/whoami.sh` to actively validate the token against
    `/v2/files`. If `whoami` fails, surface the Sigma error and abort —
    don't continue into Recon with broken auth.
  - No → walk the user through `.env.example` + Sigma's "Administration →
    Developer Access" OAuth client setup, then re-prompt.
- **Q2: What data source?** (data model URL/slug / warehouse path / mixed)
- **Q3: What would you like to build, and where in Sigma?** (verbatim
  prompt + destination folder — written to the timestamped prompt file)

The gate captures raw inputs; the per-attempt protocol below picks up at
Step 1 (Recon).

## Per-attempt protocol

### 0. Required reading (HARD GATE before any spec authoring)

Before drafting a plan or writing any spec JSON, `Read` the chunk files
mapped to the task type. This is not optional and not satisfied by reading
the SKILL.md index alone.

| Task type | Required chunks |
|---|---|
| Every build | `.claude/skills/sigma-workbook-conventions/reference/conventions.md` + `.claude/skills/sigma-workbook-conventions/reference/workflows/plan.md` + `.claude/skills/sigma-workbook-conventions/reference/specification/schema.md` + `.claude/skills/sigma-workbook-conventions/reference/specification/layout.md` |
| Viz-heavy build | + per-kind files under `.claude/skills/sigma-workbook-conventions/reference/specification/` (`charts.md`, `kpis.md`, `tables.md`, etc.) |
| Formula-heavy build | + `.claude/skills/sigma-workbook-conventions/reference/specification/formulas.md` |
| Map-bearing build | + `.claude/skills/sigma-workbook-conventions/reference/specification/maps.md` |
| Round-trip / edge-case work | + `.claude/skills/sigma-workbook-conventions/reference/scope-and-edge-cases.md` + `.claude/skills/sigma-workbook-conventions/reference/workflows/validate.md` |

For the full task-type → chunks table (with more categories), see the
skill's `SKILL.md` → "Required reading before authoring."

The plan in step 2 must include a `Chunks Read:` line listing files
consulted. Plans without it are not approvable. This gate was added 2026-05-19
after the cold-start test session ran 2 builds without reading any chunk
file — see `reference/history.md` → "2026-05-19 — Cold-start test session."

### 1. Recon (do this BEFORE writing any spec)

Build a complete picture of the inputs before drafting. Save findings in the
prompt file so future iterations don't re-discover them.

```bash
# Folder — resolve url-id slug to the internal UUID.
scripts/api/find-file-by-urlid.sh <folder-urlId>

# Data model — list elements, then describe the one you'll source from.
# Returns SQL DDL with column names, types, descriptions, formulas, AND the
# metrics catalog with usage examples. Replaces hand-walking the JSON spec.
scripts/api/mcp-describe.sh datamodel <dataModelId>
scripts/api/mcp-describe.sh datamodel-element <dataModelId> <elementId>
```

If the data model has `metrics`, plan to use `[Metrics/<Name>]` rather than
hand-deriving aggregations — it preserves currency/percent formatting and
keeps a single source of truth.

### 2. Propose the plan; wait for approval

Workbook prompts often underspecify the dashboard — the user names the data
and the question, not the visualizations or the filter set. Surface a
written plan before writing JSON. The plan covers:

- **Data inventory.** What columns *are* available, and which assumed
  ones aren't (e.g. "no customer dimension; closest proxy is Order
  Number"). Force the user to correct before you build on a wrong
  premise.
- **Inference rationale.** One line per visualization: *why this chart,
  this dimension, this metric*. ("Quantity, not revenue, because
  popularity is a unit-volume question.")
- **Filter set with reasoning.** Filters in priority order with one-line
  reasons; note what you considered and dropped.
- **Layout sketch.** Block-diagram in text (header / KPI row / chart
  grid / detail). No XML yet.
- **Open decisions.** Anywhere you guessed (proxies, scope of joined
  data, whether to modify a shared resource). Phrase as yes/no
  questions.

Wait for explicit approval. The 60 seconds spent here saves multiple
iterations of rebuilding the wrong dashboard. If the user already gave
you an explicit plan, skip this and go straight to drafting.

### 3. Save the prompt verbatim

`workbooks/<name>/prompts/<YYYYMMDD-HHMM>.md` — full natural-language prompt
plus the recon findings (folder UUID, data-model element + columns + metrics
you'll use, interpretive choices made when the prompt is ambiguous), and the
approved plan from step 2.

### 4. Draft the spec

`workbooks/<name>/iterations/<YYYYMMDD-HHMM>.json`. Apply the rules in the
appropriate `reference/*.md` chunk
([formulas](../.claude/skills/sigma-workbook-conventions/reference/specification/formulas.md),
[per-element specification/](../.claude/skills/sigma-workbook-conventions/reference/specification/),
[layout](../.claude/skills/sigma-workbook-conventions/reference/specification/layout.md),
[scope-and-edge-cases](../.claude/skills/sigma-workbook-conventions/reference/scope-and-edge-cases.md)):

- Declare every column you'll reference downstream, with stable readable ids
  (`col-date`, `col-store-region`) — no implicit inheritance.
- Use `[Metrics/<Name>]` instead of redoing math.
- Controls bind by column `id`, not column name.
- Visualization clarity: titles + comparisons on every chart/KPI.
- Verified element kinds: `kpi-chart` (NOT `kpi`), `bar-chart`, `table`,
  `control`. See the kind-mismatch table.

Don't overwrite `spec.json` yet — that comes after the GET-back.

### 5. POST via the wrapper

```bash
scripts/api/publish-workbook.sh post workbooks/<name>/iterations/<file>.json
```

The wrapper:
- Runs `validate-spec.py` first (fail-fast on per-page layout, unplaced
  elements, empty containers, malformed column `format` shape, duplicate
  `controlId`, passthrough collapse on charts/pivots, and controlId/column
  collision on filtered elements).
- POSTs to `/v2/workbooks/spec` via the `sigma_curl` helper, which auto-
  injects `Authorization` and `Accept: application/json` headers and
  retries once on HTTP 401 (cache eviction + refetch). No env-prelude,
  no manual token chaining.
- Prints `{ workbookId, url, path }` on success, or the Sigma error
  body on failure.

**Never echo `$SIGMA_API_TOKEN` or `$SIGMA_CLIENT_SECRET`.** The token cache is
mode 0600 and gitignored; tokens never cross a tool boundary.

### 6. Read the response

- **HTTP 400** → read the `message` and iterate the spec. The error usually
  names the element + path (`pages[0].elements[1]: ...`). Save the new
  attempt as a fresh `iterations/<NEW-TIMESTAMP>.json` — don't overwrite.
- **HTTP 200** → response includes `workbookId`. Proceed to GET-back.

### 7. GET back; that's the new source of truth

```bash
scripts/api/publish-workbook.sh get-spec <workbookId> \
  | jq . > workbooks/<name>/spec.json
```

The wrapper sets `Accept: application/json` automatically (the GET endpoint
returns YAML by default). Sigma normalizes layout XML (adds prolog) and may
auto-fill default fields. The GET, not your input, is the new baseline.

### 8. Visually verify

Open the workbook URL. Confirm every element actually renders with data:

- KPIs show numbers (not blank, not NaN, format applied).
- Charts have axes with values, sort order matches expectation.
- Controls populate with values and filter every dependent element.
- Table shows the columns and rows you expected.

A spec is not "done" until visual verification passes. The CREATE endpoint
will not catch broken cross-element column references, missing titles, or
unreadable formats.

### 9. Capture user feedback (when applicable)

If the user UI-fixes something, GET the spec again and diff against your
previous version:

```bash
TS=$(date +%Y%m%d-%H%M)
scripts/api/publish-workbook.sh get-spec <workbookId> \
  | jq . > workbooks/<name>/iterations/${TS}-from-sigma.json

diff <(jq -S 'del(.workbookId, .url, .documentVersion, .latestDocumentVersion, .ownerId, .createdBy, .updatedBy, .createdAt, .updatedAt)' workbooks/<name>/spec.json) \
     <(jq -S 'del(.workbookId, .url, .documentVersion, .latestDocumentVersion, .ownerId, .createdBy, .updatedBy, .createdAt, .updatedAt)' workbooks/<name>/iterations/${TS}-from-sigma.json)
```

Read the diff like a code review. Each change the user made is a lesson —
extract it, then update the skill / memory / exemplar accordingly.

### 10. Diff vs the closest exemplar

```bash
diff <(jq -S . workbooks/_exemplars/<closest>.json) \
     <(jq -S . workbooks/<name>/spec.json)
```

Look for shape divergence (missing elements, unusual source patterns) that
suggests either a bug or a candidate new exemplar.

### 11. Record findings + commit

Append a row to `workbooks/<name>/notes.md` iteration log: what worked,
what broke, what got promoted. Then commit:

```bash
git add workbooks/<name> && git commit -m "iter <name>: <one-line summary>"
```

Each iteration in `git log` is the diffable audit trail.

## Promotion rule

Promote a fix into a skill when ANY of these is true:

- A fix **recurs across 2+ iterations** in any workbook (proven pattern).
- A **single net-new working shape** is discovered that future workbooks of
  this kind will need (e.g. KPI element shape, list-control wiring).
- A **doc/API mismatch** is verified (e.g. `kpi` vs `kpi-chart`) — these are
  high-value because they're invisible from public docs.

Where to put it:

| Lesson type | Destination |
|-------------|-------------|
| Naming / layout / general workbook conventions | `.claude/skills/sigma-workbook-conventions/reference/naming.md` or `reference/conventions.md` |
| Function signatures / formula namespaces | `.claude/skills/sigma-workbook-conventions/reference/specification/formulas.md` |
| Element shape mechanics (KPI/bar/pie/scatter/pivot/controls) | `.claude/skills/sigma-workbook-conventions/reference/specification/<kind>.md` (e.g., `charts.md`, `kpis.md`, `tables.md`, `controls.md`, `maps.md`) |
| Layout XML, cross-element formulas, groupings, summary-bar | `.claude/skills/sigma-workbook-conventions/reference/specification/layout.md` + `reference/conventions.md` |
| Scope-of-code limits, edge cases, format field, fallbacks | `.claude/skills/sigma-workbook-conventions/reference/scope-and-edge-cases.md` |
| Pattern-specific (e.g. financial recon variance formula) | `.claude/skills/<pattern-skill>/reference/<topic>.md` |
| A whole spec that exemplifies a pattern | `workbooks/_exemplars/<pattern>-<shape>.json` |
| Account-specific (folder IDs, broken helpers, staging quirks) | Memory only — these don't belong in a shareable skill |

If you find yourself re-explaining the same thing in prompts, that's the
signal to promote. The point of skills is that recurring knowledge stops
being re-invented per session.

## When to start a new exemplar

When you produce a spec that would serve as a good reference for future
generations of the same pattern:

```bash
cp workbooks/<name>/spec.json workbooks/_exemplars/<pattern>-<shape>.json
git add workbooks/_exemplars && git commit -m "exemplar: <pattern> <shape>"
```

Naming convention: `<source-pattern>-<element-shape>.json` (e.g.
`data-model-sourced-simple-overview.json`,
`data-model-sourced-kpi-chart-table-controls.json`). Exemplars are
treated as immutable — prefer adding new ones over modifying old.

## Anti-patterns

- **Trusting HTTP 200 as "done."** It only validates structure, not
  cross-element column resolution. Always visually verify.
- **Editing `spec.json` directly without saving the iteration.** You lose the
  evidence of what worked.
- **Letting prompts drift.** If you tweak a prompt across attempts, save each
  variant; a working prompt is reusable.
- **Promoting too eagerly on recurring "fixes" that were really one-time
  account/data quirks.** Account specifics go to memory, not skills.
- **Hand-editing exemplars.** They're anchors. If an exemplar needs an edit,
  it usually means it's wrong — replace it instead.
- **Echoing tokens or secrets.** The cached token at `/tmp/.sigma_token` is
  mode 0600 and never logged. Never `echo $SIGMA_API_TOKEN` or paste it into a
  prompt/file/commit.
- **Skipping recon** because "the user told me what they want." Recon catches
  metric reuse, column-name realities, and folder-ID mismatches before they
  become an HTTP 400.
- **Skipping the plan proposal** and jumping straight from recon to JSON.
  The user often hasn't specified the visualizations or the filter set;
  inferring silently and shipping is a recipe for tearing the dashboard
  apart on first review. Surface the inference, get a yes, then build.
- **Trusting that every column in `GET /v2/dataModels/{id}/spec` is
  queryable.** Some are stale/orphaned and fail formula resolution at
  POST. Probe unfamiliar columns with a one-table POST before building
  on them.
