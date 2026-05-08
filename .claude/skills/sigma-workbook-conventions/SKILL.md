---
name: sigma-workbook-conventions
description: >-
  Use when authoring, editing, or reviewing any Sigma workbook/data-model spec
  in this repo. Encodes project conventions on element naming, page/folder
  layout, ID semantics on create-vs-update, secret handling, and common
  pitfalls when generating Sigma JSON specs. Pair with sigma-data-models for
  field-level reference and with a domain-specific skill (e.g. sigma-fin-recon)
  when one is available.
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

## Workflow: propose a plan before building

Workbook prompts often underspecify the dashboard — the user names the data
and the question, not the visualizations or the filter set. Do not jump
straight to JSON. Before authoring any spec, surface a written plan and
wait for explicit approval.

The plan must include:

1. **Data inventory.** What table(s) and which columns are actually
   available — pulled from `GET /v2/dataModels/{id}/spec`, not assumed.
   Name any column that's missing from your assumed schema (e.g. there
   *is* a customer dimension; there *isn't* a margin field) so the user
   can correct before you build on a wrong premise.
2. **Inference rationale.** For each visualization you propose, one line
   on *why this chart, this dimension, this metric* answers the user's
   question. "Quantity, not revenue, because popularity is a unit-volume
   question" beats "bar chart of products."
3. **Filter set with reasoning.** Filters aren't free — each one earns
   its place by mapping to an axis the user is likely to interrogate.
   List the filters in priority order with a one-line reason, and note
   what you considered and dropped.
4. **Layout sketch.** A textual block-diagram of the page is enough
   (header / KPI row / chart grid / detail). Don't draw the XML yet.
5. **Open decisions.** Anywhere you had to guess (proxy for a missing
   dimension, scope of demographic data to bring in, whether to modify a
   shared data model). Phrase as questions the user can yes/no.

Only after the user approves should you write spec JSON. This convention
exists because rebuilding a wrong dashboard costs more iterations than
the 60 seconds spent writing the plan, and because the user can correct
data-model assumptions you'd otherwise discover at POST time.

If the user has already given you an explicit plan, skip to building —
don't re-propose.

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

For workbook specs specifically (not data models), eight rules from past
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

Full patterns, source kinds, formula namespaces, KPI/text/container shapes,
GridContainer layout XML, and the page-structure pattern live in
`reference/workbook-spec-api.md`. Always visually verify the workbook in
the UI after a CREATE — the API doesn't validate cross-element column
resolution or visualization quality.

## Reference and examples

- `reference/naming.md` — naming rubric.
- `reference/workbook-spec-api.md` — endpoints, source kinds, column rule,
  formula namespaces, control wiring, KPI shape, kind mismatches,
  visualization clarity. **Read this before authoring any workbook spec.**
- `examples/` — known-good specs to seed generation. Treat as immutable
  references; clone-and-modify rather than editing in place.

For data-model field-level mechanics (columns, metrics, relationships,
filters, controls, formatting, folders, column-level security, workflows)
defer to the upstream `sigma-data-models` skill — its `reference/` folder is
the authoritative answer for those topics.
