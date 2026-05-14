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
- `sigma-workbook-conventions` — input resolution, naming, layout, control catalog, and POST-time gotchas when generating workbook specs. Pair with `scripts/sigma-resolve.py` (resolver) and `scripts/validate-spec.py` (pre-POST validator).

Domain-specific workbook-pattern skills (revenue, ops, fin-recon, etc.) get added under `.claude/skills/` as separate folders once we have 2–3 working exemplars to anchor a pattern on. See `docs/skill-authoring.md`.

A read-only mirror of the upstream skills lives at `vendor/sigma-agent-skills/` for inspection while authoring new project skills. Refresh with `scripts/refresh-vendor.sh`.

## Authentication

1. `cp .env.example .env` and fill in `SIGMA_BASE_URL`, `SIGMA_CLIENT_ID`, `SIGMA_CLIENT_SECRET`.
2. Done — scripts in `scripts/api/*.sh` self-bootstrap on first call (load
   `.env`, fetch token via the `sigma-api` skill, cache at `/tmp/.sigma_token`
   with a 55-min TTL). No env-prelude or token chaining needed from the caller.
3. If your `get-token.sh` lives somewhere other than `~/.claude/plugins/marketplaces/sigma-computing/...`, set `SIGMA_TOKEN_FETCHER` to its path.
4. **Never echo `$SIGMA_API_TOKEN`, `$SIGMA_CLIENT_SECRET`, or any other secret.** Don't write secrets to files inside the workspace. Pass tokens only via `Authorization` headers.

## Bash invocation hygiene

Claude Code's permission patterns (e.g. `Bash(scripts/api/*)`) match the
**start** of the command string. A `cd "<repo>" && script` prefix breaks the
match against the bare pattern and falls back to a defensive `Bash(cd * &&
scripts/api/*)` pattern instead.

Working-directory reality: if the repo is the project CWD, invoke bare from
the start (`scripts/api/foo.sh ...`). If the repo is nested under the CC
working directory (as in this checkout — `Run 5.13.2026 10.45AM/ryan-
workbook-skill`), one `cd ryan-workbook-skill` per session is unavoidable;
after that, CWD persists and subsequent calls should be bare. The
anti-pattern is **re-prepending `cd <repo> &&` on every command** — that
defeats both pattern matching and readability. Full rule and rationale in
`sigma-workbook-conventions/SKILL.md` → "Bash invocation hygiene."

## Layout

- `workbooks/<name>/` — one folder per dashboard. Each contains `spec.json`, `prompts/<timestamp>.md`, `iterations/<timestamp>.json`, `notes.md`. Start a new dashboard by copying `workbooks/_template/`.
- `workbooks/_exemplars/` — golden specs harvested from Sigma. Read-only references; never edit.
- `scripts/api/` — auth-bootstrapped wrappers around Sigma's MCP server (`mcp-search.sh`, `mcp-describe.sh`) and REST endpoints (`find-file-by-urlid.sh`, `list-folders.sh`, etc.). Each sources `_env.sh` on first call to load `.env` and cache an OAuth token. Workbook CRUD (POST/PUT to `/v2/workbooks/*`) still goes through direct `curl` — no helper script yet.
- `scripts/load-env.sh` — used internally by `_env.sh`. Direct callers rarely need it. `scripts/refresh-vendor.sh` clones the upstream skill repo into `vendor/` for inspection only.
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
