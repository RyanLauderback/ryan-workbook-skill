# Sigma Computing Workbook Skill

Project-local Claude Code skills + a working sandbox for building Sigma Computing workbooks/dashboards via Claude Code. Pairs Sigma's official `sigma-api` and `sigma-data-models` plugins with a project-local skill that encodes workbook-spec conventions (naming, layout, control catalog, POST-time gotchas), plus helper scripts that resolve user prompts ("the FUN.BIKES schema, Claude Testing folder") into Sigma API identifiers and validate workbook specs before POST.

## Quick start (for colleagues)

```bash
# 1. Clone this repo
git clone https://github.com/RyanLauderback/ryan-workbook-skill.git
cd ryan-workbook-skill

# 2. Set Sigma API credentials
cp .env.example .env
# edit .env — fill in SIGMA_BASE_URL, SIGMA_CLIENT_ID, SIGMA_CLIENT_SECRET

# 3. Open the folder in Claude Code (CLI, desktop app, or IDE extension)
```

On first open, Claude Code reads `.claude/settings.json` and **automatically installs the upstream `sigma-agent-skills` plugin** (which provides `sigma-api` and `sigma-data-models`) from `github.com/sigmacomputing/sigma-agent-skills`. The two project-local skills under `.claude/skills/` load automatically because they live in the standard skill directory.

You don't need to run `/plugin marketplace add` or `/plugin install` manually — those are only required if you want the upstream plugin available globally instead of project-scoped.

## Starting a session

Once Claude Code is open, kick off with one of these phrases:

- **`start build mode`** (default) — produce a workbook. Claude opens with a 3-question gate (.env / data source / what to build + where in Sigma), warms the OAuth token, and runs `whoami` to confirm auth before recon. Then: Recon → Plan → Approval → Build → Verify.
- **`start training mode`** — locally enrich the skill with session-specific context (e.g. Tableau migration notes). Skill-file additions use a `local-` filename prefix to stay visually separable from canonical content.

The plan-first convention stays: Claude proposes a written plan and waits for explicit approval before POSTing the workbook. Before drafting that plan, Claude is required to `Read` the relevant `reference/` chunk files in the workbook-conventions skill (hard gate added 2026-05-19); the plan must list which chunks were consulted under a `Chunks Read:` line.

## Example prompts

Describe the dashboard in your own words — mix URLs and prose freely. Claude routes the prompt through the right discovery tool — Sigma's MCP server (the `/mcp/v2` REST endpoint, reached via `scripts/api/mcp-search.sh` and `scripts/api/mcp-describe.sh` — *not* the Claude.ai Sigma_MCP connector) for name/topic searches, `scripts/api/find-file-by-urlid.sh` for URL slugs, and `scripts/api/mcp-describe.sh` to inspect data-model columns/metrics — then resolves each reference to the API identifiers it needs. Examples:

> Use the `Plugs Example Data Model` and the transaction details table to build a customer performance dashboard showing how customers buy across stores and which products are most popular. Save it in my Claude Testing folder.

> Build a viz catalog off the FUN.BIKES schema (Sigma Sample Database connection) — drop it in the Claude Testing folder.

> Build a workbook off these tables: `https://app.sigmacomputing.com/<org>/t/<id1>`, `<id2>` and place it in folder `https://app.sigmacomputing.com/<org>/My-Folder-<urlId>`.

You shouldn't have to look up internal UUIDs, schema paths, or connection IDs by hand. If the prompt is ambiguous (two folders named "Sandbox", etc.), Claude asks with the candidate names — not raw IDs.

## What's in the box

