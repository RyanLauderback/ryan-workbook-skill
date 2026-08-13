# Sigma Computing Workbook Skill

Project-local Claude Code skills + a working sandbox for building Sigma Computing workbooks/dashboards via Claude Code. Pairs Sigma's official `sigma-api` and `sigma-data-models` plugins with a project-local skill that encodes workbook-spec conventions (naming, layout, control catalog, POST-time gotchas), plus helper scripts that resolve user prompts ("the FUN.BIKES schema, Claude Testing folder") into Sigma API identifiers and validate workbook specs before POST.

## Quick start (for colleagues)

```bash
# 1. Clone this repo
git clone https://github.com/RyanLauderback/ryan-workbook-skill.git
cd ryan-workbook-skill

# 2. Authenticate — sign in via browser, no admin-provisioned credential needed
export SIGMA_BASE_URL=https://aws-api.sigmacomputing.com  # pick your region — see help.sigmacomputing.com/docs/region-warehouse-and-feature-support
eval "$(skills/sigma-workbook-conventions/scripts/api/browser-login.sh)"

# 3. Open the folder in Claude Code (CLI, desktop app, or IDE extension)
```

On first open, Claude Code reads `.claude/settings.json` and **automatically installs the upstream `sigma-agent-skills` plugin** (which provides `sigma-api` and `sigma-data-models`) from `github.com/sigmacomputing/sigma-agent-skills`. The canonical `sigma-workbook-conventions` skill lives at `skills/sigma-workbook-conventions/` (marketplace-installable — see `.claude-plugin/`); a thin stub at `.claude/skills/sigma-workbook-conventions/SKILL.md` loads automatically in this checkout because it lives in the standard skill directory, and points at the canonical copy.

You don't need to run `/plugin marketplace add` or `/plugin install` manually — those are only required if you want the upstream plugin available globally instead of project-scoped.

## Starting a session

Once Claude Code is open, describe what you want to build. Explicit trigger: **`start build mode`** — Claude resolves auth automatically (browser sign-in, or reusing already-exported credentials), warms the OAuth token, and runs `whoami` to confirm auth before recon, then opens a 2-question gate (data source / what to build + where in Sigma). Then: Recon → Plan → Approval → Build → Verify.

Opt-in session-local enrichment (Tableau migration notes, account-specific patterns) uses a **`local-`** filename prefix on skill files to stay visually separable from canonical content — see the skill's SKILL.md for the convention.

The plan-first convention stays: Claude proposes a written plan and waits for explicit approval before POSTing the workbook. Before drafting that plan, Claude is required to `Read` the relevant `reference/` chunk files in the workbook-conventions skill (hard gate added 2026-05-19); the plan must list which chunks were consulted under a `Chunks Read:` line.

## Example prompts

Describe the dashboard in your own words — mix URLs and prose freely. Claude routes the prompt through the right discovery tool — Sigma's MCP server (the `/mcp/v2` REST endpoint, reached via `skills/sigma-workbook-conventions/scripts/api/mcp-search.sh` and `skills/sigma-workbook-conventions/scripts/api/mcp-describe.sh` — *not* the Claude.ai Sigma_MCP connector) for name/topic searches, `skills/sigma-workbook-conventions/scripts/api/find-file-by-urlid.sh` for URL slugs, and `skills/sigma-workbook-conventions/scripts/api/mcp-describe.sh` to inspect data-model columns/metrics — then resolves each reference to the API identifiers it needs. Examples:

> Use the `Plugs Example Data Model` and the transaction details table to build a customer performance dashboard showing how customers buy across stores and which products are most popular. Save it in my Claude Testing folder.

> Build a viz catalog off the FUN.BIKES schema (Sigma Sample Database connection) — drop it in the Claude Testing folder.

> Build a workbook off these tables: `https://app.sigmacomputing.com/<org>/t/<id1>`, `<id2>` and place it in folder `https://app.sigmacomputing.com/<org>/My-Folder-<urlId>`.

You shouldn't have to look up internal UUIDs, schema paths, or connection IDs by hand. If the prompt is ambiguous (two folders named "Sandbox", etc.), Claude asks with the candidate names — not raw IDs.

## What's in the box

