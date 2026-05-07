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

## Reference

See `reference/naming.md` for the full naming rubric. For field-level mechanics
(columns, metrics, relationships, filters, controls, formatting, folders,
column-level security, workflows) defer to the upstream `sigma-data-models`
skill — its `reference/` folder is the authoritative answer for those topics.