| Path | What it does |
|---|---|
| `.claude/settings.json` | Auto-installs upstream `sigma-agent-skills` plugin on first open. |
| `.claude/skills/sigma-workbook-conventions/` | Naming, layout, POST-time gotchas, the discovery routing rules (MCP-first for search/inspect, REST fallbacks for the rest), and **load-bearing rules** (passthrough, `[Metrics/<Name>]` resolution, formula recon anchor, controlId collision) plus a 5-file `reference/` split (`function-reference`, `element-shapes`, `layout-and-cross-element`, `scope-and-edge-cases`, `history`). SKILL.md gates the chunk reads via a hard "Required reading before authoring" check — see SKILL.md. The main draw of this repo. |
| `scripts/api/mcp-search.sh` | Query Sigma's MCP server to find workbooks / data models / data-model elements / tables by name or topic. The first call for any name- or topic-based prompt. |
| `scripts/api/mcp-describe.sh` | Query the MCP server's `describe` tool for any `table` / `datamodel` / `datamodel-element` / `workbook` / `workbook-element` — returns SQL DDL with column names, types, descriptions, formulas, and the metrics catalog. Replaces hand-walking `GET /v2/dataModels/{id}/spec`. |
| `scripts/api/find-file-by-urlid.sh` | Resolve any URL slug (`/b/<id>`, `…-<urlId>`) to its file metadata via `/v2/files`. The URL-slug path of the discovery router. |
| `scripts/api/_env.sh` | Sourced internally by every `scripts/api/*.sh`. Loads `.env`, fetches an OAuth token via the `sigma-api` skill, and caches it at `/tmp/.sigma_token` (mode 0600, 55-min TTL). Self-bootstrap — callers do not set env vars. |
| `scripts/api/` (rest) | Thin REST wrappers used as MCP fallbacks: `list-connections.sh`, `list-folders.sh`, `lookup-path.sh`, `list-table-columns.sh`, `probe-schema-tables.sh`. Reach for these when MCP doesn't cover the case (raw connection enumeration, folder browsing by name pattern, warehouse-schema probing). |
| `scripts/sigma-resolve.py` | Handles the messy-input case — prose mixed with URL slugs and warehouse paths (`<DB>.<SCHEMA>.<table>`). Returns structured `{sources, folder, candidates, unresolved}` JSON. Use when the simpler MCP/URL-slug paths don't fit. |
| `scripts/validate-spec.py` | Pre-POST static checks (7 total): per-page `layout`, unplaced elements, empty containers, malformed `format` shape (missing `kind`), duplicate `controlId`, passthrough collapse on charts/pivots, and controlId/column collision on filtered elements. Auto-runs via `publish-workbook.sh post`. |
| `scripts/load-env.sh` | `eval "$(scripts/load-env.sh)"` to load `.env` into the shell. Used internally by `_env.sh`; callers rarely invoke it directly. |
| `scripts/refresh-vendor.sh` | Optional: clone a read-only mirror of upstream skills into `vendor/` for inspection while authoring new project skills. |
| `workbooks/_template/` | Starter folder — `cp -R` to seed a new dashboard. |
| `workbooks/_exemplars/` | Golden specs harvested from Sigma. Read-only references. |
| `prompts/library/` | Reusable prompt fragments (currently empty; grow as patterns recur). |
| `docs/` | `conventions.md`, `iteration-playbook.md`, `skill-authoring.md`. |
| `CLAUDE.md` | Project context auto-loaded by Claude Code on every session. |

Per-user workbook iterations (`workbooks/<name>/`) are gitignored; only `workbooks/_template/` and `workbooks/_exemplars/` are repo-tracked. See `.gitignore`.

## The build loop, end to end

1. **Authenticate.** Just `cp .env.example .env` and fill in credentials. `scripts/api/*.sh` scripts self-bootstrap on first call (load `.env`, fetch token via `sigma-api` skill, cache at `/tmp/.sigma_token`). No env-prelude needed from the caller.
2. **Discover & inspect.** Claude routes by prompt shape: name/topic → `scripts/api/mcp-search.sh`; URL slug → `scripts/api/find-file-by-urlid.sh`; messy prose → `scripts/sigma-resolve.py`. Then `scripts/api/mcp-describe.sh datamodel-element <dm> <el>` pulls the column types, descriptions, and metrics catalog for the data inventory. Ambiguity surfaces as named candidates to disambiguate, not endpoint errors.
3. **Plan.** Claude drafts the data inventory, chart inference, controls, and layout sketch (per the plan-first workflow in the conventions skill) and waits for explicit approval.
4. **Author.** `workbooks/<name>/spec.json` with two-tier sourcing (raw → derived → viz), `name`-on-every-cross-referenced-column, the documented control shapes, and one **top-level** `layout` XML with all `<Page>` siblings nested under it.
5. **Publish.** `scripts/api/publish-workbook.sh post workbooks/<name>/spec.json` — the wrapper auto-runs `validate-spec.py` first (7 checks: per-page layout, unplaced elements, empty containers, malformed `format` shape, duplicate `controlId`, passthrough collapse, controlId/column collision), then POSTs to `/v2/workbooks/spec` with `Authorization` + `Accept: application/json` injected and a 401 auto-retry. Prints `{ workbookId, url, path }` on success.
6. **GET back.** `scripts/api/publish-workbook.sh get-spec <workbookId> | jq . > workbooks/<name>/spec.json` — the GET-back spec is the new source of truth (Sigma normalizes IDs and layout XML).
7. **Verify.** Open in the UI — the API doesn't validate cross-element column resolution or visualization quality.

## Adding a new dashboard

```bash
cp -R workbooks/_template workbooks/my-new-dashboard
```

Then describe what you want; Claude uses the loaded skills to resolve sources, author a `spec.json`, validate it, and POST it to your Sigma org. See [`docs/iteration-playbook.md`](docs/iteration-playbook.md) for the full iteration loop.

## Authoring a new workbook-pattern skill

See [`docs/skill-authoring.md`](docs/skill-authoring.md). Look at `.claude/skills/sigma-workbook-conventions/` as a working example of skill shape. The pattern: a `SKILL.md` with a sharp frontmatter description, `reference/` split by functional domain, and `examples/` with at least one known-good spec.