| Path | What it does |
|---|---|
| `.claude/settings.json` | Auto-installs upstream `sigma-agent-skills` plugin on first open. |
| `.claude-plugin/`, `.cortex-plugin/` | Marketplace/plugin manifests (`marketplace.json`, `plugin.json`) that make `skills/sigma-workbook-conventions/` installable via `/plugin install` (Claude Code) or Cortex Code's plugin mechanism, independent of this checkout. |
| `skills/sigma-workbook-conventions/` | The canonical, marketplace-publishable skill. Naming, layout, POST-time gotchas, the discovery routing rules (MCP-first for search/inspect, REST fallbacks for the rest), and **load-bearing rules** (passthrough, `[Metrics/<Name>]` resolution, formula recon anchor, controlId collision) plus a chunked `reference/` split: per-element specs under `specification/` (`schema`, `charts`, `kpis`, `tables`, `controls`, `layout`, `formulas`, `formatting`, `sources`, `text`, `containers`, `others`, `maps`, etc.); operational workflows under `workflows/` (`plan`, `crud`, `validate`, `discover`, `from-image`); and top-level cross-cutting docs (`conventions`, `naming`, `scope-and-edge-cases`, `history`). SKILL.md gates the chunk reads via a hard "Required reading before authoring" check — see SKILL.md. The main draw of this repo. Bundles its own `scripts/` (below) so it's self-contained wherever it's installed. |
| `.claude/skills/sigma-workbook-conventions/SKILL.md` | Thin stub (frontmatter-only trigger) so this checkout's own `.claude/skills/` auto-discovery still fires "start build mode"; points at the canonical copy above. |
| `.cortex/skills/sigma-workbook-conventions/` | Real-file mirror (`SKILL.md`, `reference/`, `examples/`) for Cortex Code's discovery — regenerated via `sync-cortex-mirror.py`, not a symlink (Windows-checkout safe). |
| `skills/sigma-workbook-conventions/scripts/api/mcp-search.sh` | Query Sigma's MCP server to find workbooks / data models / data-model elements / tables by name or topic. The first call for any name- or topic-based prompt. |
| `skills/sigma-workbook-conventions/scripts/api/mcp-describe.sh` | Query the MCP server's `describe` tool for any `table` / `datamodel` / `datamodel-element` / `workbook` / `workbook-element` — returns SQL DDL with column names, types, descriptions, formulas, and the metrics catalog. Replaces hand-walking `GET /v2/dataModels/{id}/spec`. |
| `skills/sigma-workbook-conventions/scripts/api/find-file-by-urlid.sh` | Resolve any URL slug (`/b/<id>`, `…-<urlId>`) to its file metadata via `/v2/files`. The URL-slug path of the discovery router. |
| `skills/sigma-workbook-conventions/scripts/api/browser-login.sh` | Interactive OAuth 2.1 authorization-code + PKCE sign-in — no admin-provisioned client ID/secret needed, and the only auth path Sigma's `/mcp/v2` accepts (see `reference/workflows/discover.md` → "MCP status"). Opens the system browser, captures the redirect automatically, stores a refresh token in the OS keychain. `eval "$(skills/sigma-workbook-conventions/scripts/api/browser-login.sh)"`. |
| `skills/sigma-workbook-conventions/scripts/api/refresh-token.sh` | Headless follow-up to `browser-login.sh` — redeems the keychain-stored refresh token for a new access token with no browser round-trip. Point `_env.sh` at it via `SIGMA_TOKEN_FETCHER` for repeat sessions. |
| `skills/sigma-workbook-conventions/scripts/api/_env.sh` | Sourced internally by every `skills/sigma-workbook-conventions/scripts/api/*.sh`. Uses an already-exported `SIGMA_API_TOKEN` if present (from `browser-login.sh`/`refresh-token.sh`); otherwise, if `SIGMA_CLIENT_ID`/`SIGMA_CLIENT_SECRET`/`SIGMA_BASE_URL` are already exported (Claude Code web injects these automatically), mints an OAuth token via the repo-local `get-token.sh` and caches it at a per-user path under `$SIGMA_TOKEN_CACHE` (mode 0600, 55-min TTL). No file is ever read from disk. Self-bootstrap — callers do not set env vars by hand. |
| `skills/sigma-workbook-conventions/scripts/api/get-token.sh` | Repo-local OAuth `client_credentials` exchange against `/v2/auth/token` — used when `SIGMA_CLIENT_ID`/`SIGMA_CLIENT_SECRET`/`SIGMA_BASE_URL` are already exported (Claude Code web injects these automatically; no `.env` file, no user setup). Prints `export SIGMA_API_TOKEN=...` on stdout for `_env.sh` to eval. Skill owns auth so a downloaded-zip / web-session install doesn't depend on the upstream `sigma-api` plugin being present. Override with `SIGMA_TOKEN_FETCHER` to use a different fetcher (e.g. `refresh-token.sh`). |
| `skills/sigma-workbook-conventions/scripts/api/` (rest) | Thin REST wrappers used as MCP fallbacks: `list-connections.sh`, `list-folders.sh`, `lookup-path.sh`, `list-table-columns.sh`, `probe-schema-tables.sh`. Reach for these when MCP doesn't cover the case (raw connection enumeration, folder browsing by name pattern, warehouse-schema probing). |
| `skills/sigma-workbook-conventions/scripts/sigma-resolve.py` | Handles the messy-input case — prose mixed with URL slugs and warehouse paths (`<DB>.<SCHEMA>.<table>`). Returns structured `{sources, folder, candidates, unresolved}` JSON. Use when the simpler MCP/URL-slug paths don't fit. |
| `skills/sigma-workbook-conventions/scripts/validate-spec.py` | Pre-POST static checks (16 total, full catalog in `reference/workflows/validate.md`): includes passthrough collapse, controlId/column collision, bare-reference resolution, control-filter columnId existence, KPI value formula referencing sibling aggregation, `summary` × `calculations` collision, `description` object-on-KPI-and-table, pivot missing rows and columns, schemaVersion, and 6 more. Auto-runs via `publish-workbook.sh post`. |
| `skills/sigma-workbook-conventions/scripts/doctor.sh` | Diagnoses whether the current host can run the skill's scripts (required binaries, interpreter resolution, OS, auth-config sanity). Run first on an unfamiliar host. |
| `scripts/refresh-vendor.sh` | Maintainer-only, stays at repo root (not skill-bundled): clone a read-only mirror of upstream skills into `vendor/` for inspection while authoring new project skills. |
| `workbooks/_template/` | Starter folder — `cp -R` to seed a new dashboard. |
| `workbooks/_exemplars/` | Golden specs harvested from Sigma. Read-only references. |
| `prompts/library/` | Reusable prompt fragments (currently empty; grow as patterns recur). |
| `docs/` | `conventions.md`, `iteration-playbook.md`, `skill-authoring.md`. |
| `CLAUDE.md` | Project context auto-loaded by Claude Code on every session. |

