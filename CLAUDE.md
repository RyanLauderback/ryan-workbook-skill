# Project Context — Sigma Computing Agentic Workspace

This workspace builds Sigma Computing dashboards/workbooks via Claude Code using Sigma's official agent skills plus project-local workbook-pattern skills.

## Session kickoff

The skill opens on the user's first build-related message (explicit trigger:
`start build mode`) by resolving auth automatically — `eval
"$(skills/sigma-workbook-conventions/scripts/api/browser-login.sh)"`, or skipping straight past that if a
token or client-credentials vars are already exported (a returning
browser-login session, or Claude Code web's injected vars) — then
`skills/sigma-workbook-conventions/scripts/api/whoami.sh` actively validates auth against the live API before
recon starts. A 2-question `AskUserQuestion` gate (data source, what/where
to build) follows, capturing the raw inputs the planner needs. Then Recon
→ Plan → User approval → POST → GET → Visual verify. **Plan approval is the
only authorization for state-changing API calls.**

**Recon is bounded to what the user named** — searching the broader
workspace for a reference implementation (e.g., hunting for an existing
workbook to reverse-engineer an unsupported chart kind) needs its own
explicit check-in first, even though it's read-only. That check-in only
counts if the agent actually stops and waits — silence is not approval.
See `skills/sigma-workbook-conventions/SKILL.md` → "Workflow:
propose a plan before building" and `reference/conventions.md` → "Recon
scope boundary + hard stop on permission questions."

If the user wants to add project-specific enrichments (Tableau migration
notes, account-specific patterns, etc.) directly to the skill, the
convention is a **`local-` filename prefix** on added files (e.g.
`reference/local-tableau-migration.md`) so opt-in additions stay visually
separable from canonical content. See SKILL.md → "Optional: session-local
enrichment via `local-` prefix."

Full 3-question text and workflow details live in
`skills/sigma-workbook-conventions/SKILL.md` → "Session kickoff."

## Skills loaded here

**Upstream (via plugin marketplace, see `.claude/settings.json`):**
- `sigma-api` — OAuth → bearer token; provides `get-token.sh`. Use whenever the user wants to call the Sigma REST API.
- `sigma-data-models` — Round-trips data model specs (sources, columns, metrics, relationships, filters, controls, folder groupings, column-level security).

**Project-local (canonical source at `skills/sigma-workbook-conventions/`,
discovered in this checkout via a thin `.claude/skills/sigma-workbook-conventions/SKILL.md` stub — see "Layout" below):**
- `sigma-workbook-conventions` — input resolution, naming, layout, control catalog, and POST-time gotchas when generating workbook specs. Carries **load-bearing rules** (passthrough mandatory, `[Metrics/<Name>]` resolution + DM-switch hard rule, formulas trace to recon, controlId/column collision) plus a chunked `reference/` split under `specification/` (per-element files: `schema`, `charts`, `kpis`, `tables`, `controls`, `layout`, `formulas`, `formatting`, `sources`, `sources-warehouse`, `text`, `containers`, `others`, `maps`) and `workflows/` (`plan`, `crud`, `validate`, `discover`, `from-image`), plus top-level rules (`conventions`, `naming`, `scope-and-edge-cases`, `history`). Pair with `skills/sigma-workbook-conventions/scripts/sigma-resolve.py` (resolver) and `skills/sigma-workbook-conventions/scripts/validate-spec.py` (pre-POST validator — 17 checks; full catalog in `reference/workflows/validate.md`).

**Required reading before authoring (HARD GATE).** Before drafting a plan or writing any spec JSON in build mode, `Read` the chunk files mapped to the task type in `skills/sigma-workbook-conventions/SKILL.md` → "Required reading before authoring." Plans must include a `Chunks Read:` line listing the files consulted. Plans without that line are not approvable. This gate was added 2026-05-19 after a cold-start test session authored two workbooks without ever opening the chunk files — see `skills/sigma-workbook-conventions/reference/history.md` → "2026-05-19 — Cold-start test session."

Domain-specific workbook-pattern skills (revenue, ops, fin-recon, etc.) get added under `.claude/skills/` as separate folders once we have 2–3 working exemplars to anchor a pattern on. See `docs/skill-authoring.md`.

A read-only mirror of the upstream skills lives at `vendor/sigma-agent-skills/` for inspection while authoring new project skills. Refresh with `scripts/refresh-vendor.sh`.

## Sigma documentation lookups via native MCP

When you need a Sigma formula function reference (`Sum`, `DateDiff`,
`Rollup`, etc.) or a REST API endpoint shape, use the native
`mcp__claude_ai_Sigma_Docs__*` tools instead of `WebFetch`:

- `mcp__claude_ai_Sigma_Docs__search` — keyword search across help docs
- `mcp__claude_ai_Sigma_Docs__fetch` — fetch a docs page by id
- `mcp__claude_ai_Sigma_Docs__list-endpoints` / `get-endpoint` /
  `search-endpoints` — Sigma REST API reference

No auth, no bash, no permission prompts when allowlisted. Schemas load
via `ToolSearch` on first use. Already allowlisted in `.claude/settings.json`.

**Sigma_Docs MCP is a Claude.ai account-level connector, not a Claude Code
plugin.** If the customer running this repo hasn't enabled it in their
Claude.ai account, the `mcp__claude_ai_Sigma_Docs__*` tools won't appear.
Fallback: use `WebFetch` against `https://help.sigmacomputing.com/` (function
references) and `https://help.sigmacomputing.com/reference/` (REST API
endpoints). The skill works without the MCP — most function syntax is
already in `skills/sigma-workbook-conventions/reference/specification/formulas.md`;
the MCP is a faster lookup for unfamiliar functions.

Workspace discovery (finding workbooks/data models), data-model
inspection, and workbook authoring/publishing all use the bash helpers
in `skills/sigma-workbook-conventions/scripts/api/`. See `skills/sigma-workbook-conventions/SKILL.md`
for the workflow.

## Authentication

Browser sign-in is the only auth step a CLI user takes:

1. `eval "$(skills/sigma-workbook-conventions/scripts/api/browser-login.sh)"` — discovery-driven OAuth 2.1
   authorization-code + PKCE flow. Opens the system browser, captures the
   redirect automatically (falls back to a manual paste-back if `python3`
   isn't available), and stores a refresh token in the OS keychain
   (`security` on macOS, `secret-tool`/libsecret on Linux) so future
   sessions don't need a second browser round-trip.
2. `skills/sigma-workbook-conventions/scripts/api/whoami.sh` — confirms the token against the live API.
3. Repeat sessions: `export SIGMA_TOKEN_FETCHER=$PWD/skills/sigma-workbook-conventions/scripts/api/refresh-token.sh`
   before calling any `skills/sigma-workbook-conventions/scripts/api/*.sh` — `_env.sh`'s cache-miss path then
   redeems the stored refresh token instead of prompting a new browser login.

This is also the path that unblocks Sigma's `/mcp/v2` endpoint — see
`reference/workflows/discover.md` → "MCP status": `/mcp/v2` categorically
rejects `client_credentials` tokens (confirmed by Sigma's MCP engineering
team), but accepts a browser-login token.

**Claude Code web authenticates automatically — no user action.** The
platform injects `SIGMA_CLIENT_ID`/`SIGMA_CLIENT_SECRET`/`SIGMA_BASE_URL`
directly as already-exported env vars before the session starts. There's no
file to create and no interactive browser to redirect to in that execution
context, so `_env.sh` detects the exported vars and falls through silently to
the repo-local `skills/sigma-workbook-conventions/scripts/api/get-token.sh` `client_credentials` exchange.

**In all cases: never echo `$SIGMA_API_TOKEN`, `$SIGMA_CLIENT_SECRET`, or any
other secret.** Don't write secrets to files inside the workspace. Pass
tokens only via `Authorization` headers.

## Layout

- `workbooks/<name>/` — one folder per dashboard. Each contains `spec.json`, `prompts/<timestamp>.md`, `iterations/<timestamp>.json`, `notes.md`. Start a new dashboard by copying `workbooks/_template/`.
- `workbooks/_exemplars/` — golden specs harvested from Sigma. Read-only references; never edit.
- `.claude-plugin/`, `.cortex-plugin/` — marketplace/plugin manifests (`marketplace.json`, `plugin.json`) that make `skills/sigma-workbook-conventions/` self-contained and installable via `/plugin install` or Cortex Code's plugin mechanism, independent of this checkout.
- `skills/sigma-workbook-conventions/` — the canonical, marketplace-publishable skill (`SKILL.md`, `reference/`, `examples/`), bundling its own `scripts/` (below) so it's self-contained wherever installed.
- `.claude/skills/sigma-workbook-conventions/SKILL.md` — thin stub (frontmatter-only trigger) so this checkout's own `.claude/skills/` auto-discovery still fires "start build mode"; points at the canonical copy above.
- `.cortex/skills/sigma-workbook-conventions/` — real-file mirror (`SKILL.md`, `reference/`, `examples/`) for Cortex Code discovery, regenerated via `skills/sigma-workbook-conventions/scripts/sync-cortex-mirror.py` (not a symlink — Windows-checkout safe).
- `skills/sigma-workbook-conventions/scripts/api/` — auth-bootstrapped wrappers around Sigma's MCP server (`mcp-search.sh`, `mcp-describe.sh` — the default discovery path under this skill's `browser-login.sh` auth; see `reference/workflows/discover.md` → "MCP status") and REST endpoints (`search-files.sh`, `find-file-by-urlid.sh`, `list-folders.sh`, etc. — the documented fallback). Each sources `_env.sh` on first call, which uses an already-exported token or client-credentials vars to mint/cache one — no file is ever read. Workbook CRUD (POST/PUT to `/v2/workbooks/*`) still goes through direct `curl` — no helper script yet.
- `scripts/refresh-vendor.sh` clones the upstream skill repo into `vendor/` for inspection only. Stays at the repo root — a maintainer tool, not skill-bundled content.
- `prompts/library/` — reusable prompt fragments (guardrails, framing, etc.).
- `docs/` — `conventions.md`, `iteration-playbook.md`, `skill-authoring.md`.
- `evals/` — regression test cases for the skill (real session prompts + expected behavior); see `evals/README.md`.

## Iteration loop (summary; full playbook in `docs/iteration-playbook.md`)

1. Save the prompt verbatim to `workbooks/<name>/prompts/<timestamp>.md`.
2. Save the generated/edited spec to `workbooks/<name>/iterations/<timestamp>.json`.
3. Diff against the closest exemplar; record findings in `notes.md`.
4. When a fix recurs across 2+ iterations, promote it into the relevant skill's `reference/` or `examples/`.
5. Commit each iteration so `git log` becomes the iteration log.

## Authoring new workbook-pattern skills

See `docs/skill-authoring.md`. Pattern mirrors Sigma's own: `SKILL.md` with sharp frontmatter description, `reference/` split by functional domain, `examples/` with at least one known-good spec.
