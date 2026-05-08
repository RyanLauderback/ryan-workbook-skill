# Sigma Computing Workbook Skill

Project-local Claude Code skills + a working sandbox for building Sigma Computing workbooks/dashboards via Claude Code. Pairs Sigma's official `sigma-api` and `sigma-data-models` plugins with two project-local skills that encode workbook-spec conventions and a financial-reconciliation dashboard pattern.

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

That's it. On first open, Claude Code reads `.claude/settings.json` and **automatically installs the upstream `sigma-agent-skills` plugin** (which provides `sigma-api` and `sigma-data-models`) from `github.com/sigmacomputing/sigma-agent-skills`. The two project-local skills under `.claude/skills/` load automatically because they live in the standard skill directory.

You don't need to run `/plugin marketplace add` or `/plugin install` manually — those are only required if you want the upstream plugin available globally instead of project-scoped.

## Starting a session

Once Claude Code is open, kick off a session with one of these phrases:

- **`initialize training mode session`** — full agentic loop. Claude proposes plans, asks clarifying questions, and after each build promotes recurring findings into the skill / docs / memory. Co-developing the skill is part of the work.
- **`initialize test mode session`** — build-only, for demos or focused workbook construction. Claude builds quietly using the skill as it currently exists, no skill-modification chatter.

If you don't say either, training mode is the default.

Then describe the dashboard you want, e.g.:

> Use the `Plugs Example Data Model` and the transaction details table to build a customer performance dashboard showing how customers buy across stores and which products are most popular. Save it in my Claude Testing folder.

## What's in the box

| Path | What it does |
|---|---|
| `.claude/settings.json` | Auto-installs upstream `sigma-agent-skills` plugin on first open. |
| `.claude/skills/sigma-workbook-conventions/` | Naming, layout, and POST-time gotchas for the workbook spec API. The main draw of this repo. |
| `.claude/skills/sigma-fin-recon/` | Financial reconciliation workbook pattern (KPIs, page structure, exemplar spec). |
| `workbooks/_template/` | Starter folder — `cp -R` to seed a new dashboard. |
| `workbooks/_exemplars/` | Golden specs harvested from Sigma. Read-only references. |
| `scripts/load-env.sh` | `eval "$(scripts/load-env.sh)"` to load `.env` into the shell. |
| `scripts/refresh-vendor.sh` | Optional: clone a read-only mirror of upstream skills into `vendor/` for inspection while authoring new project skills. |
| `prompts/library/` | Reusable prompt fragments. |
| `docs/` | `conventions.md`, `iteration-playbook.md`, `skill-authoring.md`. |
| `CLAUDE.md` | Project context auto-loaded by Claude Code on every session. |

## Adding a new dashboard

```bash
cp -R workbooks/_template workbooks/my-new-dashboard
```

Then describe what you want; Claude will use the loaded skills to author a `spec.json` and POST it to your Sigma org. See [`docs/iteration-playbook.md`](docs/iteration-playbook.md) for the full iteration loop.

## Authoring a new workbook-pattern skill

See [`docs/skill-authoring.md`](docs/skill-authoring.md). Copy `.claude/skills/sigma-fin-recon/` as a starting point. The pattern: a `SKILL.md` with a sharp frontmatter description, `reference/` split by functional domain, and `examples/` with at least one known-good spec.