Per-user workbook iterations (`workbooks/<name>/`) are gitignored; only `workbooks/_template/` and `workbooks/_exemplars/` are repo-tracked. See `.gitignore`.

## The build loop, end to end

1. **Authenticate.** Interactive CLI: `eval "$(skills/sigma-workbook-conventions/scripts/api/browser-login.sh)"` — no admin-provisioned credential needed, and the path that unblocks `/mcp/v2`. Claude Code web: nothing to do — the platform injects `SIGMA_CLIENT_ID`/`SIGMA_CLIENT_SECRET`/`SIGMA_BASE_URL` as env vars automatically. `skills/sigma-workbook-conventions/scripts/api/*.sh` scripts self-bootstrap on first call (use an already-exported `SIGMA_API_TOKEN`, or, if the client-credentials vars are already exported, mint one via the repo-local `get-token.sh`, caching at a per-user `$SIGMA_TOKEN_CACHE` path). No env-prelude needed from the caller and the same code path runs in CLI and web.
2. **Discover & inspect.** Claude routes by prompt shape: name/topic → `skills/sigma-workbook-conventions/scripts/api/mcp-search.sh`; URL slug → `skills/sigma-workbook-conventions/scripts/api/find-file-by-urlid.sh`; messy prose → `skills/sigma-workbook-conventions/scripts/sigma-resolve.py`. Then `skills/sigma-workbook-conventions/scripts/api/mcp-describe.sh datamodel-element <dm> <el>` pulls the column types, descriptions, and metrics catalog for the data inventory. Ambiguity surfaces as named candidates to disambiguate, not endpoint errors.
3. **Plan.** Claude drafts the data inventory, chart inference, controls, and layout sketch (per the plan-first workflow in the conventions skill) and waits for explicit approval.
4. **Author.** `workbooks/<name>/spec.json` with two-tier sourcing (raw → derived → viz), `name`-on-every-cross-referenced-column, the documented control shapes, and one **top-level** `layout` XML with all `<Page>` siblings nested under it.
5. **Publish.** `skills/sigma-workbook-conventions/scripts/api/publish-workbook.sh post workbooks/<name>/spec.json` — the wrapper auto-runs `validate-spec.py` first (17 checks), then POSTs to `/v2/workbooks/spec`. Prints `{ workbookId, url, path }` on success. Full check list in `reference/workflows/validate.md`.
6. **GET back.** `skills/sigma-workbook-conventions/scripts/api/publish-workbook.sh get-spec <workbookId> | jq . > workbooks/<name>/spec.json` — captures any server-added fields and layout XML normalization. IDs you authored are preserved verbatim.
7. **Verify.** Open in the UI — the API doesn't validate cross-element column resolution or visualization quality.

## Adding a new dashboard

```bash
cp -R workbooks/_template workbooks/my-new-dashboard
```

Then describe what you want; Claude uses the loaded skills to resolve sources, author a `spec.json`, validate it, and POST it to your Sigma org. See [`docs/iteration-playbook.md`](docs/iteration-playbook.md) for the full iteration loop.

## Authoring a new workbook-pattern skill

See [`docs/skill-authoring.md`](docs/skill-authoring.md). Look at `skills/sigma-workbook-conventions/` as a working example of skill shape. The pattern: a `SKILL.md` with a sharp frontmatter description, `reference/` split by functional domain, and `examples/` with at least one known-good spec.
