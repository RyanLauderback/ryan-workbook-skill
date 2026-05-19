# Skill Evals

Regression test cases for the `sigma-workbook-conventions` skill. Each eval
captures a real session prompt and the expected behavior — used to verify
that skill changes don't quietly break working flows.

## Format

Each eval is a single JSON file: `evals/NN-<name>.json`. Shape follows
Anthropic's skill-evaluation pattern (`{prompt, expected_output, files}`)
plus one Sigma-specific extension (`session_mode`):

```json
{
  "session_mode": "build",
  "prompt": "<verbatim user prompt>",
  "expected_output": "<bulleted behavior + spec criteria>",
  "files": ["evals/NN-<name>.spec.json"]
}
```

| Field | Required | Purpose |
|---|---|---|
| `session_mode` | yes (Sigma extension) | `"build"` or `"training"` — determines whether the 3-gate kickoff fires |
| `prompt` | yes | The verbatim prompt as a user would type it. Includes the destination folder slug when applicable |
| `expected_output` | yes | Prose checklist of what success looks like — behaviors, spec shape criteria, rule adherence |
| `files` | yes | Paths to sibling reference specs (the actual GET-back from a successful run) |

Reference specs (`evals/NN-*.spec.json`) are the full workbook GET-backs.
They're large (often >1k lines) and not meant to match output exactly — the
agent's job is to satisfy the prose `expected_output` criteria, with the
reference spec available as a "what one acceptable shape looked like" anchor.

## Running an eval (manually for now)

1. Open a fresh Claude Code session with this repo as primary working directory.
2. Type `start build mode` (or `start training mode` per `session_mode`).
3. Paste the `prompt` verbatim.
4. Let the session run to completion (Recon → Plan → POST → GET → Verify).
5. Review the resulting workbook against `expected_output`. Each bullet should
   be satisfied.

An auto-runner (`scripts/run-eval.sh`) is out of scope today — these are
manual regression checks until automation is added.

## Maintenance contract

When a skill rule changes, the affected eval's `expected_output` must update
in the **same commit** as the rule change. If a Phase 5+ change makes an
existing eval fail, that's the signal — either the change is wrong or the
eval is stale; one of them needs to move.

Evals are CANONICAL content (no `local-` filename prefix). They live at the
repo root, not under `.claude/skills/` — they're test infrastructure, not
skill content.
