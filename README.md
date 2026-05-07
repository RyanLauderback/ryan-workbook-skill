# Sigma Computing Agentic Workspace

Workspace for developing Sigma Computing workbooks/dashboards via Claude Code, using Sigma's official agent skills plus project-local workbook-pattern skills.

## Quick start

```bash
# 1. Set credentials
cp .env.example .env
# edit .env with SIGMA_BASE_URL, SIGMA_CLIENT_ID, SIGMA_CLIENT_SECRET

# 2. Pull a local read-only mirror of upstream skills (for inspection)
bash scripts/refresh-vendor.sh

# 3. Open this folder in Claude Code. The plugin marketplace entry in
#    .claude/settings.json auto-installs sigma-api + sigma-data-models on first run.
```

In Claude Code, ask things like:
- "Get me a Sigma API token" → activates the `sigma-api` skill.
- "Export the data model `<id>` to workbooks/_exemplars/" → uses `sigma-data-models` + `scripts/export-workbook.sh`.
- "Scaffold a financial reconciliation dashboard" → activates the local `sigma-fin-recon` skill.

## Layout

```
.claude/skills/        Project-local workbook-pattern skills (sigma-fin-recon, sigma-workbook-conventions, …)
vendor/                Read-only mirror of github.com/sigmacomputing/sigma-agent-skills
workbooks/             One folder per dashboard, plus _exemplars/ and _template/
scripts/               load-env.sh, refresh-vendor.sh, export-workbook.sh, push-workbook.sh
prompts/library/       Reusable prompt fragments
docs/                  conventions.md, iteration-playbook.md, skill-authoring.md
CLAUDE.md              Project context auto-loaded by Claude Code
```

## Adding a new dashboard

```bash
cp -R workbooks/_template workbooks/my-new-dashboard
```

Then describe what you want; Claude will use the loaded skills to generate a `spec.json`. See `docs/iteration-playbook.md` for how to iterate productively.

## Adding a new workbook-pattern skill

See `docs/skill-authoring.md`. Copy `.claude/skills/sigma-fin-recon/` as a starting point.
