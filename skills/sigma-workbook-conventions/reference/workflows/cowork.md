# Claude Cowork Compatibility

What changes when this skill runs inside a **Claude Cowork** session
instead of the Claude Code CLI, and why that's the *whole* list of
changes. Load this before or during a Cowork session, or when advising a
user who says they're running this skill from Cowork.

## Table of contents

- [What's different about Cowork as a host](#whats-different-about-cowork-as-a-host)
- [Two-phase browser sign-in](#two-phase-browser-sign-in)
- [Egress prerequisite (org-admin action)](#egress-prerequisite-org-admin-action)
- [Independent gates: Sigma MCP connector vs. shell egress](#independent-gates-sigma-mcp-connector-vs-shell-egress)
- [Delivery: ZIP vs. mounted clone](#delivery-zip-vs-mounted-clone)
- [Where to start on an unfamiliar Cowork session](#where-to-start-on-an-unfamiliar-cowork-session)

## What's different about Cowork as a host

| Aspect | Claude Code CLI | Claude Cowork |
|---|---|---|
| Shell | Persistent local shell on the user's machine | Isolated shell on Anthropic's servers, separate from the user's computer and network |
| tty | Present | Absent — no `/dev/tty`, no controlling terminal; a script that blocks on `read` from a terminal fails |
| OS keychain | `security` (macOS) / `secret-tool` (Linux) available | Neither exists in the sandbox |
| Env vars across tool calls | Persist for the session's shell | Do **not** persist between separate bash tool calls |
| Personal skill discovery | `.claude/skills/` auto-discovered from the mounted repo | Not auto-discovered — personal skills load from a ZIP uploaded to `claude.ai/customize/skills` |
| Outbound network | Direct | Routed through a forward proxy enforcing an **org-admin-controlled domain allowlist** |

**Confirmed live** (repo owner, real Cowork session): egress fails
closed — a blocked host returns `403` with response header
`X-Proxy-Error: blocked-by-allowlist` (hostname-based; a bare IP is
blocked too, so pinning to an IP is not a workaround). In that org,
`api.sigmacomputing.com` and `app.sigmacomputing.com` were **already**
allowlisted and returned genuine Sigma responses (`401` with
`www-authenticate` on `/v2/whoami`; a real `invalid_request` from
`/v2/auth/token`) — proof the mechanism works end-to-end once an org has
allowlisted the right hosts, not just a theory.

That table is the entire story. Everything else this skill does — the
`/v2/workbooks/spec` REST API, the JSON spec format, `validate-spec.py`,
`publish-workbook.sh`, every convention rule in `reference/conventions.md`
and the `specification/` chunks — runs identically. Cowork is just a
different host running the exact same scripts; only the two seams that
depend on a human-facing browser and a local credential store (auth) and
folder-based skill discovery (delivery) need a variant.

**Explicitly out of scope:** the "Sigma Build MCP" (an internal-staging-only
tool that replaces JSON-spec authoring with a Python SDK program) is not
part of this compatibility effort. This document is about keeping the
existing REST + browser-OAuth + JSON-spec skill working under Cowork, not
switching to a different authoring mechanism.

## Two-phase browser sign-in

`scripts/api/browser-login.sh` auto-detects a headless environment (no
tty — see `_state.sh`'s `is_headless()`) and switches from the single
interactive call CLI users get into a two-call pattern. This is the only
part of the auth flow that differs; everything downstream (`whoami.sh`,
the 2-question kickoff gate, Recon → Plan → POST → GET → Visual verify)
is unchanged.

- **`browser-login.sh --start`** (or a plain no-arg call — headless is
  auto-detected) runs OAuth discovery and client registration and prints
  an **authorize URL to stdout**, then exits immediately. It does not
  wait, does not open a browser itself (there is nothing to open a
  browser *from*, inside the sandbox), and does not bind a loopback
  listener (the user's own browser redirects to *their* localhost, which
  the sandbox can never see). State needed to complete the flow
  (PKCE verifier, CSRF state, client ID, token URL) is saved to a `0600`
  file so the second call can pick it up — env vars set in this call
  would not survive into the next bash tool invocation.
- **`browser-login.sh --finish "<pasted-callback-url>"`** loads that
  saved state, verifies the CSRF `state` parameter, exchanges the code,
  persists the refresh token, and prints `export SIGMA_API_TOKEN=...`.

Token persistence in this mode falls back to a third tier (see
`_state.sh`): a `0600` file under `$SIGMA_STATE_DIR` (default
`${XDG_STATE_HOME:-$HOME/.local/state}/sigma-workbook-skill`), since
there's no OS keychain to write to. This is what lets `refresh-token.sh`
mint fresh access tokens on later calls with no further browser
round-trip — without it, every single Cowork tool call would otherwise
demand a fresh browser sign-in, since env vars don't survive between
them either.

### Worked example

```
User: start build mode

Claude: [SIGMA_BASE_URL already set; no SIGMA_API_TOKEN or client-creds
         exported yet, so auth resolution falls to browser-login.sh]
        [browser-login.sh detects no tty -> headless mode, runs --start]

        Claude relays this verbatim into chat:

          Open this URL, sign in, and approve:
            https://<auth-server>.sigmacomputing.com/oauth/authorize?...

          Your browser will then try to load an address that fails to
          connect -- that's expected (nothing is listening there in a
          sandbox). Copy the FULL failed redirect URL and paste it back
          here.

        [ends the turn -- there is no way to proceed without the user's
         pasted URL, so this is a hard stop, not a rhetorical pause]

User: [opens the URL, signs in, approves, copies the address bar of the
       page that failed to load, pastes it back]
      https://127.0.0.1:54321/oauth/callback?code=abc123&state=xyz789

Claude: [runs browser-login.sh --finish 'https://127.0.0.1:54321/oauth/callback?code=abc123&state=xyz789']
        -> exchanges the code, persists the refresh token to the file
           tier under $SIGMA_STATE_DIR, prints `export SIGMA_API_TOKEN=...`
        [runs whoami.sh to confirm against the live API]
        -> "Authenticated to api.sigmacomputing.com. Recent files: ..."
        [proceeds to the 2-question kickoff gate exactly as in
         SKILL.md -> "Session kickoff"]
```

On any later call in the same Cowork session, auth resolution is
automatic again: `_env.sh` falls back to `refresh-token.sh`, which reads
the file-tier credentials and mints a new access token with no further
browser round-trip — same mechanism as a returning CLI session, just
reading from the file tier instead of the keychain.

## Egress prerequisite (org-admin action)

None of the above matters if the sandbox's forward proxy blocks the
Sigma API host — this is a customer prerequisite, not something this
skill can fix in code. An org Owner/Admin must allowlist the relevant
host(s) under **Admin settings → Capabilities** before a Cowork session
can reach Sigma at all.

The complete set of hosts `browser-login.sh` will ever connect to for
the REST API + OAuth discovery/token exchange (this is the full region
list the script itself pins — see its `SIGMA_BASE_URL` case statement):

```
https://aws-api.sigmacomputing.com
https://api.us-a.aws.sigmacomputing.com
https://api.ca.aws.sigmacomputing.com
https://api.eu.aws.sigmacomputing.com
https://api.au.aws.sigmacomputing.com
https://api.uk.aws.sigmacomputing.com
https://api.us.azure.sigmacomputing.com
https://api.eu.azure.sigmacomputing.com
https://api.ca.azure.sigmacomputing.com
https://api.uk.azure.sigmacomputing.com
https://api.au.azure.sigmacomputing.com
https://api.sigmacomputing.com
https://api.sa.gcp.sigmacomputing.com
```

Plus `https://help.sigmacomputing.com` — used for OpenAPI/function-reference
lookups (see `reference/specification/formulas.md` → "Looking up Sigma
functions" and CLAUDE.md → "Sigma documentation lookups via native MCP").
An org only needs its **one** actual region/host allowlisted, not all 13 —
the list above is complete only in the sense that it's every host the
script's own region picker offers, not a recommendation to allowlist all
of them.

**Caveat an admin will hit if they stop at the API host.** The OAuth
*authorization server* is discovered dynamically at runtime — from the
`WWW-Authenticate` challenge on `/v2/whoami`, then
`.well-known/oauth-authorization-server` — and this skill only asserts
it ends in `.sigmacomputing.com` (see `assert_sigma_host()` in
`browser-login.sh`), not that it's the same host as the API host. An
admin who allowlists only `api.*` may still see sign-in fail at the
`--start` step with a proxy 403 on the authorize URL. `--start`'s printed
authorize URL reveals the actual authorization-server host — if sign-in
fails after allowlisting only the API host, check that URL's hostname and
allowlist it too.

## Independent gates: Sigma MCP connector vs. shell egress

This is a **different** risk from the one `reference/workflows/discover.md`
→ "MCP status" already warns about, and it's worth keeping the two
straight:

- **`discover.md`'s existing warning** is about *which Sigma org* a native
  claude.ai-side connector (`mcp__claude_ai_Sigma_MCP__*`) is authenticated
  to — it can silently point at a different org than this skill's own
  `browser-login.sh` auth resolved, with near-identical demo data masking
  the mismatch. That's an **authentication/identity** concern.
- **This section's concern is the network path**, not identity. A
  connected Sigma MCP connector authenticates and calls Sigma from
  Anthropic's own backend — never through the Cowork sandbox's shell
  proxy. A working MCP connector does **not** imply `curl`/`bash` calls
  from this skill's `scripts/api/*.sh` will reach Sigma, and a passing
  egress check does not imply an MCP connector (if one happens to be
  present) is authenticated correctly, or to the org the user means.

Don't let a working connector stand in for a shell-egress check, and
don't let a passing shell-egress check stand in for confirming which org
an MCP connector is pointed at — they're independent gates, and this
skill's own auth (`browser-login.sh`/`whoami.sh`) is unaffected by either.

## Delivery: ZIP vs. mounted clone

Cowork does not auto-discover `.claude/skills/` from a mounted folder the
way Claude Code does. Two things ship together, not as alternatives:

- **The ZIP (primary delivery).** Build it with
  `skills/sigma-workbook-conventions/scripts/package-skill.sh`
  (packages `skills/sigma-workbook-conventions/`, which already bundles
  its own `scripts/` — including this one, the same way it already bundles
  `sync-cortex-mirror.py` — so the archive is self-contained) and upload it at
  `claude.ai/customize/skills`. This is what makes `start build mode`
  auto-trigger in a Cowork session — the same trigger mechanism as any
  other personal skill.
- **The mounted clone still matters as the working folder.** Even with
  the ZIP uploaded, open/mount this repo as the Cowork session's working
  directory — that's where `workbooks/<name>/` (spec.json, prompts/,
  iterations/, notes.md), `prompts/library/`, and this repo's own
  `examples/`/`_exemplars/` live. The ZIP supplies the skill's
  instructions and scripts; the clone supplies the per-dashboard state
  this skill's iteration loop depends on (see CLAUDE.md → "Iteration
  loop").

Keep the ZIP and the clone in sync — a stale ZIP against an updated
clone drifts silently, since the ZIP is what actually auto-triggers.
Rebuild and re-upload the ZIP after any change to
`skills/sigma-workbook-conventions/`.

## Where to start on an unfamiliar Cowork session

Run `scripts/doctor.sh` first — it has an egress preflight that
specifically recognizes the `403` / `X-Proxy-Error: blocked-by-allowlist`
signature and prints the Admin-settings remediation above, instead of a
raw curl error, so a misconfigured org fails in the first few seconds
with an actionable message rather than mid-build. Then follow
`SKILL.md` → "Auth resolution (automatic — not a question)" for the
full auth-resolution ladder, of which the two-phase flow above is just
the headless branch.
