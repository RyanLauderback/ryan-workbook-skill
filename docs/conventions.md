# Project Conventions

Operational conventions for this workspace. For Sigma-spec naming/layout
conventions, see `.claude/skills/sigma-workbook-conventions/`.

## Folder responsibilities

| Folder | Mutable? | Purpose |
|--------|----------|---------|
| `.claude/skills/` | yes | Project-local workbook-pattern skills. Edit freely. |
| `vendor/` | no | Read-only mirror of upstream `sigma-agent-skills`. Refresh via `scripts/refresh-vendor.sh`. Gitignored. |
| `workbooks/<name>/` | yes | One folder per dashboard. Source of truth = `spec.json`. |
| `workbooks/_exemplars/` | append-only | Golden specs harvested from Sigma. Never edit in place; treat as immutable references. |
| `workbooks/_template/` | rarely | Skeleton copied for new dashboards. Keep generic. |
| `prompts/library/` | yes | Reusable prompt fragments. Markdown only. |
| `scripts/` | yes | Shell helpers. Keep thin — defer logic to skills. |
| `docs/` | yes | This folder. Keep concise. |

## Secrets

- All secrets live in `.env` (gitignored). `.env.example` documents the contract.
- Source via `eval "$(scripts/load-env.sh)"`. The script never echoes values.
- Token retrieval is delegated to the upstream `sigma-api` skill.
- Never paste a token into a prompt, comment, file, or commit message.

## Git hygiene

- Commit per iteration when working on a dashboard, so `git log` doubles as the
  iteration history.
- Avoid committing iteration scratch files; use `.draft.json` or `.tmp` suffixes
  (already gitignored).
- `.claude/settings.json` is committed (team default). `.claude/settings.local.json`
  is gitignored (personal overrides).
- Don't commit `vendor/`. It's gitignored — refresh on demand.

## Adding a new workbook

```bash
cp -R workbooks/_template workbooks/<dashboard-name>
```

Then describe the dashboard to Claude. The `sigma-workbook-conventions` skill
activates automatically; any domain-pattern skill you've authored (see
`skill-authoring.md`) also activates based on its `description:` frontmatter.

## Adding a new workbook-pattern skill

See `skill-authoring.md`.

## Iterating on Sigma generations

See `iteration-playbook.md`.
