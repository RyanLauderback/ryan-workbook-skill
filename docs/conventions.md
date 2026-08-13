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

- **Browser sign-in, no admin-provisioned credential needed.**
  `eval "$(scripts/api/browser-login.sh)"` runs an OAuth 2.1
  authorization-code + PKCE flow and stores a refresh token in the OS
  keychain (never a workspace file). This is also the only auth path
  Sigma's `/mcp/v2` accepts — see
  `.claude/skills/sigma-workbook-conventions/reference/workflows/discover.md`
  → "MCP status". `scripts/api/refresh-token.sh` redeems the stored
  refresh token for repeat sessions with no browser round-trip; point
  `_env.sh` at it via `SIGMA_TOKEN_FETCHER` if desired.
- **Claude Code web injects credentials automatically.** The platform sets
  `SIGMA_CLIENT_ID`/`SIGMA_CLIENT_SECRET`/`SIGMA_BASE_URL` as already-
  exported env vars before the session starts — no file, no user setup, and
  no browser to redirect to in that execution context.
- Token retrieval is owned by the skill: `scripts/api/_env.sh` uses an
  already-exported `SIGMA_API_TOKEN` if present (e.g. from
  `browser-login.sh`); otherwise, if the client-credentials vars above are
  already exported, it shells out to `scripts/api/get-token.sh` (a ~30-line
  `client_credentials` exchange against `/v2/auth/token`) and caches the
  token at a per-user `$SIGMA_TOKEN_CACHE` path for 55 min. Override with
  `SIGMA_TOKEN_FETCHER=/path/to/fetcher.sh` if you want to use the upstream
  `sigma-api` plugin's fetcher, or `refresh-token.sh`, instead.
- Never paste a token into a prompt, comment, file, or commit message.

## Platform support

Targets **macOS, Linux (including containerized/CI hosts and Claude Code
web), and Windows via WSL.** All scripts use `#!/usr/bin/env bash` and are
bash-3.2-safe (no associative arrays, `mapfile`, or other bash-4+-only
constructs), so they run unmodified on macOS's stock bash as well as
Linux/WSL. **Native Windows (outside WSL) is not supported** — `python3`
isn't reliably on PATH there (it's `python.exe`/`py -3`, or a
Microsoft-Store stub that opens the Store instead of running), and every
script hardcodes `python3`. Clone the repo inside the WSL filesystem
(e.g. `~/...`), not on a Windows-native drive mounted via DrvFs
(`/mnt/c/...`) — DrvFs doesn't reliably preserve the executable bit on
`scripts/api/*.sh`, though `.claude/settings.json`'s `bash scripts/api/*`
allow entries are a fallback if you end up there anyway.

Run `bash scripts/doctor.sh` first on an unfamiliar host — it checks for
required binaries, resolves which `python3`/interpreter would actually be
used, and reports the OS, before you run anything that touches the API.

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
