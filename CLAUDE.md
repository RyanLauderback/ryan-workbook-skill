# Project Context — Sigma Computing Agentic Workspace

This workspace builds Sigma Computing dashboards/workbooks via Claude Code using Sigma's official agent skills plus project-local workbook-pattern skills.

## Session modes

The user initializes each session in one of two modes:

- **"initialize training mode session"** — default. Full agentic loop:
  propose plans for approval, ask clarifying questions, surface
  inference choices, and after the build promote recurring findings
  into skills / docs / memory. Co-developing the skill is part of the
  work.
- **"initialize test mode session"** — build-only, for recording demo
  videos. Focus purely on producing the workbook with the skills as
  they currently exist. Do NOT propose skill modifications, do NOT
  offer to promote findings, do NOT editorialize about iteration
  process. Solve blockers quietly within the build. Skill is treated
  as fixed reference material.

If neither phrase is used at init, default to training mode.

## Skills loaded here

**Upstream (via plugin marketplace, see `.claude/settings.json`):**
- `sigma-api` — OAuth → bearer token; provides `get-token.sh`. Use whenever the user wants to call the Sigma REST API.
- `sigma-data-models` — Round-trips data model specs (sources, columns, metrics, relationships, filters, controls, folder groupings, column-level security).

**Project-local (`.claude/skills/`):**
- `sigma-workbook-conventions` — naming, layout, common pitfalls when generating workbook specs.
- `sigma-fin-recon` — financial reconciliation workbook pattern (structure, KPIs, exemplar spec).

A read-only mirror of the upstream skills lives at `vendor/sigma-agent-skills/` for inspection while authoring new project skills. Refresh with `scripts/refresh-vendor.sh`.

## Authentication

1. `cp .env.example .env` and fill in `SIGMA_BASE_URL`, `SIGMA_CLIENT_ID`, `SIGMA_CLIENT_SECRET`.
2. Load env vars: `eval "$(scripts/load-env.sh)"`
3. Get a token via the `sigma-api` skill (which invokes its bundled `get-token.sh`).
4. **Never echo `$SIGMA_API_TOKEN`, `$SIGMA_CLIENT_SECRET`, or any other secret.** Don't write secrets to files inside the workspace. Pass tokens only via `Authorization` headers.

## Layout

- `workbooks/<name>/` — one folder per dashboard. Each contains `spec.json`, `prompts/<timestamp>.md`, `iterations/<timestamp>.json`, `notes.md`. Start a new dashboard by copying `workbooks/_template/`.
- `workbooks/_exemplars/` — golden specs harvested from Sigma. Read-only references; never edit.
- `scripts/load-env.sh` — eval'd to load `.env` into the shell. `scripts/refresh-vendor.sh` clones the upstream skill repo into `vendor/` for inspection only. Workbook CRUD goes through the Sigma REST API directly via `curl` — there are no helper scripts for export/push.
- `prompts/library/` — reusable prompt fragments (guardrails, framing, etc.).
- `docs/` — `conventions.md`, `iteration-playbook.md`, `skill-authoring.md`.

## Iteration loop (summary; full playbook in `docs/iteration-playbook.md`)

1. Save the prompt verbatim to `workbooks/<name>/prompts/<timestamp>.md`.
2. Save the generated/edited spec to `workbooks/<name>/iterations/<timestamp>.json`.
3. Diff against the closest exemplar; record findings in `notes.md`.
4. When a fix recurs across 2+ iterations, promote it into the relevant skill's `reference/` or `examples/`.
5. Commit each iteration so `git log` becomes the iteration log.

## Authoring new workbook-pattern skills

See `docs/skill-authoring.md`. Pattern mirrors Sigma's own: `SKILL.md` with sharp frontmatter description, `reference/` split by functional domain, `examples/` with at least one known-good spec.
