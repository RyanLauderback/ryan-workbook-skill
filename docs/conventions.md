# Project Conventions

Operational conventions for this workspace. For Sigma-spec naming/layout
conventions, see `skills/sigma-workbook-conventions/`.

## Folder responsibilities

| Folder | Mutable? | Purpose |
|--------|----------|---------|
| `skills/sigma-workbook-conventions/` | yes | The canonical, marketplace-publishable skill source (see `.claude-plugin/plugin.json`) — `SKILL.md`, `reference/`, `examples/`, and its bundled `scripts/` (formerly root-level `scripts/api/` + `scripts/*.py`). |
| `.claude/skills/sigma-workbook-conventions/` | yes | Thin stub `SKILL.md` (frontmatter-only trigger) so this checkout's own `.claude/skills/` auto-discovery still fires "start build mode"; points at the canonical copy above. Other project-local workbook-pattern skills also live under `.claude/skills/`. |
| `.cortex/skills/sigma-workbook-conventions/` | generated | Real-file mirror of `SKILL.md`/`reference/`/`examples/` for Cortex Code discovery — regenerate via `skills/sigma-workbook-conventions/scripts/sync-cortex-mirror.py`, never hand-edit. |
| `vendor/` | no | Read-only mirror of upstream `sigma-agent-skills`. Refresh via `scripts/refresh-vendor.sh`. Gitignored. |
| `workbooks/<name>/` | yes | One folder per dashboard. Source of truth = `spec.json`. |
| `workbooks/_exemplars/` | append-only | Golden specs harvested from Sigma. Never edit in place; treat as immutable references. |
| `workbooks/_template/` | rarely | Skeleton copied for new dashboards. Keep generic. |
| `prompts/library/` | yes | Reusable prompt fragments. Markdown only. |
| `scripts/` | yes | Repo-maintainer tools only (`refresh-vendor.sh`). Skill-bundled scripts now live under `skills/sigma-workbook-conventions/scripts/`. |
| `docs/` | yes | This folder. Keep concise. |

## Secrets

- **Browser sign-in, no admin-provisioned credential needed.**
  `eval "$(skills/sigma-workbook-conventions/scripts/api/browser-login.sh)"` runs an OAuth 2.1
  authorization-code + PKCE flow and stores a refresh token in the OS
  keychain (never a workspace file). This is also the only auth path
  Sigma's `/mcp/v2` accepts — see
  `skills/sigma-workbook-conventions/reference/workflows/discover.md`
  → "MCP status". `skills/sigma-workbook-conventions/scripts/api/refresh-token.sh` redeems the stored
  refresh token for repeat sessions with no browser round-trip; point
  `_env.sh` at it via `SIGMA_TOKEN_FETCHER` if desired.
- **Claude Code web injects credentials automatically.** The platform sets
  `SIGMA_CLIENT_ID`/`SIGMA_CLIENT_SECRET`/`SIGMA_BASE_URL` as already-
  exported env vars before the session starts — no file, no user setup, and
  no browser to redirect to in that execution context.
- Token retrieval is owned by the skill: `skills/sigma-workbook-conventions/scripts/api/_env.sh` uses an
  already-exported `SIGMA_API_TOKEN` if present (e.g. from
  `browser-login.sh`); otherwise, if the client-credentials vars above are
  already exported, it shells out to `skills/sigma-workbook-conventions/scripts/api/get-token.sh` (a ~30-line
  `client_credentials` exchange against `/v2/auth/token`) and caches the
  token at a per-user `$SIGMA_TOKEN_CACHE` path for 55 min. Override with
  `SIGMA_TOKEN_FETCHER=/path/to/fetcher.sh` if you want to use the upstream
  `sigma-api` plugin's fetcher, or `refresh-token.sh`, instead.
- Never paste a token into a prompt, comment, file, or commit message.

## Platform support

Targets **macOS, Linux (including containerized/CI hosts and Claude Code
web), Windows via WSL, and native Windows.** CI (`.github/workflows/ci.yml`)
runs the full offline test surface on `ubuntu-latest`, `macos-latest`, and
`windows-latest` on every push/PR — this is what makes the native-Windows
claim below enforced rather than aspirational.

Native Windows support is split by layer:

- **Pure-Python tooling** — `scripts/validate-spec.py`,
  `scripts/workbook-manifest.py`, `scripts/sigma-resolve.py`,
  `scripts/sync-cortex-mirror.py` — runs natively on Windows: `pathlib`
  throughout, explicit `encoding="utf-8"` on every file open, no symlinks,
  no bash dependency. Invoke with whatever Python is on `PATH` there
  (typically `python`, sometimes `py -3` — see below).
- **The bash-based `scripts/api/*` layer** (auth, discovery, workbook
  publish) still requires a real bash — either **WSL** or **Git Bash**
  (ships with Git for Windows, and is what GitHub's own `windows-latest`
  CI runner uses by default for `shell: bash` steps). This is not a
  "not supported" gap, just a "needs one of these two, not native
  PowerShell/cmd" one: `scripts/api/_env.sh` hard-requires `$BASH_SOURCE`
  and uses `export -f` (bash-only), and `scripts/api/browser-login.sh`
  uses `/dev/tcp`, `/dev/tty`, job control, and an OS keychain CLI
  (`security` on macOS, `secret-tool` on Linux) with no Windows
  equivalent — porting that auth layer to PowerShell is a deliberate
  non-goal (see `reference/history.md` → "2026-08-03" for the portability
  decision this builds on). All scripts use `#!/usr/bin/env bash` and are
  bash-3.2-safe (no associative arrays, `mapfile`, or other bash-4+-only
  constructs), so they run unmodified on macOS's stock bash, Linux/WSL,
  and Git Bash alike.
- A `$SIGMA_PYTHON` shim (resolved once in `_env.sh`, threaded through
  every `scripts/api/*.sh` and `scripts/doctor.sh` call site) means that
  if the bash layer's Git Bash/WSL requirement is ever lifted for some
  future host where the interpreter isn't named `python3`, that's a
  one-line change in `_env.sh`, not a per-call-site find-replace.

Clone the repo inside the WSL filesystem (e.g. `~/...`), not on a
Windows-native drive mounted via DrvFs (`/mnt/c/...`), if using WSL —
DrvFs doesn't reliably preserve the executable bit on
`skills/sigma-workbook-conventions/scripts/api/*.sh`, though
`.claude/settings.json`'s `bash skills/sigma-workbook-conventions/scripts/api/*`
allow entries are a fallback if you end up there anyway.

Run `bash skills/sigma-workbook-conventions/scripts/doctor.sh` first on an
unfamiliar host (macOS/Linux/WSL/Git Bash) — it checks for required
binaries, resolves which `python3`/interpreter would actually be used,
reports the OS (including a Git Bash/MSYS/Cygwin-specific branch, not just
a generic "unrecognized platform" warning), and does a cheap auth-config
sanity check.

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
