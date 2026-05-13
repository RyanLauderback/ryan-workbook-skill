# Authoring a Workbook-Pattern Skill

A workbook-pattern skill encodes "what does a {revenue dashboard, ops
control tower, financial reconciliation, …} workbook look like in Sigma." It is
the single most leveraged thing you can build in this repo — domain skills are
how we get one-shot quality on dashboards Sigma's generic skills can't predict.

## When to create a new skill

Create one when you've generated 2–3 workbooks of the same pattern and noticed
the same scaffolding ("standard pages: overview / trend / detail / exceptions",
"these 6 KPIs always appear", etc.). Until then, just use
`sigma-workbook-conventions` plus `sigma-data-models`.

## Pattern (mirrors Sigma's own)

```
.claude/skills/<your-skill-name>/
├── SKILL.md             # frontmatter + body
├── reference/
│   ├── structure.md     # canonical pages + element checklist
│   ├── kpis.md          # canonical metric definitions
│   └── <other>.md       # anything domain-specific (e.g. tax-rules.md)
└── examples/
    └── exemplar-spec.json   # at least one known-good spec
```

## Step-by-step

1. **Scaffold the directory.**
   ```bash
   mkdir -p .claude/skills/<your-skill>/reference .claude/skills/<your-skill>/examples
   ```
   Then create the `SKILL.md`, `reference/structure.md`, `reference/kpis.md`,
   and `examples/exemplar-spec.json` files following the tree above.

2. **Write a sharp `description:` in the frontmatter.** This is what Claude
   uses to decide whether to activate the skill. The description should:
   - Lead with "Use when…" + concrete trigger phrases
   - Name the artifacts/concepts (KPIs, page types) that distinguish this pattern
   - State prerequisites (typically `sigma-api`, `sigma-data-models`, and `sigma-workbook-conventions`)
   - Say what it does NOT cover, if there's a near-neighbor pattern

   Compare to the upstream `sigma-data-models` description in
   `vendor/sigma-agent-skills/skills/sigma-data-models/SKILL.md` — match that
   density.

3. **Document canonical structure** in `reference/structure.md`. List every
   page with required and optional elements, plus folder groupings, sources,
   and relationships. Mark required elements explicitly.

4. **Document canonical KPIs** in `reference/kpis.md` as a table: ID, formula,
   format, dependencies. Use Sigma function syntax for formulas.

5. **Drop a real exemplar** into `examples/exemplar-spec.json`. GET it from
   the Sigma REST API: `GET /v2/workbooks/{workbookId}/spec` with header
   `Accept: application/json`, then save the response body. The skill works
   without one but is much sharper with it.

6. **Test activation.** In a fresh Claude Code session, ask for a workbook of
   that pattern and verify the skill activates. If it doesn't, the
   `description:` is the most likely culprit — make trigger phrases more
   concrete.

7. **Commit.** Then iterate via the playbook in `iteration-playbook.md`.

## Quality bar

A good workbook-pattern skill should:

- Say `Use when…` clearly enough that Claude picks it without prompting.
- Have a `reference/` that fits on screen — if it's a wall of text, split it.
- Have at least one exemplar.
- Defer to `sigma-data-models` for field-level mechanics rather than restating them.
- Defer to `sigma-workbook-conventions` for naming/layout rather than restating them.

A weak skill restates the upstream skills and gives no domain-specific
structure. If your skill doesn't say something the upstream skills don't,
you don't need it yet.
