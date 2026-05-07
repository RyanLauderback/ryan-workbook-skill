# Iteration Playbook

Sigma workbook spec JSON is **net-new to LLMs** — not in pretraining data. The
fastest path to one-shot quality is a tight feedback loop where every attempt
becomes evidence and recurring fixes get promoted into skills.

## The loop

```
prompt  ─►  generation  ─►  validate  ─►  diff vs exemplar  ─►  promote learnings
   ▲                                                                  │
   └──────────────────────  refine  ◄─────────────────────────────────┘
```

## Per-attempt protocol

For each attempt at generating or editing a workbook:

1. **Save the prompt verbatim.**
   `workbooks/<name>/prompts/<YYYYMMDD-HHMM>.md`
   Include the full natural-language prompt, plus any reference files you cited
   (paths, not contents).

2. **Save the generated spec.**
   `workbooks/<name>/iterations/<YYYYMMDD-HHMM>.json`
   This is the candidate. Don't overwrite `spec.json` until validation passes.

3. **Validate.**
   - Local: `jq . iterations/<file>.json` to confirm valid JSON.
   - Remote: `scripts/push-workbook.sh create <file>` (new) or
     `update <id> <file>` (existing). Server validation catches schema issues
     LLMs miss.
   - If push succeeds, GET it back and compare — Sigma may have remapped IDs
     (CREATE) or normalized fields. The GET response, not your input, is the
     new source of truth.

4. **Diff vs the closest exemplar.**
   ```bash
   diff <(jq -S . workbooks/_exemplars/<closest>.json) \
        <(jq -S . workbooks/<name>/iterations/<file>.json)
   ```
   Sort keys (`jq -S`) so diffs are stable. Look for missing required elements
   from the relevant skill's `reference/structure.md`.

5. **Record findings in `notes.md`.**
   One row per attempt in the iteration log table. Be terse: what worked, what
   broke, whether anything was promoted.

6. **Commit.**
   `git add workbooks/<name> && git commit -m "iter <name>: <one-line summary>"`
   Each iteration is now in `git log` with diffable history.

## Promotion rule

When a fix recurs across **2+ iterations** in **any** workbook of the same
pattern, promote it:

- Naming/layout fix → `.claude/skills/sigma-workbook-conventions/reference/naming.md`
- Pattern-specific fix (e.g. variance metric formula tweak) →
  `.claude/skills/<pattern-skill>/reference/<topic>.md`
- A spec fragment that consistently produces correct output →
  add it to that skill's `examples/` so future generations few-shot off it.

The point of skills is that recurring knowledge stops being re-invented per
session. If you find yourself re-explaining the same thing in prompts, that's
the signal to promote.

## When to start a new exemplar

When you produce a workbook that would serve as a good reference for future
generations of the same pattern:

```bash
cp workbooks/<name>/spec.json workbooks/_exemplars/<pattern>-<descriptive-name>.json
git add workbooks/_exemplars && git commit -m "exemplar: <pattern> <description>"
```

Exemplars are treated as immutable. Prefer adding new ones over modifying old.

## Anti-patterns to avoid

- **Editing `spec.json` directly without saving the iteration.** You lose the
  evidence of what worked.
- **Letting prompts drift.** If you tweak a prompt across attempts, save each
  variant; a working prompt is reusable.
- **Promoting too eagerly.** A one-time fix isn't a pattern. Wait for it to
  show up twice before promoting.
- **Hand-editing exemplars.** They are anchors. If an exemplar needs an edit,
  it usually means it's wrong — replace it instead.
